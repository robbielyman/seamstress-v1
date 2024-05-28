/// my hope is that this mild layer of indirection makes it easier to add new modules
/// new modules should provide a pub function `module` that can be called
/// from wherever modules end up being processed that returns an object conforming to this interface
const Module = @This();

self: ?*anyopaque = null,
vtable: *const Vtable,

pub const Vtable = struct {
    init_fn: *const fn (*Module, *Spindle, std.mem.Allocator) void,
    deinit_fn: *const fn (*const Module, *Lua, std.mem.Allocator, Cleanup) void,
    launch_fn: *const fn (*const Module, *Lua, *Wheel) void,
};

pub fn init(m: *Module, vm: *Spindle, allocator: std.mem.Allocator) void {
    m.vtable.init_fn(m, vm, allocator);
}

pub fn deinit(m: *const Module, l: *Lua, allocator: std.mem.Allocator, cleanup: Cleanup) void {
    m.vtable.deinit_fn(m, l, allocator, cleanup);
}

pub fn launch(m: *const Module, l: *Lua, wheel: *Wheel) void {
    m.vtable.launch_fn(m, l, wheel);
}

const Spindle = @import("spindle.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Wheel = @import("wheel.zig");
const Seamstress = @import("seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const std = @import("std");
