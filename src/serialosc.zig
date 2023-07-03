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
var allocator: std.mem.Allocator = undefined;
const logger = std.log.scoped(.serialosc);

pub fn init(local_port: [:0]const u8, alloc: std.mem.Allocator) !void {
    allocator = alloc;
    localport = try std.fmt.parseUnsigned(u16, local_port, 10);
    serialosc_addr = c.lo_address_new("localhost", "12002") orelse return error.Fail;
    server_thread = c.lo_server_thread_new(local_port, lo_error_handler) orelse return error.Fail;
    _ = c.lo_server_thread_add_method(server_thread, "/serialosc/device", "ssi", monome.handle_add, null);
    _ = c.lo_server_thread_add_method(server_thread, "/serialosc/add", "ssi", monome.handle_add, null);
    _ = c.lo_server_thread_add_method(server_thread, "/serialosc/remove", "ssi", monome.handle_remove, null);
    _ = c.lo_server_thread_add_method(server_thread, null, null, osc_receive, null);
    // _ = c.DNSServiceRegister(&dnssd_ref, 0, 0, "seamstress", "_osc._udp", null, null, state.port, 0, null, null, null);
    _ = c.lo_server_thread_start(server_thread);
    try monome.init(alloc, localport);
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

pub const Lo_Arg_t = enum {
    Lo_Int32,
    Lo_Float,
    Lo_String,
    Lo_Blob,
    Lo_Int64,
    Lo_Double,
    Lo_Symbol,
    Lo_Midi,
    Lo_True,
    Lo_False,
    Lo_Nil,
    Lo_Infinitum,
    // lo_msg arg types
};

pub const Lo_Blob_t = struct { dataptr: ?*anyopaque, datasize: i32 };

pub const Lo_Arg = union(Lo_Arg_t) {
    Lo_Int32: i32,
    Lo_Float: f32,
    Lo_String: [:0]const u8,
    Lo_Blob: Lo_Blob_t,
    Lo_Int64: i64,
    Lo_Double: f64,
    Lo_Symbol: [:0]const u8,
    Lo_Midi: [4]u8,
    Lo_True: bool,
    Lo_False: bool,
    Lo_Nil: bool,
    Lo_Infinitum: bool,
    // Lo_Arg union
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

    var i: usize = 0;
    while (i < argc) : (i += 1) {
        switch (types[i]) {
            c.LO_INT32 => {
                message[i] = Lo_Arg{ .Lo_Int32 = argv[i].*.i };
            },
            c.LO_FLOAT => {
                message[i] = Lo_Arg{ .Lo_Float = argv[i].*.f };
            },
            c.LO_STRING => {
                var slice = @as([*]u8, @ptrCast(&argv[i].*.s));
                var len: usize = 0;
                while (slice[len] != 0) : (len += 1) {}
                message[i] = Lo_Arg{ .Lo_String = slice[0..len :0] };
            },
            c.LO_BLOB => {
                const arg = argv[i];
                message[i] = Lo_Arg{ .Lo_Blob = Lo_Blob_t{
                    .dataptr = c.lo_blob_dataptr(@as(c.lo_blob, @ptrCast(arg))),
                    .datasize = @as(i32, @intCast(c.lo_blob_datasize(@as(c.lo_blob, @ptrCast(arg))))),
                } };
            },
            c.LO_INT64 => {
                message[i] = Lo_Arg{ .Lo_Int64 = argv[i].*.h };
            },
            c.LO_DOUBLE => {
                message[i] = Lo_Arg{ .Lo_Double = argv[i].*.d };
            },
            c.LO_SYMBOL => {
                var slice = @as([*]u8, @ptrCast(&argv[i].*.S));
                var len: usize = 0;
                while (slice[len] != 0) : (len += 1) {}
                message[i] = Lo_Arg{ .Lo_Symbol = slice[0..len :0] };
            },
            c.LO_MIDI => {
                message[i] = Lo_Arg{ .Lo_Midi = argv[i].*.m };
            },
            c.LO_TRUE => {
                message[i] = Lo_Arg{ .Lo_True = true };
            },
            c.LO_FALSE => {
                message[i] = Lo_Arg{ .Lo_False = false };
            },
            c.LO_NIL => {
                message[i] = Lo_Arg{ .Lo_Nil = false };
            },
            c.LO_INFINITUM => {
                message[i] = Lo_Arg{ .Lo_Infinitum = true };
            },
            else => {
                logger.err("unknown osc typetag: {c}", .{types[i]});
                message[i] = Lo_Arg{ .Lo_Nil = false };
            },
        }
    }
    const path_slice = std.mem.span(path);
    var path_copy = allocator.allocSentinel(u8, path_slice.len, 0) catch @panic("OOM!");
    std.mem.copyForwards(u8, path_copy, path_slice);
    const source = c.lo_message_get_source(msg);
    const host = std.mem.span(c.lo_address_get_hostname(source));
    var host_copy = allocator.allocSentinel(u8, host.len, 0) catch @panic("OOM!");
    std.mem.copyForwards(u8, host_copy, host);
    const port = std.mem.span(c.lo_address_get_port(source));
    var port_copy = allocator.allocSentinel(u8, port.len, 0) catch @panic("OOM!");
    std.mem.copyForwards(u8, port_copy, port);

    const event = .{ .OSC = .{
        .msg = message,
        .from_host = host_copy,
        .from_port = port_copy,
        .path = path_copy,
    } };
    events.post(event);
    return 1;
}

pub fn send(
    to_host: [*:0]const u8,
    to_port: [*:0]const u8,
    path: [*:0]const u8,
    msg: []Lo_Arg,
) void {
    const address: c.lo_address = c.lo_address_new(to_host, to_port);
    if (address == null) {
        logger.err("failed to create lo_address", .{});
        return;
    }
    var message: c.lo_message = c.lo_message_new();
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        switch (msg[i]) {
            Lo_Arg_t.Lo_Int32 => |a| _ = c.lo_message_add_int32(message, a),
            Lo_Arg_t.Lo_Float => |a| _ = c.lo_message_add_float(message, a),
            Lo_Arg_t.Lo_String => |a| _ = c.lo_message_add_string(message, a),
            Lo_Arg_t.Lo_Blob => |a| {
                const blob = c.lo_blob_new(a.datasize, a.dataptr);
                _ = c.lo_message_add_blob(message, blob);
            },
            Lo_Arg_t.Lo_Int64 => |a| _ = c.lo_message_add_int64(message, a),
            Lo_Arg_t.Lo_Double => |a| _ = c.lo_message_add_double(message, a),
            Lo_Arg_t.Lo_Symbol => |a| _ = c.lo_message_add_symbol(message, a),
            Lo_Arg_t.Lo_Midi => |a| _ = c.lo_message_add_midi(message, @as([*c]u8, @ptrCast(@constCast(a[0..4])))),
            Lo_Arg_t.Lo_True => _ = c.lo_message_add_true(message),
            Lo_Arg_t.Lo_False => _ = c.lo_message_add_false(message),
            Lo_Arg_t.Lo_Nil => _ = c.lo_message_add_nil(message),
            Lo_Arg_t.Lo_Infinitum => _ = c.lo_message_add_infinitum(message),
        }
    }
    _ = c.lo_send_message(address, path, message);
    c.lo_address_free(address);
    c.lo_message_free(message);
}
