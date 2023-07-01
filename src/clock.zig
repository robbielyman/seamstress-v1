const std = @import("std");
const events = @import("events.zig");

pub const Transport = enum { Start, Stop, Reset };

pub const Source = enum(c_longlong) { Internal, MIDI, Link };

const Clock = struct {
    inactive: bool = true,
    delta: i128 = 0,
};

const Fabric = struct {
    threads: []Clock,
    tempo: f64,
    clock: ?std.Thread,
    lock: std.Thread.Mutex,
    tick: u64,
    ticks_since_start: u64,
    quit: bool,
    fn init(self: *Fabric) !void {
        self.threads = try allocator.alloc(Clock, 100);
        var i: u8 = 0;
        while (i < 100) : (i += 1) {
            self.threads[i] = Clock{};
        }
        set_tempo(120);
        self.lock = .{};
        self.clock = try std.Thread.spawn(.{}, loop, .{self});
    }
    fn deinit(self: *Fabric) void {
        self.quit = true;
        if (self.clock) |c| c.join();
        allocator.free(self.threads);
        allocator.destroy(self);
    }
    fn loop(self: *Fabric) void {
        while (!self.quit) {
            self.do_tick();
            wait(self.tick);
            self.ticks_since_start += 1;
        }
    }
    fn do_tick(self: *Fabric) void {
        var i: u8 = 0;
        self.lock.lock();
        while (i < 100) : (i += 1) {
            if (!self.threads[i].inactive) {
                self.threads[i].delta -= self.tick;
                if (self.threads[i].delta <= 0) {
                    self.threads[i].delta = 0;
                    self.threads[i].inactive = true;
                    events.post(.{ .Clock_Resume = .{ .id = i } });
                }
            }
        }
        self.lock.unlock();
    }
};

var allocator: std.mem.Allocator = undefined;
var fabric: *Fabric = undefined;
var source: Source = .Internal;

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    allocator = alloc_pointer;
    fabric = try allocator.create(Fabric);
    try fabric.init();
}

pub fn deinit() void {
    fabric.deinit();
}

pub fn set_tempo(bpm: f64) void {
    fabric.tempo = bpm;
    const beats_per_sec = bpm / 60;
    const ticks_per_sec = beats_per_sec * 96;
    const seconds_per_tick = 1.0 / ticks_per_sec;
    const nanoseconds_per_tick = seconds_per_tick * std.time.ns_per_s;
    fabric.tick = @intFromFloat(nanoseconds_per_tick);
}

pub fn get_tempo() f64 {
    return fabric.tempo;
}

pub fn get_beats() f64 {
    const ticks: f64 = @floatFromInt(fabric.ticks_since_start);
    return ticks / 96.0;
}

fn wait(nanoseconds: u64) void {
    // for now, just call sleep
    std.time.sleep(nanoseconds);
}

pub fn cancel(id: u8) void {
    fabric.threads[id].inactive = true;
    fabric.threads[id].delta = 0;
}

pub fn schedule_sleep(id: u8, seconds: f64) void {
    fabric.lock.lock();
    const delta: u64 = @intFromFloat(seconds * std.time.ns_per_s);
    fabric.threads[id].delta = delta;
    fabric.threads[id].inactive = false;
    fabric.lock.unlock();
}

pub fn schedule_sync(id: u8, beat: f64, offset: f64) void {
    fabric.lock.lock();
    const tick_sync = beat * 96;
    const since_start: f64 = @floatFromInt(fabric.ticks_since_start);
    const ticks_elapsed = std.math.mod(f64, since_start, tick_sync) catch unreachable;
    const next_tick = tick_sync - ticks_elapsed + offset;
    const tick: f64 = @floatFromInt(fabric.tick);
    const delta: u64 = @intFromFloat(next_tick * tick);
    fabric.threads[id].delta = delta;
    fabric.threads[id].inactive = false;
    fabric.lock.unlock();
}

pub fn stop() void {
    fabric.quit = true;
    if (fabric.clock) |pid| pid.join();
    fabric.clock = null;
    const event = .{
        .Clock_Transport = .{
            .transport = .Stop,
        },
    };
    events.post(event);
}

pub fn start() !void {
    if (fabric.clock == null) {
        fabric.clock = try std.Thread.spawn(.{}, Fabric.loop, .{fabric});
    }
    const event = .{
        .Clock_Transport = .{
            .transport = .Start,
        },
    };
    events.post(event);
}

pub fn reset(beat: u64) void {
    const num_ticks = beat * 96;
    fabric.ticks_since_start = num_ticks;
    var event = .{
        .Clock_Transport = .{
            .transport = .Reset,
        },
    };
    events.post(event);
}

pub fn midi(message: u8, timestamp: f64) !void {
    switch (source) {
        .MIDI => {},
        else => return,
    }
    switch (message) {
        0xfa => {
            try start();
            reset(0);
        },
        0xfc => {
            stop();
        },
        0xfb => {
            try start();
        },
        0xf8 => {
            midi_update_tempo(timestamp);
        },
        else => {},
    }
}

// var last: f64 = -1;

fn midi_update_tempo(timestamp: f64) void {
    const new_bpm = 60 / (24 * timestamp);
    set_tempo((new_bpm + fabric.tempo) / 2);
}

pub fn set_source(new: Source) !void {
    defer source = new;
    if (source != new) {
        switch (new) {
            .MIDI => try start(),
            .Internal => try start(),
            .Link => {},
        }
    }
}

pub fn link_set_tempo(bpm: f64) void {
    _ = bpm;
}
