const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("rtmidi/rtmidi_c.h");
});
const events = @import("events.zig");

var allocator: std.mem.Allocator = undefined;
var thread: std.Thread = undefined;
var quit = false;
var devices: []Device = undefined;
var midi_in_counter: *c.RtMidiWrapper = undefined;
var midi_out_counter: *c.RtMidiWrapper = undefined;
const logger = std.log.scoped(.midi);

const RtMidiPrefix = "seamstress";

pub const Device = struct {
    id: u8,
    name: ?[:0]const u8,
    input: ?Input,
    output: ?Output,

    pub const Input = struct {
        quit: bool,
        ptr: *c.RtMidiWrapper,
        thread: std.Thread,
        buf: [1024]u8 = undefined,

        fn create(self: *Device, i: c_uint) !void {
            if (self.input) |_| return;
            const midi_in = c.rtmidi_in_create(
                c.RTMIDI_API_UNSPECIFIED,
                RtMidiPrefix,
                1024,
            ) orelse return error.Fail;
            const name = self.name orelse return error.Fail;
            c.rtmidi_open_port(midi_in, i, name.ptr);
            c.rtmidi_in_ignore_types(midi_in, false, false, false);
            self.input = .{
                .quit = false,
                .ptr = midi_in,
                .thread = try std.Thread.spawn(.{}, loop, .{self}),
            };
        }
    };

    pub const Output = struct {
        ptr: *c.RtMidiWrapper,

        fn create(self: *Device, i: c_uint) !void {
            if (self.output) |_| return;
            const midi_out = c.rtmidi_out_create(
                c.RTMIDI_API_UNSPECIFIED,
                RtMidiPrefix,
            ) orelse return error.Fail;
            const name = self.name orelse return error.Fail;
            c.rtmidi_open_port(midi_out, i, name.ptr);
            self.output = .{
                .ptr = midi_out,
            };
        }
    };

    fn read(self: *Device) DeviceError!void {
        var in = self.input orelse return error.NotFound;
        var len: usize = 1024;
        while (len > 0) {
            len = 1024;
            const timestamp = c.rtmidi_in_get_message(in.ptr, &in.buf, &len);
            if (!in.ptr.*.ok) {
                const err = std.mem.sliceTo(in.ptr.*.msg, 0);
                logger.err("error in device {s}: {s}", .{ self.name.?, err });
                return error.ReadError;
            }
            if (len == 0) break;
            var line = allocator.dupe(u8, in.buf[0..len]) catch @panic("OOM!");
            events.post(.{ .MIDI = .{
                .message = line,
                .timestamp = timestamp,
                .id = self.id,
            } });
        }
    }

    fn loop(self: *Device) void {
        var loop_quit = false;
        while (!loop_quit) {
            const in = self.input orelse return;
            loop_quit = in.quit;
            self.read() catch {
                self.input.?.quit = true;
                break;
            };
            std.time.sleep(std.time.ns_per_us * 3);
        }
    }

    pub fn write(self: *Device, message: []const u8) DeviceError!void {
        const out = self.output orelse return error.NotFound;
        _ = c.rtmidi_out_send_message(out.ptr, message.ptr, @intCast(message.len));
        if (!out.ptr.*.ok) {
            const err = std.mem.sliceTo(out.ptr.*.msg, 0);
            logger.err("error in device {s}: {s}", .{ self.name.?, err });
            return error.WriteError;
        }
    }
};

pub const DeviceError = error{ NotFound, ReadError, WriteError };
pub const Device_Type = enum { Input, Output };

fn remove(id: usize) void {
    if (devices[id].input) |*in| {
        devices[id].input.?.quit = true;
        in.thread.join();
        c.rtmidi_close_port(in.ptr);
        c.rtmidi_in_free(in.ptr);
        devices[id].input = null;
    }
    if (devices[id].output) |*out| {
        c.rtmidi_close_port(out.ptr);
        c.rtmidi_out_free(out.ptr);
        devices[id].output = null;
    }
    if (devices[id].name) |n| allocator.free(n);
    devices[id].name = null;
    events.post(.{
        .MIDI_Remove = .{ .id = devices[id].id },
    });
}

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    quit = false;
    allocator = alloc_pointer;
    devices = try allocator.alloc(Device, 32);
    inline for (0..32) |idx| {
        devices[@intCast(idx)] = .{
            .id = idx,
            .name = null,
            .input = null,
            .output = null,
        };
    }
    var midi_in = c.rtmidi_in_create(
        c.RTMIDI_API_UNSPECIFIED,
        RtMidiPrefix,
        1024,
    );
    errdefer c.rtmidi_in_free(midi_in);
    if (midi_in.*.ok == false) return error.Fail;
    c.rtmidi_open_virtual_port(midi_in, "seamstress_in");
    errdefer c.rtmidi_close_port(midi_in);
    var midi_out = c.rtmidi_out_create(
        c.RTMIDI_API_UNSPECIFIED,
        RtMidiPrefix,
    );
    errdefer c.rtmidi_out_free(midi_out);
    if (midi_out.*.ok == false) return error.Fail;
    c.rtmidi_open_virtual_port(midi_out, "seamstress_out");
    errdefer c.rtmidi_close_port(midi_out);
    devices[0].name = allocator.dupeZ(u8, "seamstress") catch @panic("OOM!");
    events.post(.{
        .MIDI_Add = .{ .dev = &devices[0] },
    });
    devices[0].input = .{
        .quit = false,
        .ptr = midi_in,
        .thread = try std.Thread.spawn(.{}, Device.loop, .{&devices[0]}),
    };
    devices[0].output = .{
        .ptr = midi_out,
    };

    midi_in_counter = c.rtmidi_in_create_default();
    midi_out_counter = c.rtmidi_out_create_default();
    try add_devices();
    thread = try std.Thread.spawn(.{}, main_loop, .{});
}

fn add_devices() !void {
    const Is_Active = packed struct {
        input: bool,
        output: bool,
    };
    var is_active: [32]Is_Active = .{.{ .input = false, .output = false }} ** 32;
    const in_count = c.rtmidi_get_port_count(midi_in_counter);
    for (0..in_count) |i| {
        var len: c_int = 256;
        _ = c.rtmidi_get_port_name(midi_in_counter, @intCast(i), null, &len);
        var buf = allocator.allocSentinel(u8, @intCast(len), 0) catch @panic("OOM!");
        defer allocator.free(buf);
        _ = c.rtmidi_get_port_name(midi_in_counter, @intCast(i), buf.ptr, &len);
        const spanned = switch (comptime builtin.os.tag) {
            .linux => std.mem.sliceTo(buf.ptr, ':'),
            else => std.mem.sliceTo(buf.ptr, 0),
        };
        // NB: on linux, rtmidi keeps on reannouncing registered devices
        // with 'RtMidiPrefix' added.
        if (find(spanned)) |id| {
            is_active[id].input = true;
            if (devices[id].input) |in| {
                if (in.quit) {
                    in.thread.join();
                    c.rtmidi_close_port(in.ptr);
                    c.rtmidi_in_free(in.ptr);
                    devices[id].input = null;
                    try Device.Input.create(&devices[id], @intCast(i));
                }
            } else {
                try Device.Input.create(&devices[id], @intCast(i));
            }
        } else {
            if (try add(.Input, @intCast(i), spanned)) |id| is_active[id].input = true;
        }
    }
    const out_count = c.rtmidi_get_port_count(midi_out_counter);
    for (0..out_count) |i| {
        var len: c_int = 256;
        _ = c.rtmidi_get_port_name(midi_out_counter, @intCast(i), null, &len);
        var buf = allocator.allocSentinel(u8, @intCast(len), 0) catch @panic("OOM!");
        defer allocator.free(buf);
        _ = c.rtmidi_get_port_name(midi_out_counter, @intCast(i), buf.ptr, &len);
        const spanned = switch (comptime builtin.os.tag) {
            .linux => std.mem.sliceTo(buf.ptr, ':'),
            else => std.mem.sliceTo(buf.ptr, 0),
        };
        if (find(spanned)) |id| {
            is_active[id].output = true;
            if (devices[id].output == null) try Device.Output.create(&devices[id], @intCast(i));
        } else {
            if (try add(.Output, @intCast(i), spanned)) |id| is_active[id].output = true;
        }
    }
    for (is_active, 0..) |active, i| {
        if (!active.input and !active.output) {
            if (devices[i].name) |_| remove(i);
        } else if (!active.input) {
            var in = devices[i].input orelse continue;
            in.quit = true;
            in.thread.join();
            devices[i].input = null;
        } else if (!active.output) {
            const out = devices[i].output orelse continue;
            c.rtmidi_close_port(out.ptr);
            c.rtmidi_out_free(out.ptr);
            devices[i].output = null;
        }
    }
}

fn is_prefixed(name: [:0]const u8) bool {
    if (!std.mem.startsWith(u8, name, RtMidiPrefix ++ ":")) return false;
    if (std.mem.startsWith(u8, name, RtMidiPrefix ++ ":seamstress_")) return false;
    return true;
}

fn main_loop() !void {
    while (!quit) {
        std.time.sleep(std.time.ns_per_s);
        try add_devices();
    }
}

fn find(name: []const u8) ?usize {
    for (0..32) |i| {
        const n = devices[i].name orelse continue;
        if (std.mem.eql(u8, name, n)) return i;
    }
    return null;
}

fn add(dev_type: Device_Type, port_number: c_uint, name: []const u8) !?u8 {
    var free: ?*Device = null;
    for (0..32) |i| {
        const is_free = devices[i].name == null;
        if (is_free) {
            free = &devices[i];
            break;
        }
    }
    var device = free orelse {
        logger.err("too many devices! not adding {s}", .{name});
        return null;
    };
    const id = device.id;
    device.name = allocator.dupeZ(u8, name) catch @panic("OOM!");
    events.post(.{
        .MIDI_Add = .{ .dev = device },
    });
    switch (dev_type) {
        .Input => try Device.Input.create(device, port_number),
        .Output => try Device.Output.create(device, port_number),
    }
    return id;
}

pub fn deinit() void {
    quit = true;
    thread.join();
    for (0..32) |i| {
        remove(i);
    }
    allocator.free(devices);
}
