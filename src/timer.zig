/// Lua-owned libxev timers.
pub fn registerSeamstress(l: *Lua) !void {
    try l.newMetatable("seamstress.Timer");
    _ = l.pushStringZ("__index");
    l.pushFunction(ziglua.wrap(index));
    l.setTable(-3);
    _ = l.pushStringZ("__newindex");
    l.pushFunction(ziglua.wrap(newindex));
    l.setTable(-3);
    _ = l.pushStringZ("__gc");
    l.pushFunction(ziglua.wrap(gc));
    l.setTable(-3);
    l.pop(1);
    lu.getSeamstress(l);
    _ = l.pushStringZ("Timer");
    l.pushFunction(ziglua.wrap(new));
    l.setTable(-3);
    l.pop(1);
}

fn new(l: *Lua) i32 {
    const delta = l.optNumber(2) orelse 1;
    l.argCheck(delta >= std.math.floatEps(f64), 2, "delta must be positive");
    const stage_end = l.optNumber(3) orelse -1;
    const stage = l.optNumber(4) orelse 1;
    const t = l.newUserdata(xev.Timer, 8);
    _ = l.getMetatableRegistry("seamstress.Timer");
    l.setMetatable(-2);
    lu.checkCallable(l, 1);
    t.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new timer! %s", .{@errorName(err)});
    l.setUserValue(-2, 1) catch unreachable; // function: 1
    l.newTable();
    l.setUserValue(-2, 8) catch unreachable; // data: 8
    l.pushNumber(delta);
    l.setUserValue(-2, 2) catch unreachable; // delta (in seconds): 2
    l.pushNumber(stage_end);
    l.setUserValue(-2, 3) catch unreachable; // stage_end: 3
    l.pushNumber(stage);
    l.setUserValue(-2, 4) catch unreachable; // stage: 4
    const t5 = l.typeOf(5);
    const running = t5 == .none or t5 == .nil or l.toBoolean(5);
    l.pushBoolean(running);
    l.setUserValue(-2, 5) catch unreachable; // running: 5
    const wheel = lu.getWheel(l);
    const now = wheel.timer.read();
    l.pushInteger(@bitCast(now));
    l.setUserValue(-2, 6) catch unreachable; // current time (in ns): 6
    const c = l.newUserdata(xev.Completion, 0);
    c.* = .{};
    l.setUserValue(-2, 7) catch unreachable; // completion: 7
    if (!running) return 1;
    l.pushValue(-1);
    const next: u64 = @intFromFloat(delta * std.time.ms_per_s);
    const handle = l.ref(ziglua.registry_index) catch l.raiseErrorStr("unable to register timer!", .{});
    t.run(&wheel.loop, c, next, anyopaque, @ptrFromInt(@as(u32, @bitCast(handle))), bang);
    return 1;
}

fn bang(ud: ?*anyopaque, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const handle: i32 = @bitCast(@as(u32, @intCast(@intFromPtr(ud))));
    _ = r catch |err| panic("timer error: {s}", .{@errorName(err)});
    const l = Wheel.getLua(loop);
    const top = l.getTop();
    defer std.debug.assert(top == l.getTop());
    _ = l.rawGetIndex(ziglua.registry_index, handle); // push Timer userdata
    const self = l.toUserdata(xev.Timer, -1) catch unreachable;
    var rearm = true;
    defer if (!rearm) l.unref(ziglua.registry_index, handle); // discard timer when not on event loop
    _ = l.getUserValue(-1, 3) catch unreachable; // stage_end: 3
    const stage_end = l.toNumber(-1) catch unreachable;
    _ = l.getUserValue(-2, 4) catch unreachable; // stage: 4
    const stage = l.toNumber(-1) catch unreachable;
    l.pop(2);
    if (stage_end >= std.math.floatEps(f64) and stage - 1 >= stage_end) {
        rearm = false;
        l.pushBoolean(false);
        l.setUserValue(-2, 5) catch unreachable; // running: 5
        l.pop(1);
        return .disarm;
    }
    _ = l.getUserValue(-1, 5) catch unreachable; // running: 5
    const running = l.toBoolean(-1);
    l.pop(1);
    if (!running) {
        rearm = false;
        l.pop(1);
        return .disarm;
    }

    const wheel: *Wheel = @fieldParentPtr("loop", loop);
    const now = wheel.timer.read(); // get current time
    _ = l.getUserValue(-1, 6) catch unreachable; // current time (in ns): 6
    const then: u64 = @bitCast(l.toInteger(-1) catch unreachable);
    _ = l.getUserValue(-2, 2) catch unreachable; // delta: 2
    const old_delta = l.toNumber(-1) catch unreachable;
    const old_delta_ms: u64 = @intFromFloat(old_delta * std.time.ms_per_s);
    l.pop(2);

    l.pushInteger(@bitCast(now));
    l.setUserValue(-2, 6) catch unreachable; // current time (in ns): 6
    const dt: f64 = @as(f64, @floatFromInt(now - then)) / std.time.ns_per_s;
    _ = l.getUserValue(-1, 1) catch unreachable; // function
    l.pushValue(-2); // self
    l.pushNumber(dt); // dt
    l.call(2, 0); // call function

    _ = l.getUserValue(-1, 4) catch unreachable; // stage: 4
    const new_stage = (l.toNumber(-1) catch unreachable) + 1;
    l.pop(1);
    l.pushNumber(new_stage); // stage = stage + 1
    l.setUserValue(-2, 4) catch unreachable;
    _ = l.getUserValue(-1, 5) catch unreachable; // running: 5
    const new_running = l.toBoolean(-1);
    l.pop(1);
    if (!new_running) {
        rearm = false;
        l.pop(1);
        return .disarm;
    }
    _ = l.getUserValue(-1, 2) catch unreachable; // delta: 2
    const delta = l.toNumber(-1) catch unreachable;
    const delta_ms: u64 = @intFromFloat(delta * std.time.ms_per_s);
    const next = (@divFloor(then, std.time.ns_per_ms) + old_delta_ms + delta_ms) -| @divFloor(now, std.time.ns_per_ms); // keep time with our intentions
    l.pop(2);
    self.run(loop, c, next, anyopaque, ud, bang);
    return .disarm;
}

fn gc(l: *Lua) i32 {
    const timer = l.checkUserdata(xev.Timer, 1, "seamstress.Timer");
    timer.deinit();
    return 0;
}

fn index(l: *Lua) i32 {
    const t = l.typeOf(2);
    if (t == .string) {
        const str = l.toString(2) catch unreachable;
        inline for (indices) |tuple| {
            if (std.mem.eql(u8, str, tuple[0])) {
                _ = l.getUserValue(1, tuple[1]) catch unreachable;
                return 1;
            }
        }
    }
    _ = l.getUserValue(1, 8) catch unreachable;
    _ = l.pushValue(2);
    _ = l.getTable(-2);
    l.remove(-2);
    return 1;
}

fn newindex(l: *Lua) i32 {
    const t = l.typeOf(2);
    if (t == .string) {
        const key = l.toString(2) catch unreachable;
        if (std.mem.eql(u8, "delta", key)) {
            const delta = l.checkNumber(3);
            l.argCheck(delta >= std.math.floatEps(f64), 3, "delta must be positive");
            l.pushNumber(delta);
            l.setUserValue(1, 2) catch unreachable;
            return 0;
        }
        if (std.mem.eql(u8, "running", key)) {
            const running = l.toBoolean(3);
            _ = l.getUserValue(1, 5) catch unreachable;
            const old_running = l.toBoolean(-1);
            l.pop(1);
            l.pushBoolean(running);
            l.setUserValue(1, 5) catch unreachable;
            if (!old_running and running) {
                const wheel = lu.getWheel(l);
                const now = wheel.timer.read();
                l.pushInteger(@bitCast(now));
                l.setUserValue(1, 6) catch unreachable; // current time (in ns): 6
                const timer = l.checkUserdata(xev.Timer, 1, "seamstress.Timer");
                _ = l.getUserValue(1, 7) catch unreachable; // completion: 7
                const c = l.toUserdata(xev.Completion, -1) catch unreachable;
                _ = l.getUserValue(1, 2) catch unreachable; // delta: 2
                const delta = l.toNumber(-1) catch unreachable;
                l.pop(2);
                l.pushInteger(1);
                l.setUserValue(1, 4) catch unreachable; // stage: 4
                const next: u64 = @intFromFloat(delta * std.time.ms_per_s);
                l.pushValue(1);
                const handle = l.ref(ziglua.registry_index) catch l.raiseErrorStr("unable to register timer!", .{});
                timer.run(&wheel.loop, c, next, anyopaque, @ptrFromInt(@as(u32, @bitCast(handle))), bang);
            }
            return 0;
        }
        if (std.mem.eql(u8, "stage", key)) {
            _ = l.checkNumber(3);
            l.pushValue(3);
            l.setUserValue(1, 4) catch unreachable; // stage: 4
            return 0;
        }
        if (std.mem.eql(u8, "stage_end", key)) {
            _ = l.checkNumber(3);
            l.pushValue(3);
            l.setUserValue(1, 3) catch unreachable; // stage end: 3
            return 0;
        }
        if (std.mem.eql(u8, "action", key)) {
            lu.checkCallable(l, 3);
            l.setUserValue(1, 1) catch unreachable; // action: 1
            return 0;
        }
    }
    _ = l.getUserValue(1, 8) catch unreachable; // data: 8
    l.pushValue(2);
    l.pushValue(3);
    l.setTable(-3);
    return 0;
}

const indices: [5]struct { []const u8, i32 } = .{
    .{ "delta", 2 },
    .{ "running", 5 },
    .{ "stage", 4 },
    .{ "stage_end", 3 },
    .{ "action", 1 },
};

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const xev = @import("xev");
const lu = @import("lua_util.zig");
const std = @import("std");
const panic = std.debug.panic;
const Wheel = @import("wheel.zig");
const logger = std.log.scoped(.timer);
