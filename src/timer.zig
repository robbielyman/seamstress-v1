/// seamstress.Timer provides the Timer userdata type,
/// which (usually repeatedly) executes a Lua function after waiting on the event loop
/// this function loads the library, returning a function which creates a new Timer
pub fn register(l: *Lua) i32 {
    blk: {
        l.newMetatable("seamstress.Timer") catch break :blk; // new metatable
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(__index) },
            .{ .name = "__newindex", .func = ziglua.wrap(__newindex) },
            .{ .name = "__cancel", .func = ziglua.wrap(__cancel) },
        };
        l.setFuncs(funcs, 0);
    }
    l.pop(1);
    l.pushFunction(ziglua.wrap(new));
    return 1;
}

fn __cancel(l: *Lua) i32 {
    const timer = l.checkUserdata(Timer, 1, "seamstress.Timer");
    l.pushValue(1);
    const handle = l.ref(ziglua.registry_index) catch
        std.debug.panic("unable to register Timer!", .{});
    timer.c_c = .{
        .op = .{ .cancel = .{ .c = &timer.c } },
        .userdata = ptrFromHandle(handle),
        .callback = struct {
            fn callback(
                userdata: ?*anyopaque,
                loop: *xev.Loop,
                _: *xev.Completion,
                result: xev.Result,
            ) xev.CallbackAction {
                const lua = lu.getLua(loop);
                const top = if (builtin.mode == .Debug) lua.getTop();
                defer if (builtin.mode == .Debug) std.debug.assert(top == lua.getTop()); // stack must be unchanged
                lua.unref(ziglua.registry_index, handleFromPtr(userdata)); // release the reference
                _ = result.cancel catch |err| {
                    _ = lua.pushFString("unable to cancel: %s", .{@errorName(err).ptr});
                    lu.reportError(lua);
                };
                return .disarm;
            }
        }.callback,
    };
    const seamstress = lu.getSeamstress(l);
    seamstress.loop.add(&timer.c_c);
    return 0;
}

/// runs the timer's action and reschedules depending on Timer's values
fn bang(ud: ?*anyopaque, loop: *xev.Loop, c: *xev.Completion, r: xev.Result) xev.CallbackAction {
    const l = lu.getLua(loop);
    const top = if (builtin.mode == .Debug) l.getTop();
    defer if (builtin.mode == .Debug) std.debug.assert(top == l.getTop());
    const handle = handleFromPtr(ud);
    _ = r.timer catch |err| {
        l.unref(ziglua.registry_index, handle);
        if (err == error.Canceled) return .disarm;
        _ = l.pushFString("timer error! %s", .{@errorName(err).ptr});
        lu.reportError(l);
        return .disarm;
    };
    _ = l.rawGetIndex(ziglua.registry_index, handle); // push Timer userdata
    var rearm = true;
    defer if (!rearm) l.unref(ziglua.registry_index, handle); // discard timer when not on event loop
    _ = l.getUserValue(-1, @intFromEnum(Indices.stage_end)) catch unreachable;
    const stage_end = l.toNumber(-1) catch unreachable;
    l.pop(1);
    _ = l.getUserValue(-1, @intFromEnum(Indices.stage)) catch unreachable;
    const stage = l.toNumber(-1) catch unreachable;
    l.pop(1);
    if (stage_end >= std.math.floatEps(f64) and stage - 1 >= stage_end) {
        rearm = false;
        l.pushBoolean(false); // Timer.running = false
        l.setUserValue(-2, @intFromEnum(Indices.running)) catch unreachable;
        l.pop(1);
        return .disarm;
    }
    _ = l.getUserValue(-1, @intFromEnum(Indices.running)) catch unreachable;
    const running = l.toBoolean(-1);
    l.pop(1);
    if (!running) {
        rearm = false;
        l.pop(1);
        return .disarm;
    }
    const now = loop.now(); // current time
    _ = l.getUserValue(-1, @intFromEnum(Indices.now)) catch unreachable;
    const then = l.toInteger(-1) catch unreachable;
    l.pop(1);

    _ = l.getUserValue(-1, @intFromEnum(Indices.delta)) catch unreachable;
    const old_delta = l.toNumber(-1) catch unreachable;
    l.pop(1);
    const old_delta_ms: u64 = @intFromFloat(old_delta * std.time.ms_per_s);
    l.pushInteger(now);
    l.setUserValue(-2, @intFromEnum(Indices.now)) catch unreachable; // update now
    const dt: f64 = @as(f64, @floatFromInt(now - then)) / std.time.ns_per_s;
    _ = l.getUserValue(-1, @intFromEnum(Indices.action)) catch unreachable; // f
    l.pushValue(-2); // self
    l.pushNumber(dt);
    lu.doCall(l, 2, 0) catch lu.reportError(l); // f(self, dt)

    // now: are we running again?
    _ = l.getUserValue(-1, @intFromEnum(Indices.stage)) catch unreachable;
    const new_stage = (l.toNumber(-1) catch unreachable) + 1;
    l.pop(1);
    l.pushNumber(new_stage);
    l.setUserValue(-2, @intFromEnum(Indices.stage)) catch unreachable;
    // no need to check against the stage; we'll get that on the flip side
    _ = l.getUserValue(-1, @intFromEnum(Indices.running)) catch unreachable;
    const new_running = l.toBoolean(-1);
    l.pop(1);
    if (!new_running) {
        rearm = false;
        l.pop(1);
        return .disarm;
    }
    _ = l.getUserValue(-1, @intFromEnum(Indices.delta)) catch unreachable;
    const delta = l.toNumber(-1) catch unreachable;
    const delta_ms: u64 = @intFromFloat(delta * std.time.ms_per_s);
    const u_then: u64 = @intCast(@divFloor(then, std.time.ns_per_ms));
    const u_now: u64 = @intCast(@divFloor(now, std.time.ns_per_ms));
    const next = (u_then + old_delta_ms + delta_ms) -| u_now; // keep time with our intentions
    l.pop(2);
    loop.timer(c, next, ud, bang);
    return .disarm;
}

const Timer = @This();
c: xev.Completion = .{},
c_c: xev.Completion = .{},

/// creates and returns a Timer object
fn new(l: *Lua) i32 {
    const delta = l.optNumber(@intFromEnum(Indices.delta)) orelse 1;
    l.argCheck(delta >= std.math.floatEps(f64), @intFromEnum(Indices.delta), "delta must be positive");
    const stage_end = l.optNumber(@intFromEnum(Indices.stage_end)) orelse -1;
    const stage = l.optNumber(@intFromEnum(Indices.stage)) orelse 1;
    const running_t = l.typeOf(@intFromEnum(Indices.running));
    const running = running_t == .none or running_t == .nil or l.toBoolean(@intFromEnum(Indices.running));
    lu.checkCallable(l, @intFromEnum(Indices.action));
    const c = l.newUserdata(Timer, @intFromEnum(Indices.data));
    c.* = .{};
    // set uservalues
    l.pushValue(1); // action = f
    l.setUserValue(-2, @intFromEnum(Indices.action)) catch unreachable;
    l.pushNumber(delta);
    l.setUserValue(-2, @intFromEnum(Indices.delta)) catch unreachable;
    l.pushNumber(stage_end);
    l.setUserValue(-2, @intFromEnum(Indices.stage_end)) catch unreachable;
    l.pushNumber(stage);
    l.setUserValue(-2, @intFromEnum(Indices.stage)) catch unreachable;
    l.pushBoolean(running);
    l.setUserValue(-2, @intFromEnum(Indices.running)) catch unreachable;
    l.newTable(); // data = {}
    l.setUserValue(-2, @intFromEnum(Indices.data)) catch unreachable;
    const seamstress = lu.getSeamstress(l);
    const now = seamstress.loop.now();
    l.pushInteger(now);
    l.setUserValue(-2, @intFromEnum(Indices.now)) catch unreachable;
    _ = l.getMetatableRegistry("seamstress.Timer");
    l.setMetatable(-2); // set metatable for the Timer
    // if running is false, don't start the Timer
    if (!running) return 1;
    l.pushValue(-1); // push the Timer
    const handle = l.ref(ziglua.registry_index) catch l.raiseErrorStr("unable to register timer!", .{});
    const next: u64 = @intFromFloat(delta * std.time.ms_per_s);
    seamstress.loop.timer(&c.c, next, ptrFromHandle(handle), bang);
    return 1;
}

const Indices = enum(i32) {
    action = 1,
    delta = 2,
    stage_end = 3,
    stage = 4,
    running = 5,
    now = 6,
    data = 7, // should always be the last entry
};

const indices = std.StaticStringMap(Indices).initComptime(.{
    .{ "action", .action },
    .{ "delta", .delta },
    .{ "stage_end", .stage_end },
    .{ "stage", .stage },
    .{ "running", .running },
});

/// return t[k], special casing depending on whether k is in the list of indices above or not
fn __index(l: *Lua) i32 {
    const t = l.typeOf(2); // typeof(k)
    if (t == .string) {
        const str = l.toString(2) catch unreachable; // if k is a string
        if (indices.get(str)) |value| { // and it is one of our special fields
            _ = l.getUserValue(1, @intFromEnum(value)) catch unreachable; // v = Timer[k]
            return 1; // return v
        }
    }
    _ = l.getUserValue(1, @intFromEnum(Indices.data)) catch unreachable; // Timer's data table; t
    _ = l.pushValue(2); // k
    _ = l.getTable(-2); // v = t[k]
    l.remove(-2); // remove t
    return 1; // return v
}

/// converts a userdata pointer to a Lua registry index handle
fn handleFromPtr(ptr: ?*anyopaque) i32 {
    const @"u32": u32 = @intCast(@intFromPtr(ptr));
    return @bitCast(@"u32");
}

/// converts a Lua registry index handle to a userdata pointer
fn ptrFromHandle(handle: i32) ?*anyopaque {
    const @"u32": u32 = @bitCast(handle);
    const ptr: usize = @"u32";
    return @ptrFromInt(ptr);
}

/// performs t[k] = v, special casing based on whether k is in the list of indices above
fn __newindex(l: *Lua) i32 {
    const t = l.typeOf(2);
    if (t == .string) {
        const key = l.toString(2) catch unreachable;
        if (indices.get(key)) |value| {
            switch (value) {
                .delta => {
                    const delta = l.checkNumber(3);
                    l.argCheck(delta >= std.math.floatEps(f64), 3, "delta must be positive");
                    l.pushNumber(delta);
                    l.setUserValue(1, @intFromEnum(value)) catch unreachable;
                    return 0;
                },
                .running => {
                    const running = l.toBoolean(3);
                    _ = l.getUserValue(1, @intFromEnum(value)) catch unreachable;
                    const old_running = l.toBoolean(-1);
                    l.pop(1);
                    l.pushBoolean(running);
                    l.setUserValue(1, @intFromEnum(value)) catch unreachable;
                    if (!old_running and running) {
                        const seamstress = lu.getSeamstress(l);
                        const now = seamstress.loop.now();
                        l.pushInteger(now);
                        l.setUserValue(1, @intFromEnum(Indices.now)) catch unreachable; // current time (in ns)
                        const c = &l.checkUserdata(Timer, 1, "seamstress.Timer").c;
                        _ = l.getUserValue(1, @intFromEnum(Indices.delta)) catch unreachable;
                        const delta = l.toNumber(-1) catch unreachable;
                        l.pop(2);
                        l.pushInteger(1); // set stage to 1
                        l.setUserValue(1, @intFromEnum(Indices.stage)) catch unreachable;
                        const next: u64 = @intFromFloat(delta * std.time.ms_per_s);
                        l.pushValue(1);
                        const handle = l.ref(ziglua.registry_index) catch l.raiseErrorStr("unable to register timer!", .{});
                        seamstress.loop.timer(c, next, ptrFromHandle(handle), bang);
                    }
                    return 0;
                },
                .stage, .stage_end => {
                    _ = l.checkNumber(3);
                    l.pushValue(3);
                    l.setUserValue(1, @intFromEnum(value)) catch unreachable;
                    return 0;
                },
                .action => {
                    lu.checkCallable(l, 3);
                    l.pushValue(3);
                    l.setUserValue(1, @intFromEnum(value)) catch unreachable;
                    return 0;
                },
                else => {},
            }
        }
    }
    _ = l.getUserValue(1, @intFromEnum(Indices.data)) catch unreachable;
    l.pushValue(2);
    l.pushValue(3);
    l.setTable(-3);
    return 0;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const xev = @import("xev");
const lu = @import("lua_util.zig");
const std = @import("std");
const builtin = @import("builtin");
