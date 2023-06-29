const std = @import("std");
const events = @import("events.zig");

const Status = enum { Running, Stopped };
const logger = std.log.scoped(.metros);

const Metro = struct {
    // metro struct
    status: Status = .Stopped,
    seconds: f64 = 1.0,
    id: u8,
    hot: bool = true,
    count: i64 = -1,
    stage: i64 = 0,
    delta: u64 = undefined,
    thread: ?std.Thread = null,
    stage_lock: std.Thread.Mutex = .{},
    status_lock: std.Thread.Mutex = .{},
    fn stop(self: *Metro) void {
        self.status_lock.lock();
        self.status = Status.Stopped;
        self.status_lock.unlock();
        if (self.thread) |pid| {
            pid.join();
        }
        self.thread = null;
    }
    fn bang(self: *Metro) void {
        const event = .{ .Metro = .{ .id = self.id, .stage = self.stage } };
        events.post(event);
    }
    fn init(self: *Metro, delta: u64, count: i64) !void {
        self.delta = delta;
        self.count = count;
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
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
    var metro = &metros[idx];
    metro.status_lock.lock();
    if (metro.status == Status.Running) {
        metro.stop();
    }
    metro.status_lock.unlock();
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    const delta: u64 = @intFromFloat(metro.seconds * std.time.ns_per_s);
    metro.reset(stage);
    try metro.init(delta, count);
}

pub fn set_period(idx: u8, seconds: f64) !void {
    if (idx < 0 or idx >= max_num_metros) return;
    var metro = metros[idx];
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    metro.delta = @intFromFloat(metro.seconds * std.time.ns_per_s);
}

const max_num_metros = 36;
var metros: []Metro = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    allocator = alloc_pointer;
    metros = try allocator.alloc(Metro, max_num_metros);
    for (metros, 0..) |*metro, idx| {
        metro.* = .{ .id = @intCast(idx) };
    }
}

pub fn set_hot(idx: u8) void {
    metros[idx].hot = true;
}

pub fn deinit() void {
    defer allocator.free(metros);
    for (metros) |*metro| metro.stop();
}

fn loop(self: *Metro) void {
    var quit = false;
    self.status_lock.lock();
    self.status = Status.Running;
    self.status_lock.unlock();

    while (!quit) {
        std.time.sleep(self.delta);
        self.stage_lock.lock();
        if (self.stage >= self.count and self.count >= 0) {
            quit = true;
        }
        self.stage_lock.unlock();
        self.status_lock.lock();
        if (self.status == Status.Stopped) {
            quit = true;
        }
        self.status_lock.unlock();
        if (quit) break;
        self.bang();
        self.stage_lock.lock();
        self.stage += 1;
        self.stage_lock.unlock();
    }
    self.status_lock.lock();
    self.status = Status.Stopped;
    self.status_lock.unlock();
}
