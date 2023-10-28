const std = @import("std");
const events = @import("events.zig");
const monome = @import("monome.zig");
pub const c = @cImport({
    @cInclude("lo/lo.h");
});

var server_thread: c.lo_server_thread = undefined;
// TODO: is this needed?
// dnssd_ref: c.DNSServiceRef = undefined,
var localport: u16 = undefined;
var localhost = "localhost";
pub var serialosc_addr: c.lo_address = undefined;
var sfba = std.heap.stackFallback(32 * 1024, std.heap.raw_c_allocator);
var allocator: std.mem.Allocator = undefined;
const logger = std.log.scoped(.serialosc);

pub fn init(local_port: [:0]const u8) !void {
    allocator = sfba.get();
    localport = try std.fmt.parseUnsigned(u16, local_port, 10);
    serialosc_addr = c.lo_address_new("localhost", "12002") orelse return error.Fail;
    server_thread = c.lo_server_thread_new(local_port, lo_error_handler) orelse return error.Fail;
    _ = c.lo_server_thread_add_method(server_thread, "/serialosc/device", "ssi", monome.handle_add, null);
    _ = c.lo_server_thread_add_method(server_thread, "/serialosc/add", "ssi", monome.handle_add, null);
    _ = c.lo_server_thread_add_method(server_thread, "/serialosc/remove", "ssi", monome.handle_remove, null);
    _ = c.lo_server_thread_add_method(server_thread, null, null, osc_receive, null);
    // _ = c.DNSServiceRegister(&dnssd_ref, 0, 0, "seamstress", "_osc._udp", null, null, state.port, 0, null, null, null);
    _ = c.lo_server_thread_start(server_thread);
    try monome.init(allocator, localport);
    var message = c.lo_message_new();
    _ = c.lo_message_add_string(message, localhost);
    _ = c.lo_message_add_int32(message, localport);
    _ = c.lo_send_message(serialosc_addr, "/serialosc/list", message);
    c.lo_message_free(message);
    send_notify();
}

pub fn deinit() void {
    // _ = c.DNSServiceRefDeallocate(dnssd_ref);
    monome.deinit();
    c.lo_server_thread_free(server_thread);
    c.lo_address_free(serialosc_addr);
}

pub fn lo_error_handler(
    num: c_int,
    m: [*c]const u8,
    path: [*c]const u8,
) callconv(.C) void {
    if (path == null) {
        logger.err("liblo error {d}: {s}", .{ num, std.mem.span(m) });
    } else {
        logger.err("liblo error {d} in path {s}: {s}", .{ num, std.mem.span(path), std.mem.span(m) });
    }
}

inline fn unwrap_string(str: *u8) [:0]u8 {
    var slice: [*]u8 = @ptrCast(str);
    var len: usize = 0;
    while (slice[len] != 0) : (len += 1) {}
    return slice[0..len :0];
}

pub fn send_notify() void {
    var message = c.lo_message_new();
    _ = c.lo_message_add_string(message, localhost);
    _ = c.lo_message_add_int32(message, localport);
    _ = c.lo_send_message(serialosc_addr, "/serialosc/notify", message);
    c.lo_message_free(message);
}

pub const Lo_Arg = union(enum) {
    Lo_Int32: i32,
    Lo_Float: f32,
    Lo_String: [:0]const u8,
    Lo_Blob: []const u8,
    Lo_Int64: i64,
    Lo_Double: f64,
    Lo_Symbol: [:0]const u8,
    Lo_Midi: [4]u8,
    Lo_True: bool,
    Lo_False: bool,
    Lo_Nil: bool,
    Lo_Infinitum: bool,
};

fn osc_receive(
    path: [*c]const u8,
    types: [*c]const u8,
    argv: [*c][*c]c.lo_arg,
    argc: c_int,
    msg: c.lo_message,
    user_data: ?*anyopaque,
) callconv(.C) c_int {
    _ = user_data;
    const arg_size = @as(usize, @intCast(argc));
    var message: []Lo_Arg = allocator.alloc(Lo_Arg, arg_size) catch @panic("OOM!");

    for (0..@intCast(argc)) |i| {
        switch (types[i]) {
            c.LO_INT32 => {
                message[i] = .{ .Lo_Int32 = argv[i].*.i };
            },
            c.LO_FLOAT => {
                message[i] = .{ .Lo_Float = argv[i].*.f };
            },
            c.LO_STRING => {
                const slice: [*:0]const u8 = @ptrCast(&argv[i].*.s);
                const slice_copy = allocator.dupeZ(u8, std.mem.sliceTo(slice, 0)) catch @panic("OOM!");
                message[i] = .{ .Lo_String = slice_copy };
            },
            c.LO_BLOB => {
                const arg: c.lo_blob = @ptrCast(argv[i]);
                const len: usize = @intCast(c.lo_blob_datasize(arg));
                const ptr: [*]const u8 = @ptrCast(c.lo_blob_dataptr(arg));
                var blobby = allocator.alloc(u8, len) catch @panic("OOM!");
                @memcpy(blobby, ptr);
                message[i] = .{
                    .Lo_Blob = blobby,
                };
            },
            c.LO_INT64 => {
                message[i] = .{ .Lo_Int64 = argv[i].*.h };
            },
            c.LO_DOUBLE => {
                message[i] = .{ .Lo_Double = argv[i].*.d };
            },
            c.LO_SYMBOL => {
                const slice: [*:0]const u8 = @ptrCast(&argv[i].*.S);
                const slice_copy = allocator.dupeZ(u8, std.mem.sliceTo(slice, 0)) catch @panic("OOM!");
                message[i] = .{ .Lo_Symbol = slice_copy };
            },
            c.LO_MIDI => {
                message[i] = .{ .Lo_Midi = argv[i].*.m };
            },
            c.LO_TRUE => {
                message[i] = .{ .Lo_True = true };
            },
            c.LO_FALSE => {
                message[i] = .{ .Lo_False = false };
            },
            c.LO_NIL => {
                message[i] = .{ .Lo_Nil = false };
            },
            c.LO_INFINITUM => {
                message[i] = .{ .Lo_Infinitum = true };
            },
            else => {
                logger.err("unknown osc typetag: {c}", .{types[i]});
                message[i] = .{ .Lo_Nil = false };
            },
        }
    }
    const path_copy = allocator.dupeZ(u8, std.mem.span(path)) catch @panic("OOM!");
    const source = c.lo_message_get_source(msg);
    const host = std.mem.span(c.lo_address_get_hostname(source));
    var host_copy = allocator.dupeZ(u8, host) catch @panic("OOM!");
    const port = std.mem.span(c.lo_address_get_port(source));
    var port_copy = allocator.dupeZ(u8, port) catch @panic("OOM!");

    const event = .{ .OSC = .{
        .msg = message,
        .from_host = host_copy,
        .from_port = port_copy,
        .path = path_copy,
        .allocator = allocator,
    } };
    events.post(event);
    return 1;
}

pub fn send(
    to_host: [:0]const u8,
    to_port: [:0]const u8,
    path: [:0]const u8,
    msg: []Lo_Arg,
) void {
    const address: c.lo_address = c.lo_address_new(to_host.ptr, to_port.ptr);
    if (address == null) {
        logger.err("failed to create lo_address", .{});
        return;
    }
    defer c.lo_address_free(address);
    var message: c.lo_message = c.lo_message_new();
    defer c.lo_message_free(message);
    for (msg) |m| {
        switch (m) {
            .Lo_Int32 => |a| _ = c.lo_message_add_int32(message, a),
            .Lo_Float => |a| _ = c.lo_message_add_float(message, a),
            .Lo_String => |a| _ = c.lo_message_add_string(message, a.ptr),
            .Lo_Blob => |a| {
                const blob = c.lo_blob_new(@intCast(a.len), a.ptr);
                _ = c.lo_message_add_blob(message, blob);
            },
            .Lo_Int64 => |a| _ = c.lo_message_add_int64(message, a),
            .Lo_Double => |a| _ = c.lo_message_add_double(message, a),
            .Lo_Symbol => |a| _ = c.lo_message_add_symbol(message, a.ptr),
            .Lo_Midi => |a| _ = c.lo_message_add_midi(message, @as([*c]u8, @ptrCast(@constCast(a[0..4])))),
            .Lo_True => _ = c.lo_message_add_true(message),
            .Lo_False => _ = c.lo_message_add_false(message),
            .Lo_Nil => _ = c.lo_message_add_nil(message),
            .Lo_Infinitum => _ = c.lo_message_add_infinitum(message),
        }
    }
    _ = c.lo_send_message(address, path.ptr, message);
}
