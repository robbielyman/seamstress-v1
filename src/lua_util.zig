/// quits seamstress (by running the quit handlers)
pub fn quit(l: *Lua) void {
    _ = l.getMetatableRegistry("seamstress");
    _ = l.getField(-1, "__quit");
    doCall(l, 0, 0) catch {
        panic("error while quitting! {s}", .{l.toString(-1) catch unreachable});
    };
    load(l, "seamstress") catch unreachable;
    // replace seamstress.quit so that calling seamstress.quit() is idempotent
    l.pushFunction(ziglua.wrap(struct {
        fn f(_: *Lua) i32 {
            return 0;
        }
    }.f));
    l.setField(-2, "quit");
    l.pop(1);
}

/// grabs the main Lua instance from the event loop
pub fn getLua(loop: *xev.Loop) *Lua {
    const s: *Seamstress = @fieldParentPtr("loop", loop);
    return s.lua;
}

/// grabs the core seamstress object
/// panics on failure
/// stack effect: 0
pub fn getSeamstress(l: *Lua) *Seamstress {
    _ = l.getMetatableRegistry("seamstress");
    _ = l.getField(-1, "__seamstress");
    const seamstress = l.toUserdata(Seamstress, -1) catch panic("unable to get handle to seamstress object!", .{});
    l.pop(2);
    return seamstress;
}

/// adds the closure on top of the stack to the array of exit handlers
/// panics if unable to get the upvalue
/// stack effect: -1 (removes the handler)
pub fn addExitHandler(l: *Lua, which: enum { panic, quit }) void {
    if (l.getTop() == 0) panic("no exit handler on the stack!", .{});
    _ = l.getMetatableRegistry("seamstress");
    _ = l.getField(-1, switch (which) {
        .panic => "__panic",
        .quit => "__quit",
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
pub fn preparePublish(l: *Lua, namespace: []const []const u8) !void {
    if (namespace.len == 0) return;
    try load(l, "seamstress.event");
    _ = l.getField(-1, "publish");
    l.remove(-2);
    if (!isCallable(l, -1)) return error.EventPublishNotCallable;
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
    l.pop(1);
    std.log.scoped(.lua).err("{s}", .{msg});
    preparePublish(l, &.{"error"}) catch {
        panic("unable to report the following error: {s}", .{msg});
    };
    _ = l.pushString(msg);
    doCall(l, 2, 0) catch {
        panic("error while reporting the following error: {s}", .{msg});
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

/// a wrapper around `pcall`
/// returns an error to signal function failure; `catch reportError(l)`
/// is often correct if the way Lua handles errors from pcall is sufficient
pub fn doCall(l: *Lua, nargs: i32, nres: i32) error{LuaFunctionFailed}!void {
    const base = l.getTop() - nargs;
    l.pushFunction(ziglua.wrap(struct {
        /// adds a stack trace to the error message on top of the stack
        fn messageHandler(lua: *Lua) i32 {
            switch (lua.typeOf(1)) {
                .string => {
                    const msg = lua.toString(1) catch unreachable;
                    lua.traceback(lua, msg, 1);
                },
                else => {
                    var buf: ziglua.Buffer = undefined;
                    buf.init(lua);
                    buf.addStringZ("error object is an ");
                    buf.addStringZ(lua.typeName(lua.typeOf(1)));
                    buf.addStringZ(" value: ");
                    buf.addStringZ(lua.toStringEx(1));
                    buf.pushResult();
                    const msg = lua.toString(1) catch unreachable;
                    lua.traceback(lua, msg, 1);
                },
            }
            return 1;
        }
    }.messageHandler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        return error.LuaFunctionFailed;
    };
    l.remove(base);
}

/// processes the buffer as plaintext Lua code
/// returns `false` when the chunk fails to compile because it is incomplete
/// otherwise returns `true` or an error
/// stack effect: essentially arbitrary: usually you should subsequently call `print`
pub fn processChunk(l: *Lua, buffer: []const u8) !bool {
    // add "return" to the beginning of the buffer
    const with_return = try std.fmt.allocPrint(l.allocator(), "return {s}", .{buffer});
    defer l.allocator().free(with_return);
    // loads the chunk...
    l.loadBuffer(with_return, "=stdin", .text) catch |err| {
        // ... if the chunk does not compile
        switch (err) {
            error.Memory => return error.OutOfMemory,
            error.Syntax => {
                // remove the error message
                l.pop(1);
                // load the original buffer
                l.loadBuffer(buffer, "=stdin", .text) catch |err2| switch (err2) {
                    error.Memory => return error.OutOfMemory,
                    error.Syntax => {
                        const msg = l.toStringEx(-1);
                        // does the syntax error tell us the statement isn't finished?
                        if (std.mem.endsWith(u8, msg, "<eof>")) {
                            l.pop(1);
                            // false means we're not done
                            return false;
                        } else {
                            // return an error to signal the syntax error
                            return error.LuaSyntaxError;
                        }
                    },
                };
            },
        }
        // call the compiled function
        try doCall(l, 0, ziglua.mult_return);
        // true means we're done
        return true;
    };
    // ... the chunk compiles fine with "return " added!
    // call the compiled function
    try doCall(l, 0, ziglua.mult_return);
    // true means we're done
    return true;
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

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Seamstress = @import("seamstress.zig");
const xev = @import("xev");
