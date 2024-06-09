/// the event loop, based on libxev
const Wheel = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
quit_flag: bool = false,
quit_ev: xev.Async,
render: ?struct {
    ctx: *anyopaque,
    render_fn: *const fn (*anyopaque, u64) void,
} = null,
timer: std.time.Timer,
kind: Seamstress.Cleanup = switch (builtin.mode) {
    .Debug, .ReleaseSafe => .full,
    .ReleaseFast, .ReleaseSmall => .clean,
},

pub fn init(self: *Wheel) void {
    self.* = .{
        .pool = xev.ThreadPool.init(.{}),
        .loop = xev.Loop.init(.{
            .thread_pool = &self.pool,
        }) catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
        .timer = std.time.Timer.start() catch unreachable,
        .quit_ev = xev.Async.init() catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
    };
}

/// the main event loop; blocks until self.quit becomes true
pub fn run(self: *Wheel) void {
    defer {
        self.pool.shutdown();
        self.pool.deinit();
        self.loop.deinit();
    }
    var c1: xev.Completion = .{};
    var render_timer = xev.Timer.init() catch unreachable;
    render_timer.run(&self.loop, &c1, 17, xev.Timer, &render_timer, render);
    _ = self.timer.lap();
    var c2: xev.Completion = .{};
    self.quit_ev.wait(&self.loop, &c2, Wheel, self, callback);
    var c3: xev.Completion = .{};
    const timer = xev.Timer.init() catch unreachable;
    const seamstress: *Seamstress = @fieldParentPtr("loop", self);
    timer.run(&self.loop, &c3, 0, Lua, seamstress.l, callInit);
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

fn render(w: ?*xev.Timer, l: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const render_timer = w.?;
    _ = r catch return .disarm;
    render_timer.run(l, c, 17, xev.Timer, render_timer, render);
    return .disarm;
}

pub fn quit(self: *Wheel) void {
    self.quit_flag = true;
    self.quit_ev.notify() catch |err| panic("error while quitting! {s}", .{@errorName(err)});
}

fn callInit(lua: ?*Lua, _: *xev.Loop, _: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const l = lua.?;
    _ = r catch |err| panic("timer error: {s}", .{@errorName(err)});
    lu.getSeamstress(l);
    _ = l.getField(-1, "_start");
    l.remove(-2);
    lu.doCall(l, 0, 0);
    return .disarm;
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const xev = @import("xev");
const std = @import("std");
const Lua = @import("ziglua").Lua;
const lu = @import("lua_util.zig");
const panic = std.debug.panic;
const builtin = @import("builtin");
