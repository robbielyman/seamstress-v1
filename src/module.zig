/// my hope is that this mild layer of indirection makes it easier to add new modules
/// new modules should provide a pub function `module` that can be called
/// from wherever modules end up being processed that returns an object conforming to this interface
const Module = @This();

self: ?*anyopaque = null,
vtable: *const Vtable,

pub const Vtable = struct {
    init_fn: *const fn (*Module, *Lua, std.mem.Allocator) anyerror!void,
    deinit_fn: *const fn (*const Module, *Lua, std.mem.Allocator, Cleanup) void,
    launch_fn: *const fn (*const Module, *Lua, *Wheel) anyerror!void,
};

/// sets up the module without starting it
/// should not assume that, for example, the event loop is already running
/// Modules should not depend on each other, nor assume that each other are active
/// for example, because we use serialosc rather than libmonome,
/// monome.zig does not export a Module but instead is set up by osc.zig
/// clock.zig gets MIDI clock from the midi module by exporting a Lua function
/// tui.zig asks cli.zig to shut down via the Lua VM
pub fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) !void {
    try m.vtable.init_fn(m, l, allocator);
}

/// shuts down the module, respecting the Cleanup level
pub fn deinit(m: *const Module, l: *Lua, allocator: std.mem.Allocator, cleanup: Cleanup) void {
    m.vtable.deinit_fn(m, l, allocator, cleanup);
}

/// actually puts the module into operation
pub fn launch(m: *const Module, l: *Lua, wheel: *Wheel) anyerror!void {
    try m.vtable.launch_fn(m, l, wheel);
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Wheel = @import("wheel.zig");
const Seamstress = @import("seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const std = @import("std");

/// the full list of modules available to seamstress
const module_list = [_]struct { []const u8, Module }{
    //.{ "osc", @import("modules/osc.zig").module() },
    //.{ "clock", @import("modules/clock.zig").module() },
    // .{ "metros", @import("modules/metros.zig").module() },
    .{ "cli", @import("modules/cli.zig").module() },
    .{ "tui", @import("modules/tui.zig").module() },
};

pub fn list(allocator: std.mem.Allocator) !std.StaticStringMap(*Module) {
    var tuple = comptime tuple: {
        var tuple: [module_list.len]struct { []const u8, *Module } = undefined;
        for (module_list, 0..) |element, i| {
            tuple[i] = .{ element[0], undefined };
        }
        const ret = tuple;
        break :tuple ret;
    };
    inline for (module_list, 0..) |element, i| {
        const mod = try allocator.create(Module);
        mod.* = element[1];
        tuple[i][1] = mod;
    }
    return std.StaticStringMap(*Module).init(tuple, allocator);
}
