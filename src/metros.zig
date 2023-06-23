const std = @import("std");
const events = @import("events.zig");

const Status = enum { Running, Stopped };
const logger = std.log.scoped(.metros);

const Metro_List = struct {
    const Node = struct { next: ?*Node, prev: ?*Node, metro: *Metro, id: u8 };
    head: ?*Node,
    tail: ?*Node,
    size: u8,
    fn search(self: *Metro_List, id: u8) ?*Node {
        var node = self.head;
        while (node) |n| {
            if (n.id == id) return n;
            node = n.next;
        }
        return null;
    }
    pub fn add_or_find(self: *Metro_List, id: u8) !*Metro {
        if (self.search(id)) |n| return n.metro;
        var metro = try allocator.create(Metro);
        metro.* = Metro{
            .count = -1,
            .seconds = 1.0,
            .stage = 0,
            .stage_lock = .{},
            .status_lock = .{},
            .thread = null,
            .delta = undefined,
            .status = Status.Stopped,
            .id = id,
            // blank slate
        };
        var new_node = try allocator.create(Node);
        new_node.* = Node{ .next = null, .prev = null, .metro = metro, .id = id };
        var node = self.head;
        while (node != null and node.?.next != null) : (node = node.?.next) {}
        if (node == null) {
            std.debug.assert(self.size == 0);
            self.head = new_node;
        } else {
            node.?.next = new_node;
            new_node.prev = node;
        }
        self.tail = new_node;
        self.size += 1;
        return metro;
    }
    pub fn remove_and_free(self: *Metro_List, id: u8) !void {
        const nd = self.search(id);
        if (nd) |node| {
            defer allocator.destroy(node);
            var prev = node.prev;
            var next = node.next;
            if (node == self.head) self.head = next;
            if (node == self.tail) self.tail = prev;
            if (prev) |p| p.next = next;
            if (next) |n| n.prev = prev;
            self.size -= 1;
            try node.metro.stop();
            allocator.destroy(node.metro);
        }
    }
};

const Metro = struct {
    // metro struct
    status: Status,
    seconds: f64,
    id: u8,
    count: i64,
    stage: i64,
    delta: u64,
    thread: ?std.Thread,
    stage_lock: std.Thread.Mutex,
    status_lock: std.Thread.Mutex,
    fn stop(self: *Metro) !void {
        self.status_lock.lock();
        self.status = Status.Stopped;
        self.status_lock.unlock();
        if (self.thread) |pid| {
            pid.join();
        }
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

pub fn stop(idx: u8) !void {
    if (idx < 0 or idx >= max_num_metros) {
        logger.warn("invalid index, max count of metros is {d}", .{max_num_metros});
        return;
    }
    try metros.remove_and_free(idx);
}

pub fn start(idx: u8, seconds: f64, count: i64, stage: i64) !void {
    if (idx < 0 or idx >= max_num_metros) {
        logger.warn("invalid index; not added. max count of metros is {d}", .{max_num_metros});
        return;
    }
    var metro = try metros.add_or_find(idx);
    metro.status_lock.lock();
    if (metro.status == Status.Running) {
        try metro.stop();
    }
    metro.status_lock.unlock();
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    const delta = @intFromFloat(u64, metro.seconds * std.time.ns_per_s);
    metro.reset(stage);
    try metro.init(delta, count);
}

pub fn set_period(idx: u8, seconds: f64) !void {
    if (idx < 0 or idx >= max_num_metros) return;
    const metro = try metros.add_or_find(idx);
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    metro.delta = @intFromFloat(u64, metro.seconds * std.time.ns_per_s);
}

const max_num_metros = 36;
var metros = Metro_List{ .head = null, .tail = null, .size = 0 };
var allocator: std.mem.Allocator = undefined;

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    allocator = alloc_pointer;
}

pub fn deinit() void {
    var i: u8 = 0;
    while (i < max_num_metros) : (i += 1) {
        try metros.remove_and_free(i);
    }
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
