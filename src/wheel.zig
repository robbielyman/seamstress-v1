/// the event loop, based on libxev
const Wheel = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
quit_flag: bool = false,
render: ?struct {
    ctx: *anyopaque,
    render_fn: *const fn (*anyopaque) void,
} = null,

pub fn init(self: *Wheel) void {
    self.* = .{
        .pool = xev.ThreadPool.init(.{}),
        .loop = xev.Loop.init(.{
            .thread_pool = &self.pool,
        }) catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
    };
}

/// drains the event queue
pub fn processAll(self: *Wheel) void {
    self.loop.run(.no_wait) catch |err| panic("error running event loop! {s}", .{@errorName(err)});
}

/// the main event loop; blocks until self.quit becomes true
pub fn run(self: *Wheel) void {
    defer {
        self.pool.shutdown();
        self.pool.deinit();
        self.loop.deinit();
    }
    while (!self.quit_flag) {
        self.loop.run(.once) catch |err| panic("error running event loop! {s}", .{@errorName(err)});
        if (self.render) |r| r.render_fn(r.ctx);
    }
}

pub fn quit(self: *Wheel) void {
    self.quit_flag = true;
    self.loop.stop();
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const xev = @import("libxev");
const std = @import("std");
const panic = std.debug.panic;
