/// struct for storing and interacting with monome arc or grid devices
const Monome = @This();

devices: std.BoundedArray(Device, 16) = .{},
serialosc_address: *lo.Address,
local_address: *lo.Message,

const Device = struct {
    connected: bool = false,
    name_buf: [256]u8 = undefined,
    addr: *lo.Address,
    m_type: enum { grid, arc },
    rows: u8,
    cols: u8,
    vm: *Spindle,
    node: Events.Node = .{
        .handler = Events.handlerFromClosure(Device, addOrRemove, "node"),
    },

    fn addOrRemove(device: *Device) void {
        _ = device; // autofix

    }
};

fn sendNotify(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(self.serialosc_address, "/serialosc/notify", self.local_address);
}

fn handleAdd(path: [:0]const u8, typespec: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
    const name = msg.getArg([:0]const u8, 0) catch return true;
    _ = name; // autofix
    const dev_type = msg.getArg([:0]const u8, 1) catch return true;
    _ = dev_type; // autofix
    const port = msg.getArg(i32, 2) catch return true;
    _ = port; // autofix
    for (self.devices.slice()) |dev| {
        _ = dev; // autofix
    }
    _ = typespec; // autofix
    if (std.mem.eql(u8, "/serialosc/add", path)) sendNotify(self);
    return false;
}

const Osc = @import("osc.zig").Osc;
const lo = @import("ziglo");
const std = @import("std");
const Events = @import("events.zig");
const Spindle = @import("spindle.zig");
