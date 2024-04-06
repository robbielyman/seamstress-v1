/// a collection of convenience functions intended to make module code easier to write

// checks that the function has the specified number of arguments
pub fn checkNumArgs(l: *Lua, n: usize) void {
    if (l.getTop() != n) l.raiseErrorStr("error: requires %d arguments", .{n});
}

// registers a closure as _seamstress.field_name
// we're using closures this time around instead of global state!
// makes me feel fancy
// the closure has one "upvalue" in Lua terms: ptr
pub fn registerSeamstress(vm: *Spindle, field_name: [:0]const u8, comptime f: ziglua.ZigFn, ptr: *anyopaque) void {
    // pushes _seamstress onto the stack
    getSeamstress(vm.lvm);
    // upshes our upvalue
    vm.lvm.pushLightUserdata(ptr);
    // creates the function (consuming the upvalue)
    vm.lvm.pushClosure(ziglua.wrap(f), 1);
    // assigns it to _seamstress.field_name
    vm.lvm.setField(-2, field_name);
    // and removes _seamstress from the stack
    vm.lvm.pop(1);
}

// must be called within a closure registered with `registerSeamstress`.
// gets the one upvalue associated with the closure
// returns null on failure
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

// attempts to get a reference to the Lua VM
// pub so that it can be used in module code
pub fn getVM(l: *Lua) *Spindle {
    getSeamstress(l);
    const t = l.getField(-1, "_context");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .userdata and t != .light_userdata) std.debug.panic("_seamstress corrupted!", .{});
    const self = l.toUserdata(Spindle, -1) catch std.debug.panic("_seamstress corrupted!", .{});
    l.pop(2);
    return self;
}

// attempts to set the specified field of the _seamstress.config table
// pub so that it can be used in module code
pub fn setConfig(vm: *Spindle, field: [:0]const u8, val: anytype) Error!void {
    getSeamstress(vm.lvm);
    defer vm.lvm.setTop(0);
    const t = vm.lvm.getField(-1, "config");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .table) std.debug.panic("_seamstress corrupted!", .{});
    vm.lvm.pushAny(val) catch return error.LuaError;
    vm.lvm.setField(-2, field);
}

// attempts to get the specified field of the _seamstress.config table
// pub so that it can be used in module code
pub fn getConfig(vm: *Spindle, field: [:0]const u8, comptime T: type) Error!T {
    getSeamstress(vm.lvm);
    const t = vm.lvm.getField(-1, "config");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .table) std.debug.panic("_seamstress corrupted!", .{});
    _ = vm.lvm.getField(-1, field);
    const ret = vm.lvm.toAny(T, -1) catch return error.LuaFailed;
    vm.lvm.setTop(0);
    return ret;
}

// allows us to panic on the main thread by pushing it through the event queue
pub fn panic(vm: *Spindle, err: Error) void {
    vm.events.err = err;
    vm.events.submit(&vm.events.panic_node);
}

// posts a quit event
pub fn quit(vm: *Spindle) void {
    vm.events.submit(&vm.events.quit_node);
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

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Spindle = @import("spindle.zig");
const Lua = ziglua.Lua;
const ziglua = @import("ziglua");
const logger = Spindle.logger;
const std = @import("std");
