const std = @import("std");
const osc = @import("serialosc.zig");
const c = osc.c;
const events = @import("events.zig");

var allocator: std.mem.Allocator = undefined;
var monomes: [8]Monome = undefined;
var devices: []Monome = &monomes;
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
        const message = c.lo_message_new();
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
        inline for (0..4) |idx| {
            @memset(&self.data[idx], val);
            self.dirty[idx] = true;
        }
    }
    pub fn set_rotation(self: *Monome, rotation: u16) void {
        const message = c.lo_message_new();
        _ = c.lo_message_add_int32(message, rotation);
        _ = c.lo_send_message(self.addr, "/sys/rotation", message);
        c.lo_message_free(message);
    }
    pub fn tilt_set(self: *Monome, sensor: u8, enabled: u8) void {
        const message = c.lo_message_new();
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
        inline for (0..4) |idx| {
            @memset(&self.data[idx], val);
            self.dirty[idx] = true;
        }
    }
    pub fn intensity(self: *Monome, level: u8) void {
        const message = c.lo_message_new();
        _ = c.lo_message_add_int32(message, level);
        _ = c.lo_send_message(self.addr, "/monome/grid/led/intensity", message);
        c.lo_message_free(message);
    }
    pub fn refresh(self: *Monome) void {
        const xoff = [4]u8{ 0, 8, 0, 8 };
        const yoff = [4]u8{ 0, 0, 8, 8 };
        for (0..4) |idx| {
            if (!self.dirty[idx]) continue;
            const message = c.lo_message_new();
            switch (self.m_type) {
                .Grid => {
                    _ = c.lo_message_add_int32(message, xoff[idx]);
                    _ = c.lo_message_add_int32(message, yoff[idx]);
                },
                .Arc => _ = c.lo_message_add_int32(message, @intCast(idx)),
            }
            inline for (0..64) |j| _ = c.lo_message_add_int32(message, self.data[idx][j]);
            switch (self.m_type) {
                .Grid => _ = c.lo_send_message(self.addr, "/monome/grid/led/level/map", message),
                .Arc => _ = c.lo_send_message(self.addr, "/monome/ring/map", message),
            }
            c.lo_message_free(message);
            self.dirty[idx] = false;
        }
    }
};

pub fn init(alloc: std.mem.Allocator, port: u16) !void {
    allocator = alloc;
    @memset(devices, .{});
    for (devices, 0..) |*device, i| {
        device.id = @intCast(i);
        device.from_port = device.id + 1 + port;
        const from_port_str = try std.fmt.allocPrintZ(allocator, "{d}", .{device.from_port});
        defer allocator.free(from_port_str);
        device.thread = c.lo_server_thread_new(from_port_str, osc.lo_error_handler) orelse return error.Fail;
        _ = c.lo_server_thread_add_method(device.thread, "/sys/size", "ii", handle_size, device);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/grid/key", "iii", handle_grid_key, device);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/enc/key", "ii", handle_arc_key, device);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/enc/delta", "ii", handle_delta, device);
        _ = c.lo_server_thread_add_method(device.thread, "/monome/tilt", "iiii", handle_tilt, device);
        _ = c.lo_server_thread_start(device.thread);
    }
}

pub fn deinit() void {
    for (devices) |device| {
        if (device.to_port) |port| allocator.free(port);
        if (device.name) |n| allocator.free(n);
        c.lo_server_thread_free(device.thread);
    }
}

pub fn add(name: []const u8, dev_type: []const u8, port: i32) void {
    var free: ?*Monome = null;
    for (devices) |*device| {
        if (free == null and device.connected == false and device.name == null) free = device;
        const n = device.name orelse continue;
        if (std.mem.eql(u8, n, name)) {
            if (device.connected == true) return;
            device.connected = true;
            events.post(.{ .Monome_Add = .{ .dev = device } });
            device.set_port();
            return;
        }
    }
    if (free) |device| {
        const name_copy = allocator.dupeZ(u8, name) catch @panic("OOM!");
        device.name = name_copy;
        const port_str = std.fmt.allocPrintZ(allocator, "{d}", .{port}) catch unreachable;
        device.to_port = port_str;
        const addr = c.lo_address_new("localhost", port_str.ptr);
        device.addr = addr;
        if (std.mem.eql(u8, dev_type[0..10], "monome arc")) {
            device.m_type = .Arc;
            device.quads = 4;
            device.connected = true;
            events.post(.{ .Monome_Add = .{ .dev = device } });
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
            events.post(.{ .Monome_Remove = .{ .id = device.id } });
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
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = user_data;
    _ = msg;
    _ = argc;
    _ = types;
    const id = std.mem.span(@as([*:0]const u8, @ptrCast(&argv[0].*.s)));
    const dev_t = std.mem.span(@as([*:0]const u8, @ptrCast(&argv[1].*.s)));
    const port = argv[2].*.i;
    add(id, dev_t, port);
    const unwound_path = std.mem.span(path);
    if (std.mem.eql(u8, "/serialosc/add", unwound_path[0..14])) osc.send_notify();
    return 0;
}

pub fn handle_remove(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = user_data;
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const id = std.mem.span(@as([*:0]const u8, @ptrCast(&argv[0].*.s)));
    remove(id);
    osc.send_notify();
    return 0;
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
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    var device: *Monome = @ptrCast(@alignCast(user_data orelse return 1));
    device.cols = @intCast(argv[0].*.i);
    device.rows = @intCast(argv[1].*.i);
    device.quads = @intCast(@divExact(argv[0].*.i * argv[1].*.i, 64));
    if (!device.connected) {
        device.connected = true;
        events.post(.{ .Monome_Add = .{ .dev = device } });
    }
    return 0;
}

fn handle_grid_key(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const device: *Monome = @ptrCast(@alignCast(user_data orelse return 1));
    events.post(.{ .Grid_Key = .{ .id = device.id, .x = argv[0].*.i, .y = argv[1].*.i, .state = argv[2].*.i } });
    return 0;
}

fn handle_arc_key(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const device: *Monome = @ptrCast(@alignCast(user_data orelse return 1));
    events.post(.{ .Arc_Key = .{ .id = device.id, .ring = argv[0].*.i, .state = argv[1].*.i } });
    return 0;
}

fn handle_delta(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const device: *Monome = @ptrCast(@alignCast(user_data orelse return 1));
    events.post(.{ .Arc_Encoder = .{ .id = device.id, .ring = argv[0].*.i, .delta = argv[1].*.i } });
    return 0;
}

fn handle_tilt(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = msg;
    _ = argc;
    _ = types;
    _ = path;
    const device: *Monome = @ptrCast(@alignCast(user_data orelse return 1));
    events.post(.{ .Grid_Tilt = .{
        .id = device.id,
        .sensor = argv[0].*.i,
        .x = argv[1].*.i,
        .y = argv[2].*.i,
        .z = argv[3].*.i,
    } });
    return 0;
}
