const std = @import("std");
const events = @import("events.zig");
const pthread = @import("pthread.zig");
const c = @cImport({
    @cInclude("abl_link.h");
});

var buf: [8 * 1024]u8 = undefined;
var allocator: std.mem.Allocator = undefined;
var fabric: *Fabric = undefined;
var timer: std.time.Timer = undefined;
var quantum: f64 = 4.0;
pub const Transport = enum { Start, Stop, Reset };
pub const Source = enum(c_longlong) { Internal, MIDI, Link };
const logger = std.log.scoped(.clock);

pub fn init(time: std.time.Timer) !void {
    quantum = 4.0;
    timer = time;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    allocator = fba.allocator();
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
            .beat_duration = @divFloor(std.time.ns_per_min, 120),
        },
        .lock = .{},
        .quit = false,
        .thread = undefined,
    };
    internal_beat_reference.thread = try std.Thread.spawn(.{}, Internal_Beat_Reference.loop, .{&internal_beat_reference});
    midi_beat_reference = .{
        .beat = .{
            .last_beat_time = now,
            .beats = 0,
            .beat_duration = @divFloor(std.time.ns_per_min, 120),
        },
        .duration_buf = .{@divFloor(std.time.ns_per_min, 120)} ** 6,
        .idx = 0,
        .lock = .{},
    };
    link_beat_reference = .{
        .beat = .{
            .last_beat_time = now,
            .beats = 0,
            .beat_duration = @divFloor(std.time.ns_per_min, 120),
        },
        .lock = .{},
        .quit = false,
        .flag = false,
        .thread = undefined,
    };
    link_beat_reference.thread = try std.Thread.spawn(.{}, Link_Beat_Reference.loop, .{&link_beat_reference});
    try fabric.init();
}

pub fn deinit() void {
    internal_beat_reference.quit = true;
    link_beat_reference.quit = true;
    internal_beat_reference.thread.join();
    link_beat_reference.thread.join();
    fabric.deinit();
}

const Clock = struct {
    id: u8 = 255,
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
    fn find(self: *Fabric, id: u8) ?*Clock {
        var ret: ?*Clock = null;
        for (self.threads) |*clock| {
            if (clock.id == id) return clock;
            if (ret == null and clock.id == 255) ret = clock;
        }
        return ret;
    }
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
        self.clock.setName("clock_scheduler") catch {};
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
        for (self.threads) |*thread| {
            if (thread.id == 255) continue;
            if (thread.inactive) continue;
            switch (thread.data) {
                .Sleep => |time| if (now > time) {
                    thread.inactive = true;
                    events.post(.{ .Clock_Resume = .{
                        .id = thread.id,
                    } });
                },
                .Sync => |sync| if (current_beat > sync.beat) {
                    thread.inactive = true;
                    events.post(.{ .Clock_Resume = .{
                        .id = thread.id,
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
        self.thread.setName("internal_clock_thread") catch {};
        self.beat.last_beat_time = timer.read();
        self.beat.beats = 0;
        while (!self.quit) {
            self.lock.lock();
            const next = self.beat.last_beat_time + @divFloor(self.beat.beat_duration, 96);
            defer self.beat.last_beat_time = next;
            self.lock.unlock();
            const wait_time = @as(i128, next) - timer.read();
            if (wait_time > 0) std.time.sleep(@intCast(wait_time));
            self.lock.lock();
            self.beat.beats = self.beat.beats + (1.0 / 96.0);
            self.lock.unlock();
        }
    }
};
const Link_Beat_Reference = struct {
    beat: Beat,
    lock: std.Thread.Mutex,
    thread: std.Thread,
    quit: bool,
    flag: bool,
    fn loop(self: *@This()) void {
        self.thread.setName("link_clock_thread") catch {};
        while (!self.quit) {
            c.abl_link_capture_audio_session_state(fabric.link, fabric.state);
            self.lock.lock();
            self.beat.last_beat_time = timer.read();
            const now = c.abl_link_clock_micros(fabric.link);
            const beat = c.abl_link_beat_at_time(fabric.state, @intCast(now), quantum);
            // const phase = c.abl_link_phase_at_time(fabric.state, @intCast(now), quantum);
            const last = self.beat.beats;
            self.beat.beats = beat;
            const micros = c.abl_link_time_at_beat(fabric.state, beat + 1, quantum);
            if (micros > now) {
                self.beat.beat_duration = @intCast((micros - now) * std.time.ns_per_us);
            }
            self.lock.unlock();
            if (self.flag and beat > 0 and beat < 1) {
                self.flag = false;
                start();
                reschedule_sync_events();
            }
            if (last > beat) reschedule_sync_events();
            c.abl_link_commit_audio_session_state(fabric.link, fabric.state);
            std.time.sleep(1000);
        }
    }
};
const Midi_Beat_Reference = struct {
    beat: Beat,
    duration_buf: [6]u64,
    idx: u8,
    lock: std.Thread.Mutex,
};

var internal_beat_reference: Internal_Beat_Reference = undefined;
var link_beat_reference: Link_Beat_Reference = undefined;
var midi_beat_reference: Midi_Beat_Reference = undefined;

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
    if (numerator <= 0) return 0;
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
            midi_beat_reference.lock.lock();
            defer midi_beat_reference.lock.unlock();
            const delta = get_delta(timer.read(), midi_beat_reference.beat.last_beat_time, midi_beat_reference.beat.beat_duration);
            return midi_beat_reference.beat.beats + delta;
        },
        .Link => {
            link_beat_reference.lock.lock();
            defer link_beat_reference.lock.unlock();
            return link_beat_reference.beat.beats;
        },
    }
}

pub fn set_quantum(q: f64) void {
    quantum = q;
}

fn get_sync_beat(clock_beat: f64, sync_beat: f64, offset: f64) f64 {
    var next_beat: f64 = (std.math.floor((clock_beat + std.math.floatEps(f64)) / sync_beat) + 1) * sync_beat;
    next_beat = next_beat + offset;
    while (next_beat < (clock_beat + std.math.floatEps(f64))) next_beat += sync_beat;
    return next_beat;
}

pub fn cancel(id: u8) void {
    fabric.lock.lock();
    defer fabric.lock.unlock();
    for (fabric.threads) |*clock| {
        if (clock.id != id) continue;
        clock.id = 255;
        clock.inactive = true;
        clock.data = .{ .Sleep = 0 };
    }
}

pub fn schedule_sleep(id: u8, seconds: f64) void {
    fabric.lock.lock();
    defer fabric.lock.unlock();
    const delta: u64 = @intFromFloat(seconds * std.time.ns_per_s);
    var clock = fabric.find(id) orelse {
        logger.warn("unable to find clock thread for id {d}", .{id});
        return;
    };
    clock.data = .{ .Sleep = timer.read() + delta };
    clock.inactive = false;
    clock.id = id;
}

pub fn schedule_sync(id: u8, beat: f64, offset: f64) void {
    const clock_beat = get_beats();
    fabric.lock.lock();
    defer fabric.lock.unlock();
    var clock = fabric.find(id) orelse {
        logger.warn("unable to find clock thread for id {d}", .{id});
        return;
    };
    const sync_beat = get_sync_beat(clock_beat, beat, offset);
    clock.data = .{ .Sync = .{
        .beat = sync_beat,
        .sync = beat,
        .offset = offset,
    } };
    clock.id = id;
    clock.inactive = false;
}

fn reschedule_sync_events() void {
    const clock_beat = get_beats();
    logger.info("rescheduling at beat {d}", .{clock_beat});
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

pub fn reset(beat: f64) void {
    switch (fabric.source) {
        .Internal => {
            internal_beat_reference.lock.lock();
            internal_beat_reference.beat.beats = beat;
            internal_beat_reference.lock.unlock();
            reschedule_sync_events();
        },
        .MIDI => {
            midi_beat_reference.lock.lock();
            midi_beat_reference.beat.beats = beat;
            midi_beat_reference.lock.unlock();
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
    if (fabric.source != .MIDI) {
        if (message == 0xf8) {
            midi_tick();
        }
        return;
    }
    switch (message) {
        0xfa => {
            const now = timer.read();
            start();
            reset(0);
            midi_beat_reference.lock.lock();
            midi_beat_reference.beat.last_beat_time = now;
            midi_beat_reference.lock.unlock();
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
    midi_beat_reference.lock.lock();
    defer midi_beat_reference.lock.unlock();
    midi_beat_reference.beat.beats += 1.0 / 24.0;
    if (now < midi_beat_reference.beat.last_beat_time) return;
    midi_beat_reference.idx = @mod(midi_beat_reference.idx + 1, 6);
    midi_beat_reference.duration_buf[midi_beat_reference.idx] = (now - midi_beat_reference.beat.last_beat_time) * 4;
    var duration: u64 = 0;
    inline for (midi_beat_reference.duration_buf) |dur| {
        duration += dur;
    }
    midi_beat_reference.beat.beat_duration = @divFloor(duration + midi_beat_reference.beat.beat_duration, 2);
    fabric.tempo = @as(f64, std.time.ns_per_min) / @as(f64, @floatFromInt(midi_beat_reference.beat.beat_duration));
    midi_beat_reference.beat.last_beat_time = now;
}

pub fn set_source(new: Source) !void {
    c.abl_link_enable(fabric.link, new == .Link);
    if (new == .Internal) internal_set_tempo(fabric.tempo);
    if (new != fabric.source) {
        fabric.source = new;
        reschedule_sync_events();
    }
}

fn start_stop_callback(is_playing: bool, context: ?*anyopaque) callconv(.C) void {
    var ctx = context orelse return;
    var self: *Fabric = @ptrCast(@alignCast(ctx));
    if (self.source == .Link) {
        c.abl_link_capture_app_session_state(fabric.link, fabric.state);
        c.abl_link_set_is_playing_and_request_beat_at_time(
            fabric.state,
            is_playing,
            @intCast(c.abl_link_clock_micros(fabric.link)),
            0,
            quantum,
        );
        c.abl_link_commit_app_session_state(fabric.link, fabric.state);
        if (is_playing) {
            link_beat_reference.flag = true;
        } else stop();
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
    c.abl_link_set_is_playing_and_request_beat_at_time(
        fabric.state,
        true,
        @intCast(time),
        0.0,
        quantum,
    );
    link_beat_reference.flag = true;
}

pub fn link_stop() void {
    c.abl_link_capture_app_session_state(fabric.link, fabric.state);
    defer c.abl_link_commit_app_session_state(fabric.link, fabric.state);
    const time = c.abl_link_clock_micros(fabric.link);
    c.abl_link_set_is_playing(fabric.state, false, @intCast(time));
}
