/// type-erased module struct
const Module = @This();

self: ?*anyopaque = null,
vtable: *const Vtable,

const Vtable = struct {
    init_fn: *const fn (*Module, *Spindle, *Wheel, std.mem.Allocator) Error!void,
    deinit_fn: *const fn (*const Module, *Lua, std.mem.Allocator, Cleanup) void,
    launch_fn: *const fn (*const Module, *Lua, *Wheel) Error!void,
};

pub fn init(m: *Module, vm: *Spindle, wheel: *Wheel, allocator: std.mem.Allocator) Error!void {
    try m.vtable.init_fn(m, vm, wheel, allocator);
}

pub fn deinit(m: *const Module, l: *Lua, allocator: std.mem.Allocator, cleanup: Cleanup) void {
    m.vtable.deinit_fn(m, l, allocator, cleanup);
}

pub fn launch(m: *const Module, l: *Lua, wheel: *Wheel) Error!void {
    try m.vtable.launch_fn(m, l, wheel);
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Spindle = @import("spindle.zig");
const Wheel = @import("wheel.zig");
const std = @import("std");
const Lua = @import("ziglua").Lua;
