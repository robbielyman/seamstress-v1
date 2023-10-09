const std = @import("std");
const events = @import("events.zig");
const pthread = @import("pthread.zig");
const c = @cImport({
    @cInclude("abl_link.h");
});

pub const Transport = enum { Start, Stop, Reset };
const Delta = union(enum) {
    Sleep: i128,
    Sync: u64,
};

pub const Source = enum(c_longlong) { Internal, MIDI, Link };

const Clock = struct {
    inactive: bool = true,
    delta: Delta = .{ .Sleep = 0 },
};

const Fabric = struct {
    threads: []Clock,
    tempo: f64,
    clock: ?std.Thread,
    lock: std.Thread.Mutex,
    tick: u64,
    ticks_since_start: u64,
    time: u64,
    quit: bool,
    link: c.abl_link,
    state: c.abl_link_session_state,
    peers: u64 = 0,
    source: Source,
    fn init(self: *Fabric) !void {
        self.time = timer.read();
        self.ticks_since_start = 0;
        self.quit = false;
        self.source = .Internal;
        self.threads = try allocator.alloc(Clock, 100);
        @memset(self.threads, .{});
        set_tempo(120);
        self.link = c.abl_link_create(120);
        self.state = c.abl_link_create_session_state();
        c.abl_link_set_start_stop_callback(self.link, start_stop_callback, self);
        c.abl_link_set_num_peers_callback(self.link, peers_callback, self);
        c.abl_link_set_tempo_callback(self.link, tempo_callback, self);
        c.abl_link_enable_start_stop_sync(self.link, true);
        self.lock = .{};
        self.clock = try std.Thread.spawn(.{}, loop, .{self});
    }
    fn deinit(self: *Fabric) void {
        self.quit = true;
        if (self.clock) |clk| clk.join();
        c.abl_link_destroy_session_state(self.state);
        c.abl_link_destroy(self.link);
        allocator.free(self.threads);
        allocator.destroy(self);
    }
    fn loop(self: *Fabric) void {
        pthread.set_priority(90);
        while (!self.quit) {
            self.lock.lock();
            self.do_tick();
            self.lock.unlock();
            self.wait();
            self.ticks_since_start += 1;
        }
    }
    fn do_tick(self: *Fabric) void {
        for (self.threads, 0..) |*thread, i| {
            if (thread.inactive) continue;
            switch (thread.delta) {
                .Sleep => |*delta| {
                    delta.* -= self.tick;
                    if (delta.* <= 0) {
                        thread.inactive = true;
                        events.post(.{ .Clock_Resume = .{
                            .id = @intCast(i),
                        } });
                    }
                },
                .Sync => |*delta| {
                    delta.* -= 1;
                    if (delta.* == 0) {
                        thread.inactive = true;
                        events.post(.{ .Clock_Resume = .{
                            .id = @intCast(i),
                        } });
                    }
                },
            }
        }
    }
    fn wait(self: *Fabric) void {
        self.time += self.tick;
        self.lock.lock();
        const source = self.source;
        self.lock.unlock();
        switch (source) {
            .Link => {
                c.abl_link_capture_audio_session_state(self.link, self.state);
                defer c.abl_link_commit_audio_session_state(self.link, self.state);
                const now = c.abl_link_clock_micros(self.link);
                const eps: f64 = 1.0 / (96.0 * 24);
                const current_beat = c.abl_link_beat_at_time(self.state, @intCast(now), eps);
                const phase = @mod(current_beat, eps);
                const next_beat = current_beat + eps - phase;
                const next_time = c.abl_link_time_at_beat(self.state, next_beat, eps);
                const wait_time: i128 = (next_time - now) * std.time.ns_per_us;
                if (wait_time > 0) std.time.sleep(@intCast(wait_time));
            },
            else => {
                const wait_time = @as(i128, self.time) - timer.read();
                if (wait_time > 0) std.time.sleep(@intCast(wait_time));
            },
        }
    }
};

var allocator: std.mem.Allocator = undefined;
var fabric: *Fabric = undefined;
var timer: std.time.Timer = undefined;

pub fn init(time: std.time.Timer, alloc_pointer: std.mem.Allocator) !void {
    timer = time;
    allocator = alloc_pointer;
    fabric = try allocator.create(Fabric);
    try fabric.init();
}

pub fn deinit() void {
    fabric.deinit();
    fabric.* = undefined;
}

pub fn set_tempo(bpm: f64) void {
    fabric.tempo = bpm;
    const beats_per_sec = bpm / 60;
    const ticks_per_sec = beats_per_sec * 96 * 24;
    const seconds_per_tick = 1.0 / ticks_per_sec;
    const nanoseconds_per_tick = seconds_per_tick * std.time.ns_per_s;
    fabric.tick = @intFromFloat(nanoseconds_per_tick);
}

pub fn get_tempo() f64 {
    return fabric.tempo;
}

pub fn get_beats() f64 {
    const ticks: f64 = @floatFromInt(fabric.ticks_since_start);
    return ticks / (96.0 * 24.0);
}

pub fn cancel(id: u8) void {
    fabric.lock.lock();
    var clock = &fabric.threads[id];
    clock.inactive = true;
    clock.delta = .{ .Sleep = 0 };
    fabric.lock.unlock();
}

pub fn schedule_sleep(id: u8, seconds: f64) void {
    fabric.lock.lock();
    const delta: u64 = @intFromFloat(seconds * std.time.ns_per_s);
    var clock = &fabric.threads[id];
    switch (clock.delta) {
        .Sleep => |*d| {
            d.* += delta;
        },
        .Sync => {
            clock.delta = .{ .Sleep = delta };
        },
    }
    clock.inactive = false;
    fabric.lock.unlock();
}

pub fn schedule_sync(id: u8, beat: f64, offset: f64) void {
    const ticks_from_beat: u64 = @intFromFloat(beat * 96.0 * 24.0);
    const ticks_from_offset: u64 = @intFromFloat(offset * 96.0 * 24.0);
    fabric.lock.lock();
    const current_tick = @mod(fabric.ticks_since_start, ticks_from_beat);
    const ticks = ticks_from_beat - current_tick + ticks_from_offset;
    var clock = &fabric.threads[id];
    clock.delta = .{ .Sync = ticks };
    clock.inactive = false;
    fabric.lock.unlock();
}

pub fn stop() void {
    const event = .{
        .Clock_Transport = .{
            .transport = .Stop,
        },
    };
    events.post(event);
}

pub fn start() void {
    const event = .{
        .Clock_Transport = .{
            .transport = .Start,
        },
    };
    events.post(event);
}

pub fn reset(beat: u64) void {
    const num_ticks = beat * 96 * 24;
    fabric.ticks_since_start = num_ticks;
    var event = .{
        .Clock_Transport = .{
            .transport = .Reset,
        },
    };
    events.post(event);
}

pub fn midi(message: u8) !void {
    if (fabric.source != .MIDI) {
        if (message == 0xf8) last = timer.read();
        return;
    }
    switch (message) {
        0xfa => {
            start();
            reset(0);
        },
        0xfc => {
            stop();
        },
        0xfb => {
            start();
        },
        0xf8 => {
            midi_update_tempo();
        },
        else => {},
    }
}

var last: u64 = 0;

fn midi_update_tempo() void {
    const midi_tick = timer.read();
    const tick_from_midi_tick = @divFloor(midi_tick - last, 96);
    fabric.tick = @divFloor(tick_from_midi_tick + fabric.tick, 2);
    const ns_per_tick: f64 = @floatFromInt(fabric.tick);
    const ticks_per_sec = std.time.ns_per_s / ns_per_tick;
    const ticks_per_min = ticks_per_sec * 60;
    fabric.tempo = ticks_per_min / (96.0 * 24.0);
    last = midi_tick;
}

pub fn set_source(new: Source) !void {
    c.abl_link_enable(fabric.link, new == .Link);
    fabric.lock.lock();
    fabric.source = new;
    fabric.lock.unlock();
}

fn start_stop_callback(is_playing: bool, context: ?*anyopaque) callconv(.C) void {
    var ctx = context orelse return;
    var self: *Fabric = @ptrCast(@alignCast(ctx));
    if (self.source == .Link) {
        if (is_playing) start() else stop();
    }
}

fn tempo_callback(tempo: f64, context: ?*anyopaque) callconv(.C) void {
    var ctx = context orelse return;
    var self: *Fabric = @ptrCast(@alignCast(ctx));
    if (self.source == .Link) {
        set_tempo(tempo);
    }
}

fn peers_callback(peers: u64, context: ?*anyopaque) callconv(.C) void {
    var ctx = context orelse return;
    var self: *Fabric = @ptrCast(@alignCast(ctx));
    self.peers = peers;
}

pub fn link_set_tempo(bpm: f64) void {
    set_tempo(bpm);
    c.abl_link_capture_app_session_state(fabric.link, fabric.state);
    defer c.abl_link_commit_app_session_state(fabric.link, fabric.state);
    const now = c.abl_link_clock_micros(fabric.link);
    c.abl_link_set_tempo(fabric.state, bpm, now);
}

pub fn link_start() void {
    c.abl_link_capture_app_session_state(fabric.link, fabric.state);
    defer c.abl_link_commit_app_session_state(fabric.link, fabric.state);
    const time = c.abl_link_clock_micros(fabric.link);
    c.abl_link_set_is_playing(fabric.state, true, @intCast(time));
}

pub fn link_stop() void {
    c.abl_link_capture_app_session_state(fabric.link, fabric.state);
    defer c.abl_link_commit_app_session_state(fabric.link, fabric.state);
    const time = c.abl_link_clock_micros(fabric.link);
    c.abl_link_set_is_playing(fabric.state, false, @intCast(time));
}
