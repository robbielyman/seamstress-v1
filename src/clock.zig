const std = @import("std");
const events = @import("events.zig");
const pthread = @import("pthread.zig");
const c = @cImport({
    @cInclude("abl_link.h");
});

const ticks_per_beat = ticks_per_midi_tick * 24;
const ticks_per_midi_tick = 96;
const beats_per_tick = 1.0 / (96.0 * 24.0);
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
        self.time = timer.read();
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
                const beat = get_beats();
                const now = c.abl_link_clock_micros(self.link);
                if (live_next_is_jump) c.abl_link_request_beat_at_time(self.state, beat, @intCast(now), beats_per_tick);
                live_next_is_jump = false;
                const next_time = c.abl_link_time_at_beat(self.state, beat + beats_per_tick, beats_per_tick);
                c.abl_link_commit_audio_session_state(self.link, self.state);
                const wait_time: i128 = next_time - now;
                if (wait_time > 0) std.time.sleep(@intCast(wait_time * std.time.ns_per_us));
            },
            else => {
                const wait_time = @as(i128, self.time) - timer.read();
                if (wait_time > 0) std.time.sleep(@intCast(wait_time));
            },
        }
    }
};

fn beats_to_tick(beats: f64) u64 {
    return @intFromFloat(beats * ticks_per_beat);
}

fn ticks_to_beats(ticks: u64) f64 {
    return @as(f64, @floatFromInt(ticks)) * beats_per_tick;
}

pub fn set_tempo(bpm: f64) void {
    fabric.tempo = bpm;
    const ticks_per_min = beats_to_tick(bpm);
    fabric.tick = @divFloor(std.time.ns_per_min, ticks_per_min);
}

pub fn get_tempo() f64 {
    return fabric.tempo;
}

pub fn get_beats() f64 {
    return ticks_to_beats(fabric.ticks_since_start);
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
    const ticks_sync = beats_to_tick(beat);
    const ticks_offset = beats_to_tick(offset);
    fabric.lock.lock();
    const current_phase = @mod(fabric.ticks_since_start, ticks_sync);
    const ticks = ticks_sync - current_phase + ticks_offset;
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

pub fn reset(beat: f64, silent: bool) void {
    fabric.ticks_since_start = beats_to_tick(beat);
    if (silent) return;
    var event = .{
        .Clock_Transport = .{
            .transport = .Reset,
        },
    };
    events.post(event);
}

pub fn midi(message: u8) !void {
    if (fabric.source != .MIDI) {
        if (message == 0xf8) {
            last = timer.read();
            midi_counter = @mod(midi_counter + 1, 24);
        }
        return;
    }
    switch (message) {
        0xfa => {
            start();
            reset(0, false);
            midi_counter = 0;
            next_is_first = true;
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
var midi_counter: u8 = 0;
var next_is_first = false;
var live_next_is_jump = false;

fn midi_update_tempo() void {
    const new = timer.read();
    midi_counter = @mod(midi_counter + 1, 24);
    defer last = new;
    const new_ticks_interval = @divFloor(new - last, ticks_per_midi_tick);
    fabric.tick = @divFloor(fabric.tick + new_ticks_interval, 2);
    const ticks_per_min: f64 = @as(f64, std.time.ns_per_min) / @as(f64, @floatFromInt(fabric.tick));
    fabric.tempo = ticks_per_min * beats_per_tick;
    if (next_is_first and midi_counter == 0) {
        reset(@divFloor(get_beats(), 1.0), true);
        next_is_first = false;
    }
}

pub fn set_source(new: Source) !void {
    fabric.lock.lock();
    c.abl_link_enable(fabric.link, new == .Link);
    live_next_is_jump = new == .Link;
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
