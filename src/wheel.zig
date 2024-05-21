const Wheel = @This();
const logger = std.log.scoped(.wheel);

err: ?Error = null,
panic_ev: xev.Completion = .{},
quit_ev: xev.Completion = .{},
thread_pool: xev.ThreadPool,
timer: xev.Timer,
loop: xev.Loop,
quit: bool = false,

pub fn run(self: *Wheel) Error!void {
    self.loop.run(.once) catch return error.LoopFailed;
}

pub fn init(self: *Wheel) Error!void {
    self.* = .{
        .timer = xev.Timer.init() catch return error.LaunchFailed,
        .thread_pool = xev.ThreadPool.init(.{
            .max_threads = 8,
        }),
        .loop = xev.Loop.init(.{
            .thread_pool = &self.thread_pool,
        }) catch return error.LaunchFailed,
    };
}

pub fn processAll(self: *Wheel) Error!void {
    self.loop.run(.no_wait) catch return error.LoopFailed;
}

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Lua = @import("ziglua").Lua;
const xev = @import("xev");
