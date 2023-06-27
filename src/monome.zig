const std = @import("std");
const osc = @import("serialosc.zig");
const c = osc.c;
const events = @import("events.zig");

var allocator: std.mem.Allocator = undefined;
var devices: []Monome = undefined;
const logger = std.log.scoped(.monome);

pub const Monome_t = enum { Grid, Arc };
pub const Monome = struct {
    id: u8 = 0,
    connected: bool = false,
    name: ?[]const u8 = null,
    to_port: ?[]const u8 = null,
    m_type: Monome_t = undefined,
    rows: u8 = undefined,
    cols: u8 = undefined,
    quads: u8 = undefined,
    data: [4][64]u8 = undefined,
    dirty: [4]bool = undefined,
    thread: c.lo_server_thread = undefined,
    from_port: u16 = undefined,
    addr: c.lo_address = undefined,
    fn set_port(self: *Monome) void {
        var message = c.lo_message_new();
        _ = c.lo_message_add_int32(message, self.from_port);
        _ = c.lo_send_message(self.addr, "/sys/port", message);
        c.lo_message_free(message);
        message = c.lo_message_new();
        _ = c.lo_message_add_string(message, "/monome");
        _ = c.lo_send_message(self.addr, "/sys/prefix", message);
        c.lo_message_free(message);
    }
    fn get_size(self: *Monome) void {
        var message = c.lo_message_new();
        _ = c.lo_message_add_string(message, "localhost");
        _ = c.lo_message_add_int32(message, self.from_port);
        _ = c.lo_send_message(self.addr, "/sys/info", message);
        c.lo_message_free(message);
    }
    pub fn grid_set_led(self: *Monome, x: u8, y: u8, val: u8) void {
        const idx = quad_index(x, y);
        self.data[idx][quad_offset(x, y)] = val;
        self.dirty[idx] = true;
    }
    pub fn grid_all_led(self: *Monome, val: u8) void {
        var idx: u8 = 0;
        while (idx < self.quads) : (idx += 1) {
            var i: u8 = 0;
            while (i < 64) : (i += 1) {
                self.data[idx][i] = val;
            }
            self.dirty[idx] = true;
        }
    }
    pub fn set_rotation(self: *Monome, rotation: u16) void {
        var message = c.lo_message_new();
        _ = c.lo_message_add_int32(message, rotation);
        _ = c.lo_send_message(self.addr, "/sys/rotation", message);
        c.lo_message_free(message);
    }
    pub fn tilt_set(self: *Monome, sensor: u8, enabled: u8) void {
        var message = c.lo_message_new();
        _ = c.lo_message_add_int32(message, sensor);
        _ = c.lo_message_add_int32(message, enabled);
        _ = c.lo_send_message(self.addr, "/monome/tilt/set", message);
        c.lo_message_free(message);
    }
    pub fn arc_set_led(self: *Monome, ring: u8, led: u8, val: u8) void {
        self.data[ring][led] = val;
        self.dirty[ring] = true;
    }
    pub fn arc_all_led(self: *Monome, val: u8) void {
        var idx: u8 = 0;
        while (idx < 4) : (idx += 1) {
            for (self.data[idx]) |*datum| {
                datum = val;
            }
            self.dirty[idx] = true;
        }
    }
    pub fn intensity(self: *Monome, level: u8) void {
        var message = c.lo_message_new();
        _ = c.lo_message_add_int32(message, level);
        _ = c.lo_send_message(self.addr, "/monome/grid/led/intensity", message);
        c.lo_message_free(message);
    }
    pub fn refresh(self: *Monome) void {
        const xoff = [4]u8{ 0, 8, 0, 8 };
        const yoff = [4]u8{ 0, 0, 8, 8 };
        var idx: usize = 0;
        while (idx < self.quads) : (idx += 1) {
            if (!self.dirty[idx]) continue;
            var message = c.lo_message_new();
            switch (self.m_type) {
                .Grid => {
                    _ = c.lo_message_add_int32(message, xoff[idx]);
                    _ = c.lo_message_add_int32(message, yoff[idx]);
                },
                .Arc => _ = c.lo_message_add_int32(message, @intCast(idx)),
            }
            var j: usize = 0;
            while (j < 64) : (j += 1) _ = c.lo_message_add_int32(message, self.data[idx][j]);
            switch (self.m_type) {
                .Grid => _ = c.lo_send_message(self.addr, "/monome/grid/led/level/map", message),
                .Arc => _ = c.lo_send_message(self.addr, "/monome/ring/map", message),
            }
            c.lo_message_free(message);
            self.dirty[idx] = false;
        }
    }
};

pub fn init(alloc_pointer: std.mem.Allocator, port: u16) !void {
    allocator = alloc_pointer;
    devices = try allocator.alloc(Monome, 8);
    for (devices, 0..) |*device, i| {
        device.* = .{};
        device.id = @intCast(i);
        device.from_port = device.id + 1 + port;
        const from_port_str = try std.fmt.allocPrintZ(allocator, "{d}", .{device.from_port});
        defer allocator.free(from_port_str);
        device.thread = c.lo_server_thread_new(from_port_str, osc.lo_error_handler) orelse return error.Fail;
        _ = c.lo_server_thread_add_method(device.thread, "/sys/size", "ii", handle_size, &device.id);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/grid/key", "iii", handle_grid_key, &device.id);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/enc/key", "ii", handle_arc_key, &device.id);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/enc/delta", "ii", handle_delta, &device.id);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/tilt", "iiii", handle_tilt, &device.id);
        _ = c.lo_server_thread_start(device.thread);
    }
}

pub fn deinit() void {
    for (devices) |device| {
        if (device.to_port) |port| allocator.free(port);
        if (device.name) |n| allocator.free(n);
        c.lo_server_thread_free(device.thread);
    }
    allocator.free(devices);
}

pub fn add(name: []const u8, dev_type: []const u8, port: i32) void {
    var free: ?*Monome = null;
    for (devices) |*device| {
        if (free == null and device.connected == false and device.name == null) free = device;
        const n = device.name orelse continue;
        if (std.mem.eql(u8, n, name)) {
            device.connected = true;
            const event = .{
                .Monome_Add = .{
                    .dev = device,
                },
            };
            events.post(event);
            device.set_port();
            return;
        }
    }
    if (free) |device| {
        var name_copy = allocator.alloc(u8, name.len) catch unreachable;
        std.mem.copyForwards(u8, name_copy, name);
        device.name = name_copy;
        const port_str = std.fmt.allocPrint(allocator, "{d}\x00", .{port}) catch unreachable;
        device.to_port = port_str;
        const addr = c.lo_address_new("localhost", port_str.ptr);
        device.addr = addr;
        if (std.mem.eql(u8, dev_type[0..10], "monome arc")) {
            device.m_type = .Arc;
            device.quads = 4;
            device.connected = true;
            const event = .{
                .Monome_Add = .{ .dev = device },
            };
            events.post(event);
            device.set_port();
        } else {
            device.m_type = .Grid;
            device.set_port();
            device.get_size();
        }
    } else {
        logger.err("too many devices! not adding {s}\n", .{name});
    }
}

pub fn remove(name: []const u8) void {
    for (devices) |*device| {
        const n = device.name orelse continue;
        if (std.mem.eql(u8, n, name)) {
            device.connected = false;
            const event = .{
                .Monome_Remove = .{
                    .id = device.id,
                },
            };
            events.post(event);
            return;
        }
    }
    logger.err("trying to remove device {s} which was not added!\n", .{name});
}

pub fn handle_add(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = user_data;
    _ = msg;
    _ = argc;
    _ = types;
    const id = unwrap_string(&argv[0].*.s);
    const dev_t = unwrap_string(&argv[1].*.s);
    const port = argv[2].*.i;
    add(id, dev_t, port);
    const unwound_path = unwrap_string(path);
    if (std.mem.eql(u8, "/serialosc/add", unwound_path)) osc.send_notify();
    return 0;
}

pub fn handle_remove(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = user_data;
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const id = unwrap_string(&argv[0].*.s);
    remove(id);
    return 0;
}

inline fn unwrap_string(str: [*c]const u8) []const u8 {
    var slice: [*]const u8 = @ptrCast(str);
    var len: usize = 0;
    while (slice[len] != 0) : (len += 1) {}
    return slice[0..len];
}

inline fn quad_index(x: u8, y: u8) u8 {
    switch (y) {
        0...7 => {
            switch (x) {
                0...7 => return 0,
                else => return 1,
            }
        },
        else => {
            switch (x) {
                0...7 => return 2,
                else => return 3,
            }
        },
    }
}

inline fn quad_offset(x: u8, y: u8) u8 {
    return ((y & 7) * 8) + (x & 7);
}

fn handle_size(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const i: *u8 = @ptrCast(user_data);
    devices[i.*].cols = @intCast(argv[0].*.i);
    devices[i.*].rows = @intCast(argv[1].*.i);
    devices[i.*].quads = (devices[i.*].cols * devices[i.*].rows) / 64;
    if (!devices[i.*].connected) {
        devices[i.*].connected = true;
        const event = .{
            .Monome_Add = .{ .dev = &devices[i.*] },
        };
        events.post(event);
    }
    return 0;
}

fn handle_grid_key(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const i: *u8 = @ptrCast(user_data);
    const event = .{
        .Grid_Key = .{
            .id = i.*,
            .x = argv[0].*.i,
            .y = argv[1].*.i,
            .state = argv[2].*.i,
        },
    };
    events.post(event);
    return 0;
}

fn handle_arc_key(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const i: *u8 = @ptrCast(user_data);
    const event = .{
        .Arc_Key = .{
            .id = i.*,
            .ring = argv[0].*.i,
            .state = argv[1].*.i,
        },
    };
    events.post(event);
    return 0;
}

fn handle_delta(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const i: *u8 = @ptrCast(user_data);
    const event = .{
        .Arc_Encoder = .{
            .id = i.*,
            .ring = argv[0].*.i,
            .delta = argv[1].*.i,
        },
    };
    events.post(event);
    return 0;
}

fn handle_tilt(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: c.lo_message,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const i: *u8 = @ptrCast(user_data);
    const event = .{
        .Grid_Tilt = .{
            .id = i.*,
            .sensor = argv[0].*.i,
            .x = argv[1].*.i,
            .y = argv[2].*.i,
            .z = argv[3].*.i,
        },
    };
    events.post(event);
    return 0;
}
