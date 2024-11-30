/// grabs the main Lua instance from the event loop
pub fn getLua(loop: *xev.Loop) *Lua {
    const s: *Seamstress = @fieldParentPtr("loop", loop);
    return s.lua;
}

/// grabs the core seamstress object
/// panics on failure
/// stack effect: 0
pub fn getSeamstress(l: *Lua) *Seamstress {
    load(l, "seamstress");
    const seamstress = l.toUserdata(Seamstress, -1) catch panic("unable to get handle to seamstress object!", .{});
    l.pop(1);
    return seamstress;
}

/// adds the closure on top of the stack to the array of exit handlers
/// panics if unable to get the upvalue
/// stack effect: -1 (removes the handler)
pub fn addExitHandler(l: *Lua, which: enum { panic, stop }) void {
    if (l.getTop() == 0) panic("no exit handler on the stack!", .{});
    _ = l.getMetatableRegistry("seamstress");
    _ = l.getField(-1, switch (which) {
        .panic => "panic",
        .stop => "stop",
    });
    l.remove(-2);
    _ = l.getUpvalue(-1, 1) catch panic("unable to get exit function upvalue!", .{});
    l.remove(-2);
    l.rotate(-2, 1); // move the table under the function
    l.setIndex(-2, @intCast(l.rawLen(-2) + 1));
    l.pop(1);
}

/// loads the given seamstress module, e.g. "seamstress" or "seamstress.event".
/// returns an error if the module list does not contain the provided module name.
/// stack effect: +1 (the table returned by loading the module)
pub const load = @import("modules.zig").load;

/// pushes seamstress.event.publish onto the stack
/// also pushes the strings given as the namespace as the first argument
/// if namespace is empty, does nothing!
/// stack effect: +2: `seamstress.event.publish` and a table containing the strings in namespace
pub fn preparePublish(l: *Lua, namespace: []const []const u8) void {
    if (namespace.len == 0) return;
    load(l, "seamstress.event");
    _ = l.getField(-1, "publish");
    l.remove(-2);
    l.createTable(@intCast(namespace.len), 0);
    for (namespace, 1..) |name, i| {
        _ = l.pushString(name);
        l.setIndex(-2, @intCast(i));
    }
}

/// reports the error message on top of the stack by publishing an error event
/// stack effect: -1 (pops the error message)
/// panics on failure
pub fn reportError(l: *Lua) void {
    const msg = l.toStringEx(-1);
    std.log.scoped(.lua).err("{s}", .{msg});
    preparePublish(l, &.{"error"});
    l.rotate(-3, -1);
    doCall(l, 2, 0) catch {
        panic("error while reporting the following error: {s}\n{s}", .{ msg, l.toStringEx(-1) });
    };
}

/// call print; prints n values, clearing the stack if n is null or greater than the height of the stack.
pub fn luaPrint(l: *Lua, n: ?i32) !void {
    const m = l.getTop();
    if (m == 0) return;
    const num_args = if (n) |inner| @min(inner, m) else m;
    _ = try l.getGlobal("print");
    // put print where we can call it
    l.insert(-num_args - 1);
    try doCall(l, num_args, 0);
}

const BufferWriter = std.io.GenericWriter(*ziglua.Buffer, error{}, bufferWrite);
pub const LuaWriter = std.io.BufferedWriter(4096, BufferWriter);

fn bufferWrite(buf: *ziglua.Buffer, bytes: []const u8) error{}!usize {
    buf.addString(bytes);
    return bytes.len;
}

pub fn luaWriter(buf: *ziglua.Buffer) LuaWriter {
    const writer: BufferWriter = .{ .context = buf };
    return std.io.bufferedWriter(writer);
}

/// uses a Buffer object to print to a lua string
/// stack effect: +1 (the newly created string)
pub fn format(l: *Lua, comptime fmt: []const u8, args: anytype) void {
    var buf: ziglua.Buffer = undefined;
    buf.init(l);
    var bw = luaWriter(&buf);
    bw.writer().print(fmt, args) catch unreachable;
    bw.flush() catch unreachable;
    buf.pushResult();
}

/// a wrapper around `pcall`
/// returns an error to signal function failure; `catch reportError(l)`
/// is often correct if the way Lua handles errors from pcall is sufficient
pub fn doCall(l: *Lua, nargs: i32, nres: i32) error{LuaFunctionFailed}!void {
    const base = l.getTop() - nargs;
    l.pushLightUserdata(@ptrFromInt(@returnAddress()));
    l.pushClosure(ziglua.wrap(struct {
        /// adds a stack trace to the error message on top of the stack
        fn messageHandler(lua: *Lua) i32 {
            const return_address = @intFromPtr(lua.toUserdata(anyopaque, Lua.upvalueIndex(1)) catch unreachable);
            const msg = switch (lua.typeOf(1)) {
                .string => lua.toString(1) catch unreachable,
                else => msg: {
                    format(lua, "error object is an {s} value: {s}", .{ lua.typeName(lua.typeOf(1)), lua.toStringEx(1) });
                    break :msg lua.toString(-1) catch unreachable;
                },
            };
            lua.traceback(lua, msg, 1);
            var buf: ziglua.Buffer = undefined;
            buf.init(lua);
            lua.rotate(-2, 1);
            buf.addValue();
            buf.addChar('\n');
            var bw = luaWriter(&buf);
            blk: {
                const info = std.debug.getSelfDebugInfo() catch break :blk;
                std.debug.writeCurrentStackTrace(bw.writer(), info, .no_color, return_address) catch unreachable;
                bw.flush() catch unreachable;
            }
            buf.pushResult();
            return 1;
        }
    }.messageHandler), 1);
    l.insert(base);
    const ret = l.protectedCall(nargs, nres, base) catch error.LuaFunctionFailed;
    l.remove(base);
    return ret;
}

/// determines whether the value on the stack at the given index may be called
pub fn isCallable(l: *Lua, index: i32) bool {
    switch (l.typeOf(index)) {
        .function => return true,
        .table, .userdata => {
            var ret = true;
            _ = l.getMetaField(index, "__call") catch {
                ret = false;
            };
            l.pop(1);
            return ret;
        },
        else => return false,
    }
}

/// raises a lua error if the function argument at the given index is not callable
pub fn checkCallable(l: *Lua, argument: i32) void {
    if (!isCallable(l, argument)) l.typeError(argument, "callable value");
}

/// converts a userdata pointer (as in an xev callback)
/// into a handle suitable for using with the Lua registry table
pub fn handleFromPtr(ptr: ?*anyopaque) i32 {
    const num = @intFromPtr(ptr);
    const @"u32": u32 = @intCast(num);
    return @bitCast(@"u32");
}

/// converts a Lua registry handle (from Lua.ref)
/// into a userdata pointer for using with xev callbacks
pub fn ptrFromHandle(handle: i32) ?*anyopaque {
    const @"u32": u32 = @bitCast(handle);
    const num: usize = @"u32";
    return @ptrFromInt(num);
}

/// for use as an xev callback for a cancel operation;
/// pass it ptrFromHandle(handle) after calling Lua.ref
pub fn unrefCallback(ud: ?*anyopaque, loop: *xev.Loop, _: *xev.Completion, result: xev.Result) xev.CallbackAction {
    const l = getLua(loop);
    const top = if (builtin.mode == .Debug) l.getTop();
    defer if (builtin.mode == .Debug) std.debug.assert(top == l.getTop()); // stack must be unchanged
    l.unref(ziglua.registry_index, handleFromPtr(ud)); // release the reference
    _ = result.cancel catch |err| {
        _ = l.pushFString("unable to cancel: %s", .{@errorName(err).ptr});
        reportError(l);
    };
    return .disarm;
}

pub fn allocator(l: *Lua) std.mem.Allocator {
    return if (@hasDecl(@import("root"), "main"))
        l.allocator()
    else
        std.heap.c_allocator;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Seamstress = @import("seamstress.zig");
const xev = @import("xev");
