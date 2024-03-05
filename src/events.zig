const std = @import("std");
const Seamstress = @import("seamstress.zig");
const Spindle = @import("spindle.zig");
const Error = Seamstress.Error;

const Queue = @This();
const logger = std.log.scoped(.events);

// we store a reference to the Lua VM so that we can properly handle events
parent: *Spindle,
// the event queue
queue: std.fifo.LinearFifo(Event, .Dynamic),
cond: std.Thread.Condition = .{},
mtx: std.Thread.Mutex = .{},
quit: bool = false,

pub const Command = struct {
    ctx: *anyopaque,
    // where to read from
    reader: std.io.AnyReader,
    // how much to read
    len: usize,
    f: *const Handler,

    pub const Handler = fn (*anyopaque, std.io.AnyReader, usize) void;
};

pub const Event = union(enum) {
    panic: Error,
    quit: void,
    command: Command,
};

// posts an event to the queue and wakes up the thread
pub fn post(self: *Queue, ev: Event) void {
    self.queue.writeItem(ev) catch {
        switch (ev) {
            // not really anything we can do in this situation
            .panic => @panic("out of memory while attempting to panic!"),
            else => logger.err("out of memory! unable to post event of type {s}", .{@tagName(ev)}),
        }
        return;
    };
    self.cond.signal();
}

// frees memory in the queue
pub fn close(self: *Queue) void {
    // necessary so the event loop exits
    self.quit = true;
    self.queue.deinit();
}

// initializes the event queue
pub fn init(parent: *Spindle, allocator: std.mem.Allocator) Queue {
    return .{
        .queue = std.fifo.LinearFifo(Event, .Dynamic).init(allocator),
        .parent = parent,
    };
}

// the main event loop; the main thread blocks here until exiting
pub fn loop(self: *Queue) void {
    while (!self.quit) {
        // we try to handle all available events at once
        while (self.queue.readItem()) |ev| {
            // unless one of them tells us we should quit
            if (self.quit) break;
            self.handle(&ev);
        }
        if (self.quit) break;
        self.mtx.lock();
        defer self.mtx.unlock();
        // waits for new events
        self.cond.wait(&self.mtx);
    }
}

// drains the event queue
pub fn processAll(self: *Queue) void {
    while (self.queue.readItem()) |ev| {
        self.handle(&ev);
    }
}
// passing the event by reference to avoid a copy; is this useful?
fn handle(self: *Queue, ev: *const Event) void {
    switch (ev.*) {
        .panic => |err| {
            // shenanigans
            const seamstress = @fieldParentPtr(Seamstress, "vm", self.parent);
            seamstress.panic(err);
        },
        .quit => {
            // shenanigans
            const seamstress = @fieldParentPtr(Seamstress, "vm", self.parent);
            seamstress.deinit();
        },
        .command => |c| {
            c.f(c.ctx, c.reader, c.len);
        },
    }
}
