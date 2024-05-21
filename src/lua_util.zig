/// a collection of convenience functions intended to make module code easier to write
/// checks that the function has the specified number of arguments
pub fn checkNumArgs(l: *Lua, n: usize) void {
    if (l.getTop() != n) l.raiseErrorStr("error: requires %d arguments", .{n});
}

/// registers a closure as _seamstress.field_name
/// we're using closures instead of global state!
/// makes me feel fancy
/// the closure has one "upvalue" in Lua terms: ptr
pub fn registerSeamstress(l: *Lua, field_name: [:0]const u8, comptime f: ziglua.ZigFn, ptr: *anyopaque) void {
    // pushes _seamstress onto the stack
    getSeamstress(l);
    // pushes our upvalue
    l.pushLightUserdata(ptr);
    // creates the function (consuming the upvalue)
    l.pushClosure(ziglua.wrap(f), 1);
    // assigns it to _seamstress.field_name
    l.setField(-2, field_name);
    // and removes _seamstress from the stack
    l.pop(1);
}

/// must be called within a closure registered with `registerSeamstress`.
/// gets the one upvalue associated with the closure
/// returns null on failure
pub fn closureGetContext(l: *Lua, comptime T: type) ?*T {
    const idx = Lua.upvalueIndex(1);
    const ctx = l.toUserdata(T, idx) catch return null;
    return ctx;
}

// attempts to push _seamstress onto the stack
pub fn getSeamstress(l: *Lua) void {
    const t = l.getGlobal("_seamstress") catch |err| blk: {
        logger.err("error getting _seamstress: {s}", .{@errorName(err)});
        break :blk .nil;
    };
    if (t == .table) return;
    // FIXME: since the `Lua` object is a pointer,
    // we can't use @fieldParentPtr to find the VM,
    // so our only sensible option is to panic this way
    std.debug.panic("_seamstress corrupted!", .{});
}

// attempts to get the method specified by name onto the stack
pub fn getMethod(l: *Lua, field: [:0]const u8, method: [:0]const u8) void {
    getSeamstress(l);
    const t = l.getField(-1, field);
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .table) std.debug.panic("_seamstress corrupted!", .{});
    l.remove(-2);
    const t2 = l.getField(-1, method);
    if (t2 != .function) std.debug.panic("_seamstress corrupted!", .{});
    l.remove(-2);
}

// attempts to get a reference to the event loop
pub fn getWheel(l: *Lua) *Wheel {
    getSeamstress(l);
    const t = l.getField(-1, "_loop");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .userdata and t != .light_userdata) std.debug.panic("_seamstress corrupted!", .{});
    const self = l.toUserdata(Wheel, -1) catch std.debug.panic("_seamstress corrupted!", .{});
    l.pop(2);
    return self;
}

// attempts to set the specified field of the _seamstress.config table
pub fn setConfig(l: *Lua, field: [:0]const u8, val: anytype) Error!void {
    getSeamstress(l);
    defer l.setTop(0);
    const t = l.getField(-1, "config");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .table) std.debug.panic("_seamstress corrupted!", .{});
    l.pushAny(val) catch return error.LuaError;
    l.setField(-2, field);
}

// attempts to get the specified field of the _seamstress.config table
pub fn getConfig(l: *Lua, field: [:0]const u8, comptime T: type) Error!T {
    getSeamstress(l);
    const t = l.getField(-1, "config");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .table) std.debug.panic("_seamstress corrupted!", .{});
    _ = l.getField(-1, field);
    const ret = l.toAny(T, -1) catch return error.LuaFailed;
    l.setTop(0);
    return ret;
}

// allows us to panic by pushing it through the event queue
pub fn panic(l: *Lua, err: Error) void {
    const wheel = getWheel(l);
    wheel.err = err;
    // attempt to dump the stack trace _now_ so that we don't have to carry it around
    blk: {
        const seamstress: *Seamstress = @fieldParentPtr("loop", wheel);
        var info = std.debug.DebugInfo.init(seamstress.allocator) catch break :blk;
        const config = std.io.tty.detectConfig(std.io.getStdErr());
        @call(.always_inline, std.debug.writeCurrentStackTrace, .{ seamstress.vm.stderr.writer(), &info, config, null }) catch break :blk;
    }
    wheel.timer.run(&wheel.loop, &wheel.panic_ev, 1, Wheel, wheel, panicCallback);
}

// posts a quit event
pub fn quit(l: *Lua) void {
    const wheel = getWheel(l);
    wheel.timer.run(&wheel.loop, &wheel.quit_ev, 1, Wheel, wheel, quitCallback);
}

fn quitCallback(wheel: ?*Wheel, _: *xev.Loop, _: *xev.Completion, err: xev.Timer.RunError!void) xev.CallbackAction {
    const self = wheel.?;
    _ = err catch unreachable;
    const seamstress: *Seamstress = @fieldParentPtr("loop", self);
    seamstress.deinit();
    self.quit = true;
    return .disarm;
}

fn panicCallback(wheel: ?*Wheel, _: *xev.Loop, _: *xev.Completion, err: xev.Timer.RunError!void) xev.CallbackAction {
    const self = wheel.?;
    _ = err catch unreachable;
    const seamstress: *Seamstress = @fieldParentPtr("loop", self);
    seamstress.panic(self.err.?);
    self.quit = true;
    return .disarm;
}

// a wrapper around lua_pcall
pub fn doCall(l: *Lua, nargs: i32, nres: i32) void {
    const base = l.getTop() - nargs;
    l.pushFunction(ziglua.wrap(messageHandler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        luaPrint(l);
        return;
    };
    l.remove(base);
}

// adds a stack trace to an error message (and turns it into a string if it is not already)
pub fn messageHandler(l: *Lua) i32 {
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const msg = l.toString(1) catch return 1;
            l.pop(1);
            l.traceback(l, msg, 1);
        },
        // TODO: could we use checkString instead?
        else => {
            const msg = std.fmt.allocPrintZ(l.allocator(), "(error object is an {s} value)", .{l.typeName(t)}) catch return 1;
            defer l.allocator().free(msg);
            l.pop(1);
            l.traceback(l, msg, 1);
        },
    }
    return 1;
}

// calls our monkey-patched print function directly
pub fn luaPrint(l: *Lua) void {
    const n = l.getTop();
    getSeamstress(l);
    // gets the _print field of _seamstress
    _ = l.getField(-1, "_print");
    // removes _seamstress from the stack
    l.remove(-2);
    // moves _print so that we can call it
    l.insert(1);
    // TODO: should we pcall instead?
    l.call(n, 0);
}

const logger = std.log.scoped(.spindle);
const std = @import("std");
const ziglua = @import("ziglua");
const xev = @import("xev");
const Lua = ziglua.Lua;
const Spindle = @import("spindle.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Wheel = @import("wheel.zig");
