/// the event loop, based on libxev
const Wheel = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
quit_flag: bool = false,
quit_ev: xev.Async,
quit_c: xev.Completion = .{},
render: ?struct {
    ctx: *anyopaque,
    render_fn: *const fn (*anyopaque, u64) void,
} = null,
timer: std.time.Timer,
render_timer: xev.Timer,
render_ev: xev.Completion = .{},

pub fn init(self: *Wheel) void {
    self.* = .{
        .pool = xev.ThreadPool.init(.{}),
        .loop = xev.Loop.init(.{
            .thread_pool = &self.pool,
        }) catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
        .timer = std.time.Timer.start() catch unreachable,
        .render_timer = xev.Timer.init() catch unreachable,
        .quit_ev = xev.Async.init() catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
    };
}

/// drains the event queue
pub fn processAll(self: *Wheel) void {
    self.loop.run(.no_wait) catch |err| panic("error running event loop! {s}", .{@errorName(err)});
}

/// the main event loop; blocks until self.quit becomes true
pub fn run(self: *Wheel) void {
    self.render_timer.run(&self.loop, &self.render_ev, 17, Wheel, self, render);
    _ = self.timer.lap();
    defer {
        self.pool.shutdown();
        self.pool.deinit();
        self.loop.deinit();
    }
    self.quit_ev.wait(&self.loop, &self.quit_c, Wheel, self, callback);
    while (!self.quit_flag) {
        self.loop.run(.once) catch |err| panic("error running event loop! {s}", .{@errorName(err)});
        const lap_time = self.timer.lap();
        if (self.render) |r| r.render_fn(r.ctx, lap_time);
    }
}

fn callback(w: ?*Wheel, l: *xev.Loop, c: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    const wheel = w.?;
    _ = r catch unreachable;
    wheel.quit_ev.wait(l, c, Wheel, w, callback);
    return .disarm;
}

fn render(w: ?*Wheel, l: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const wheel = w.?;
    _ = r catch return .disarm;
    wheel.render_timer.run(l, c, 17, Wheel, wheel, render);
    return .disarm;
}

pub fn quit(self: *Wheel) void {
    self.quit_flag = true;
    self.quit_ev.notify() catch |err| panic("error while quitting! {s}", .{@errorName(err)});
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const xev = @import("xev");
const std = @import("std");
const panic = std.debug.panic;
