/// the event loop, based on libxev
const Wheel = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
quit_flag: bool = false,
awake: xev.Async,
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
pub fn run(self: *Wheel) !void {
    defer {
        self.loop.deinit();
    }
    _ = self.timer.lap();
    const seamstress: *Seamstress = @fieldParentPtr("loop", self);
    var c1: xev.Completion = .{};
    const flush_timer = try xev.Timer.init();
    flush_timer.run(&self.loop, &c1, 5000, Seamstress, seamstress, flush);

    var c2: xev.Completion = .{};
    self.awake.wait(&self.loop, &c2, Wheel, self, callback);

    var c3: xev.Completion = .{};
    const timer = try xev.Timer.init();
    timer.run(&self.loop, &c3, 0, Lua, seamstress.l, callInit);

    try self.loop.run(.until_done);
}

fn flush(s: ?*Seamstress, l: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch |err| panic("timer error: {s}", .{@errorName(err)});
    const seamstress = s.?;
    if (seamstress.logger) |log| log.flush() catch |err| panic("error writing logs! {s}", .{@errorName(err)});
    const timer = xev.Timer.init() catch unreachable;
    timer.run(l, c, 5000, Seamstress, seamstress, flush);
    return .disarm;
}

// just wakes up the event loop
fn callback(_: ?*Wheel, l: *xev.Loop, _: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    _ = r catch unreachable;
    l.stop();
    return .disarm;
}

/// pushes a quit event onto the event loop
pub fn quit(self: *Wheel) void {
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
