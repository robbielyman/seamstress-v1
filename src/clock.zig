const std = @import("std");
const events = @import("events.zig");
const pthread = @import("pthread.zig");
const c = @cImport({
    @cInclude("abl_link.h");
});

var allocator: std.mem.Allocator = undefined;
var fabric: *Fabric = undefined;
var timer: std.time.Timer = undefined;
var quantum: f64 = 4.0;
pub const Transport = enum { Start, Stop, Reset };
pub const Source = enum(c_longlong) { Internal, MIDI, Link };

pub fn init(time: std.time.Timer, alloc_pointer: std.mem.Allocator) !void {
    timer = time;
    allocator = alloc_pointer;
    fabric = try allocator.create(Fabric);
    fabric.link = c.abl_link_create(120);
    fabric.state = c.abl_link_create_session_state();
    c.abl_link_set_start_stop_callback(fabric.link, start_stop_callback, fabric);
    c.abl_link_set_tempo_callback(fabric.link, tempo_callback, fabric);
    c.abl_link_enable_start_stop_sync(fabric.link, true);
    const now = timer.read();
    internal_beat_reference = .{
        .beat = .{
            .last_beat_time = now,
            .beats = 0,
            .beat_duration = @divFloor(std.time.ns_per_min, 120 * 96),
        },
        .lock = .{},
        .quit = false,
        .thread = try std.Thread.spawn(.{}, Internal_Beat_Reference.loop, .{&internal_beat_reference}),
    };
    midi_beat_reference = .{
        .last_beat_time = now,
        .beats = 0,
        .beat_duration = @divFloor(std.time.ns_per_min, 120 * 96),
    };
    link_beat_reference = .{
        .beat = .{
            .last_beat_time = now,
            .beats = 0,
            .beat_duration = @divFloor(std.time.ns_per_min, 120 * 96),
        },
        .lock = .{},
        .quit = false,
        .thread = try std.Thread.spawn(.{}, Link_Beat_Reference.loop, .{&link_beat_reference}),
    };
    try fabric.init();
}

pub fn deinit() void {
    internal_beat_reference.quit = true;
    link_beat_reference.quit = true;
    internal_beat_reference.thread.join();
    link_beat_reference.thread.join();
    fabric.deinit();
    fabric.* = undefined;
}

const Clock = struct {
    inactive: bool = true,
    data: union(enum) {
        Sleep: i128,
        Sync: struct {
            beat: f64,
            sync: f64,
            offset: f64,
        },
    },
};

const Fabric = struct {
    threads: []Clock,
    tempo: f64,
    clock: std.Thread,
    lock: std.Thread.Mutex,
    quit: bool,
    link: c.abl_link,
    state: c.abl_link_session_state,
    source: Source,
    fn init(self: *Fabric) !void {
        quantum = 4;
        self.quit = false;
        self.source = .Internal;
        self.threads = try allocator.alloc(Clock, 100);
        @memset(self.threads, .{ .data = .{ .Sleep = 0 } });
        internal_set_tempo(120);
        self.lock = .{};
        self.clock = try std.Thread.spawn(.{}, loop, .{self});
    }
    fn deinit(self: *Fabric) void {
        self.quit = true;
        self.clock.join();
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
            std.time.sleep(1000);
        }
    }
    fn do_tick(self: *Fabric) void {
        const now = timer.read();
        const current_beat = get_beats();
        for (self.threads, 0..) |*thread, i| {
            if (thread.inactive) continue;
            switch (thread.data) {
                .Sleep => |time| if (now > time) {
                    thread.inactive = true;
                    events.post(.{ .Clock_Resume = .{
                        .id = @intCast(i),
                    } });
                },
                .Sync => |sync| if (current_beat > sync.beat) {
                    thread.inactive = true;
                    events.post(.{ .Clock_Resume = .{
                        .id = @intCast(i),
                    } });
                },
            }
        }
    }
};

const Beat = struct {
    last_beat_time: u64,
    beats: f64,
    beat_duration: u64,
};

const Internal_Beat_Reference = struct {
    beat: Beat,
    lock: std.Thread.Mutex,
    thread: std.Thread,
    quit: bool,
    fn loop(self: *@This()) void {
        self.beat.last_beat_time = timer.read();
        self.beat.beats = 0;
        while (!self.quit) {
            self.lock.lock();
            const next = self.beat.last_beat_time + self.beat.beat_duration;
            defer self.beat.last_beat_time = next;
            self.lock.unlock();
            const wait_time = @as(i128, next) - timer.read();
            if (wait_time > 0) std.time.sleep(@intCast(wait_time));
            self.lock.lock();
            self.beat.beats += 1.0 / 96.0;
            self.lock.unlock();
        }
    }
};
const Link_Beat_Reference = struct {
    beat: Beat,
    lock: std.Thread.Mutex,
    thread: std.Thread,
    quit: bool,
    fn loop(self: *@This()) void {
        while (!self.quit) {
            c.abl_link_capture_audio_session_state(fabric.link, fabric.state);
            self.lock.lock();
            self.beat.last_beat_time = timer.read();
            const now = c.abl_link_clock_micros(fabric.link);
            self.beat.beats = c.abl_link_beat_at_time(fabric.state, @intCast(now - 1), quantum);
            const micros = c.abl_link_time_at_beat(fabric.state, self.beat.beats + 1, quantum);
            self.beat.beat_duration = @intCast(@as(i128, micros - now) * std.time.ns_per_us);
            self.lock.unlock();
            c.abl_link_commit_audio_session_state(fabric.link, fabric.state);
            std.time.sleep(1000);
        }
    }
};

var internal_beat_reference: Internal_Beat_Reference = undefined;
var link_beat_reference: Link_Beat_Reference = undefined;
var midi_beat_reference: Beat = undefined;

pub fn internal_set_tempo(bpm: f64) void {
    defer fabric.tempo = bpm;
    internal_beat_reference.lock.lock();
    defer internal_beat_reference.lock.unlock();
    internal_beat_reference.beat.beat_duration = @intFromFloat(std.time.ns_per_min / bpm);
}

pub fn link_set_tempo(bpm: f64) void {
    fabric.tempo = bpm;
    c.abl_link_capture_app_session_state(fabric.link, fabric.state);
    defer c.abl_link_commit_app_session_state(fabric.link, fabric.state);
    const now = c.abl_link_clock_micros(fabric.link);
    c.abl_link_set_tempo(fabric.state, bpm, now);
}

pub fn get_tempo() f64 {
    return fabric.tempo;
}

fn get_delta(now: i128, then: u64, duration: u64) f64 {
    const numerator: i128 = now - then;
    const fnum: f64 = @floatFromInt(numerator);
    return fnum / @as(f64, @floatFromInt(duration));
}

pub fn get_beats() f64 {
    switch (fabric.source) {
        .Internal => {
            internal_beat_reference.lock.lock();
            defer internal_beat_reference.lock.unlock();
            const delta = get_delta(timer.read(), internal_beat_reference.beat.last_beat_time, internal_beat_reference.beat.beat_duration);
            return internal_beat_reference.beat.beats + delta;
        },
        .MIDI => {
            const delta = get_delta(timer.read(), midi_beat_reference.last_beat_time, midi_beat_reference.beat_duration);
            return midi_beat_reference.beats + delta;
        },
        .Link => {
            link_beat_reference.lock.lock();
            defer link_beat_reference.lock.unlock();
            return link_beat_reference.beat.beats;
        },
    }
}

fn get_sync_beat(clock_beat: f64, sync_beat: f64, offset: f64) f64 {
    var next_beat: f64 = (std.math.floor((clock_beat + std.math.floatEps(f64)) / sync_beat) + 1) * sync_beat;
    next_beat = next_beat + offset;
    while (next_beat < (clock_beat + std.math.floatEps(f64))) next_beat += sync_beat;
    return next_beat;
}

pub fn cancel(id: u8) void {
    fabric.lock.lock();
    var clock = &fabric.threads[id];
    clock.inactive = true;
    clock.data = .{ .Sleep = 0 };
    fabric.lock.unlock();
}

pub fn schedule_sleep(id: u8, seconds: f64) void {
    fabric.lock.lock();
    const delta: u64 = @intFromFloat(seconds * std.time.ns_per_s);
    var clock = &fabric.threads[id];
    clock.data = .{ .Sleep = timer.read() + delta };
    clock.inactive = false;
    fabric.lock.unlock();
}

pub fn schedule_sync(id: u8, beat: f64, offset: f64) void {
    const clock_beat = get_beats();
    const sync_beat = get_sync_beat(clock_beat, beat, offset);
    fabric.lock.lock();
    var clock = &fabric.threads[id];
    clock.data = .{ .Sync = .{
        .beat = sync_beat,
        .sync = beat,
        .offset = offset,
    } };
    clock.inactive = false;
    fabric.lock.unlock();
}

fn reschedule_sync_events() void {
    const clock_beat = get_beats();
    fabric.lock.lock();
    defer fabric.lock.unlock();
    for (fabric.threads) |*thread| {
        if (thread.inactive) continue;
        switch (thread.data) {
            .Sleep => continue,
            .Sync => |*data| {
                data.beat = get_sync_beat(clock_beat, data.sync, data.offset);
            },
        }
    }
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

fn reset(beat: f64) void {
    switch (fabric.source) {
        .Internal => {
            internal_beat_reference.lock.lock();
            internal_beat_reference.beat.beats = beat;
            internal_beat_reference.lock.unlock();
            reschedule_sync_events();
        },
        .MIDI => {
            midi_beat_reference.beats = beat;
            reschedule_sync_events();
        },
        .Link => {
            link_beat_reference.lock.lock();
            link_beat_reference.beat.beats = beat;
            link_beat_reference.lock.unlock();
            reschedule_sync_events();
        },
    }
    events.post(.{
        .Clock_Transport = .{ .transport = .Reset },
    });
}

pub fn midi(message: u8) void {
    if (fabric.source != .MIDI and message == 0xf8) {
        midi_tick();
        return;
    }
    switch (message) {
        0xfa => {
            start();
            reset(0);
            midi_beat_reference.last_beat_time = timer.read();
        },
        0xfc => {
            stop();
        },
        0xfb => {
            start();
        },
        0xf8 => {
            midi_tick();
        },
        else => {},
    }
}

fn midi_tick() void {
    const now = timer.read();
    midi_beat_reference.beat_duration = (now - midi_beat_reference.last_beat_time) * 24;
    midi_beat_reference.last_beat_time = now;
    midi_beat_reference.beats += 1.0 / 24.0;
}

pub fn set_source(new: Source) !void {
    c.abl_link_enable(fabric.link, new == .Link);
    fabric.source = new;
    reschedule_sync_events();
}

fn start_stop_callback(is_playing: bool, context: ?*anyopaque) callconv(.C) void {
    std.debug.print("are we playing: {}\n", .{is_playing});
    var ctx = context orelse return;
    var self: *Fabric = @ptrCast(@alignCast(ctx));
    if (self.source == .Link) {
        if (!is_playing) stop();
    }
}

fn tempo_callback(tempo: f64, context: ?*anyopaque) callconv(.C) void {
    var ctx = context orelse return;
    var self: *Fabric = @ptrCast(@alignCast(ctx));
    if (self.source == .Link) {
        fabric.tempo = tempo;
    }
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
