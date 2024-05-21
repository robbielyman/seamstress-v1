/// metros module

// returns the module interface
pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

fn init(m: *Module, vm: *Spindle, _: *Wheel, allocator: std.mem.Allocator) Error!void {
    const self = try allocator.create(Metros);
    self.* = .{
        .lua = vm.l,
    };
    for (&self.metros, 0..) |*metro, i| {
        metro.* = .{
            .timer = xev.Timer.init() catch return error.LaunchFailed,
            .parent = self,
            .id = @intCast(i),
        };
    }
    m.self = self;
    lu.registerSeamstress(vm.l, "metro_start", metroStart, self);
    lu.registerSeamstress(vm.l, "metro_stop", metroStop, self);
    lu.registerSeamstress(vm.l, "metro_set_time", metroSetTime, self);
}

fn deinit(m: *const Module, _: *Lua, allocator: std.mem.Allocator, cleanup: Cleanup) void {
    if (cleanup != .full) return;
    const self: *Metros = @ptrCast(@alignCast(m.self orelse return));
    for (&self.metros) |*metro| {
        metro.timer.deinit();
    }
    allocator.destroy(self);
}

fn launch(_: *const Module, _: *Lua, _: *Wheel) Error!void {}

const Metros = struct {
    const max_num_metros = 64;
    metros: [max_num_metros]Metro = undefined,
    lua: *Lua,

    const Metro = struct {
        timer: xev.Timer,
        parent: *Metros,
        run: xev.Completion = .{},
        cancel: xev.Completion = .{},
        id: u8,
        stage: i64 = 0,
        count: i64 = -1,
        delta: u64 = std.time.ns_per_s,
        running: bool = false,
        seconds: f64 = 1,

        fn init(self: *Metro, delta: u64, count: i64) void {
            const wheel = lu.getWheel(self.parent.lua);
            self.delta = delta;
            self.count = count;
            self.timer.run(&wheel.loop, &self.run, @divTrunc(self.delta, std.time.ns_per_ms), Metro, self, runCallback);
        }

        fn runCallback(self: ?*Metro, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
            _ = r catch |err| {
                if (err == error.Canceled) return .disarm;
                logger.err("error running metro: {s}!", .{@errorName(err)});
            };
            const m = self orelse return .disarm;
            m.stage += 1;
            if (m.count > 0 and m.stage >= m.count) m.running = false;
            m.bang();
            if (m.running and c.state() == .dead)
                m.timer.run(loop, c, @divTrunc(m.delta, std.time.ns_per_ms), Metro, m, runCallback);
            return .disarm;
        }

        fn stop(self: *Metro) void {
            const wheel = lu.getWheel(self.parent.lua);
            self.timer.cancel(&wheel.loop, &self.run, &self.cancel, Metro, self, cancel);
        }

        fn cancel(self: ?*Metro, _: *xev.Loop, _: *xev.Completion, r: xev.Timer.CancelError!void) xev.CallbackAction {
            _ = r catch {
                logger.err("error canceling metro!", .{});
            };
            const m = self orelse return .disarm;
            m.running = false;
            return .disarm;
        }

        fn bang(self: *Metro) void {
            const l = self.parent.lua;
            lu.getMethod(l, "metro", "event");
            l.pushInteger(self.id + 1);
            l.pushInteger(self.stage);
            lu.doCall(l, 2, 0);
        }
    };
};

/// sets repetition time for a metro.
// users can use the `time` field on a metro instead.
// @tparam integer idx metro id (1-64)
// @tparam number period new period in seconds
// @function metro_set_time
fn metroSetTime(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const metros = lu.closureGetContext(l, Metros) orelse return 0;
    const idx = l.checkInteger(1);
    l.argCheck(1 <= idx and idx <= 64, 1, "invalid index; max count of metros is 64");
    const seconds = l.checkNumber(2);
    const metro = &metros.metros[@intCast(idx - 1)];
    if (seconds > 0.0) metro.seconds = seconds;
    const delta: u64 = @intFromFloat(metro.seconds * std.time.ns_per_s);
    metro.delta = delta;
    return 0;
}

/// stops a metro.
// users should use `metro:stop` instead
// @tparam integer idx metro id (1-64)
// @see metro:stop
// @function metro_stop
fn metroStop(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const metros = lu.closureGetContext(l, Metros) orelse return 0;
    const idx = l.checkInteger(1);
    l.argCheck(1 <= idx and idx <= 64, 1, "invalid index; max count of metros is 64");
    // stop it
    metros.metros[@intCast(idx - 1)].stop();
    // nothing to return
    return 0;
}

/// starts a new metro.
// users should use `metro:start` instead
// @tparam integer idx metro id (1-64)
// @tparam number seconds time at which to repeat
// @tparam integer count stage at which to stop
// @tparam integer stage stage at which to start
// @see metro:start
// @function metro_start
fn metroStart(l: *Lua) i32 {
    lu.checkNumArgs(l, 4);
    const metros = lu.closureGetContext(l, Metros) orelse return 0;
    const idx = l.checkInteger(1);
    const seconds = l.checkNumber(2);
    const count: i64 = count: {
        if (l.isInteger(3)) break :count l.checkInteger(3);
        break :count @intFromFloat(l.checkNumber(3));
    };
    const stage: i64 = stage: {
        if (l.isInteger(4)) break :stage l.checkInteger(4) - 1;
        break :stage @intFromFloat(l.checkNumber(4) - 1);
    };
    l.argCheck(1 <= idx and idx <= 64, 1, "invalid index; max count of metros is 64");
    const metro = &metros.metros[@intCast(idx - 1)];
    // stop the metro if it was running
    metro.stop();
    if (seconds > 0.0) metro.seconds = seconds;
    const delta: u64 = @intFromFloat(metro.seconds * std.time.ns_per_s);
    // set the stage
    metro.stage = if (stage > 0) stage else 0;
    // start the metro
    metro.init(delta, count);
    // nothing to return
    return 0;
}

const logger = std.log.scoped(.metros);

const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Wheel = @import("wheel.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const xev = @import("xev");
const lu = @import("lua_util.zig");
