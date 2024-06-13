/// the event loop, based on libxev
const Wheel = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
quit_flag: bool = false,
awake: xev.Async,
render: ?struct {
    ctx: *anyopaque,
    render_fn: *const fn (*anyopaque, u64) void,
} = null,
timer: std.time.Timer,
kind: Seamstress.Cleanup = switch (builtin.mode) {
    .Debug, .ReleaseSafe => .full,
    .ReleaseFast, .ReleaseSmall => .clean,
},

// creates the event loop and the quit signaler
pub fn init(self: *Wheel) void {
    self.* = .{
        .pool = xev.ThreadPool.init(.{}),
        .loop = xev.Loop.init(.{
            .thread_pool = &self.pool,
        }) catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
        .timer = std.time.Timer.start() catch unreachable,
        .awake = xev.Async.init() catch |err| panic("error initializing event loop! {s}", .{@errorName(err)}),
    };
}

/// the main event loop; blocks until self.quit becomes true
pub fn run(self: *Wheel) void {
    defer {
        self.loop.deinit();
    }
    var c1: xev.Completion = .{};
    var render_timer = xev.Timer.init() catch unreachable;
    render_timer.run(&self.loop, &c1, 17, xev.Timer, &render_timer, render);
    _ = self.timer.lap();
    var c2: xev.Completion = .{};
    self.awake.wait(&self.loop, &c2, Wheel, self, callback);
    var c3: xev.Completion = .{};
    const timer = xev.Timer.init() catch unreachable;
    const seamstress: *Seamstress = @fieldParentPtr("loop", self);
    timer.run(&self.loop, &c3, 0, Lua, seamstress.l, callInit);
    while (!self.quit_flag) {
        self.loop.run(.once) catch |err| panic("error running event loop! {s}", .{@errorName(err)});
        const lap_time = self.timer.lap();
        if (self.render) |r| r.render_fn(r.ctx, lap_time) else std.log.debug("whoopsie", .{});
    }
}

// just wakes up the event loop
fn callback(w: ?*Wheel, l: *xev.Loop, c: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    const wheel = w.?;
    _ = r catch unreachable;
    wheel.awake.wait(l, c, Wheel, w, callback);
    return .disarm;
}

// just wakes up the event loop
fn render(w: ?*xev.Timer, l: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const render_timer = w.?;
    _ = r catch return .disarm;
    render_timer.run(l, c, 17, xev.Timer, render_timer, render);
    return .disarm;
}

pub fn awaken(self: *Wheel) void {
    self.awake.notify() catch |err| panic("error while waking! {s}", .{@errorName(err)});
}

// sets the quit flag and attempts to wake up the event loop
pub fn quit(self: *Wheel) void {
    self.quit_flag = true;
    self.awake.notify() catch |err| panic("error while quitting! {s}", .{@errorName(err)});
}

// we run this through the event loop in order to capture any events that have already arrived before calling init
fn callInit(lua: ?*Lua, _: *xev.Loop, _: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const l = lua.?;
    _ = r catch |err| panic("timer error: {s}", .{@errorName(err)});
    lu.getSeamstress(l);
    _ = l.getField(-1, "_start");
    l.remove(-2);
    l.call(0, 0);
    return .disarm;
}

// grabs a handle to the Lua VM
// pub for use from within event callbacks
pub fn getLua(l: *xev.Loop) *Lua {
    const wheel: *Wheel = @fieldParentPtr("loop", l);
    const seamstress: *Seamstress = @fieldParentPtr("loop", wheel);
    return seamstress.l;
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const xev = @import("xev");
const std = @import("std");
const Lua = @import("ziglua").Lua;
const lu = @import("lua_util.zig");
const panic = std.debug.panic;
const builtin = @import("builtin");
