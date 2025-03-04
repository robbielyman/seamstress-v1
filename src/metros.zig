const std = @import("std");
const events = @import("events.zig");
const pthread = @import("pthread.zig");

const Status = enum { Running, Stopped };
const logger = std.log.scoped(.metros);
var timer: std.time.Timer = undefined;

const Thread = struct {
    pid: std.Thread = undefined,
    quit: bool = false,
    fn cancel(self: *Thread) void {
        self.quit = true;
        self.pid.detach();
    }
};

const Metro = struct {
    // metro struct
    status: Status = .Stopped,
    seconds: f64 = 1.0,
    id: u8,
    count: i64 = -1,
    stage: i64 = 0,
    delta: u64 = undefined,
    time: u64 = undefined,
    thread: ?Thread = null,
    stage_lock: std.Thread.Mutex = .{},
    status_lock: std.Thread.Mutex = .{},
    fn stop(self: *Metro) void {
        self.status_lock.lock();
        self.status = Status.Stopped;
        self.status_lock.unlock();
        if (self.thread) |*pid| {
            pid.cancel();
        }
        self.thread = null;
    }
    fn bang(self: *Metro) void {
        events.post(.{ .Metro = .{ .id = self.id, .stage = self.stage } });
    }
    fn init(self: *Metro, delta: u64, count: i64) !void {
        self.delta = delta;
        self.count = count;
        self.thread = .{
            .quit = false,
            .pid = try std.Thread.spawn(.{}, loop, .{self}),
        };
    }
    fn reset(self: *Metro, stage: i64) void {
        self.stage_lock.lock();
        if (stage > 0) {
            self.stage = stage;
        } else {
            self.stage = 0;
        }
        self.stage_lock.unlock();
    }
    fn wait(self: *Metro) void {
        self.time += self.delta;
        const wait_time = @as(i128, self.time) - timer.read();
        if (wait_time > 0) std.time.sleep(@intCast(wait_time));
    }
};

pub fn stop(idx: u8) void {
    if (idx < 0 or idx >= max_num_metros) {
        logger.warn("invalid index, max count of metros is {d}", .{max_num_metros});
        return;
    }
    metros[idx].stop();
}

pub fn start(idx: u8, seconds: f64, count: i64, stage: i64) !void {
    if (idx < 0 or idx >= max_num_metros) {
        logger.warn("invalid index; not added. max count of metros is {d}", .{max_num_metros});
        return;
    }
    const metro = &metros[idx];
    metro.status_lock.lock();
    if (metro.status == Status.Running) {
        metro.status_lock.unlock();
        metro.stop();
    } else metro.status_lock.unlock();
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    const delta: u64 = @intFromFloat(metro.seconds * std.time.ns_per_s);
    metro.reset(stage);
    try metro.init(delta, count);
}

pub fn set_period(idx: u8, seconds: f64) void {
    if (idx < 0 or idx >= max_num_metros) return;
    var metro = metros[idx];
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    metro.delta = @intFromFloat(metro.seconds * std.time.ns_per_s);
}

const max_num_metros = 36;
var metros: [max_num_metros]Metro = undefined;

pub fn init(time: std.time.Timer) !void {
    timer = time;
    for (&metros, 0..) |*metro, idx| {
        metro.* = .{ .id = @intCast(idx) };
    }
}

pub fn deinit() void {
    for (&metros) |*metro| {
        if (metro.thread) |*pid| {
            pid.quit = true;
            pid.pid.join();
        }
    }
}

fn loop(self: *Metro) void {
    self.status_lock.lock();
    self.status = Status.Running;
    self.status_lock.unlock();
    self.time = timer.read();
    while (!self.thread.?.quit) {
        self.wait();
        self.status_lock.lock();
        if (self.status == Status.Stopped) {
            self.thread.?.quit = true;
        }
        self.status_lock.unlock();
        if (self.thread.?.quit) break;
        self.bang();
        self.stage_lock.lock();
        self.stage += 1;
        if (self.stage >= self.count and self.count > 0) {
            self.thread.?.quit = true;
        }
        self.stage_lock.unlock();
    }
}
