const Async = @This();

fn registerSeamstress(l: *Lua) void {
    blk: {
        l.newMetatable("seamstress.async.Promise") catch break :blk;
        l.setFuncs(functions, 0);

        _ = l.pushStringZ("__index");
        l.pushValue(-2);
        l.setTable(-3);

        l.pop(1);
    }
    lu.getSeamstress(l);
    _ = l.getField(-1, "async");
    l.remove(-2);
    _ = l.pushStringZ("Promise");
    l.pushFunction(ziglua.wrap(new));
    l.setTable(-3);
    l.pop(1);
}

const functions: []const ziglua.FnReg = &.{ .{
    .name = "anon",
    .func = ziglua.wrap(anon),
}, .{
    .name = "catch",
    .func = ziglua.wrap(catchFn),
}, .{
    .name = "finally",
    .func = ziglua.wrap(finally),
}, .{
    .name = "await",
    .func = ziglua.wrap(awaitFn),
} };

const Promise = struct {
    status: enum { waiting, pending, fulfilled, rejected },
    c: xev.Completion = .{},
    timer: xev.Timer,
    handle: i32 = undefined,
};

fn new(l: *Lua) i32 {
    const n = l.getTop();
    const newl = l.newThread();
    l.rotate(-n - 1, 1);
    l.xMove(newl, n);
    const p = l.newUserdata(Promise, 1);
    _ = l.getMetatableRegistry("seamstress.async.Promise");
    l.setMetatable(-2);
    l.rotate(-2, 1);
    l.setUserValue(-2, 1) catch unreachable;
    p.* = .{
        .timer = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new Promise: %s", .{@errorName(err).ptr}),
        .status = .waiting,
    };
    const wheel = lu.getWheel(l);
    l.pushValue(-1);
    p.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr});
    p.timer.run(&wheel.loop, &p.c, 2, i32, &p.handle, settleLuaPromise);
    return 1;
}

fn settleLuaPromise(ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch |err| panic("unexpected timer error!, {s}", .{@errorName(err)});
    const l = Wheel.getLua(loop);
    const handle = ev.?.*;
    _ = l.rawGetIndex(ziglua.registry_index, handle);
    const promise = l.toUserdata(Promise, -1) catch return .disarm;
    _ = l.getUserValue(-1, 1) catch unreachable;
    const lua = l.toThread(-1) catch unreachable;
    l.pop(2);
    var res: i32 = undefined;
    if (lua.resumeThread(l, switch (promise.status) {
        .waiting => lua.getTop() - 1,
        .pending => 0,
        else => unreachable,
    }, &res)) |result| {
        switch (result) {
            .ok => {
                promise.status = .fulfilled;
            },
            .yield => {
                promise.status = .pending;
                lua.pop(res);
                promise.timer.run(loop, c, 2, i32, &promise.handle, settleLuaPromise);
                return .disarm;
            },
        }
    } else |_| {
        lua.xMove(l, lua.getTop());
        promise.status = .rejected;
        l.raiseError();
    }
    l.unref(ziglua.registry_index, handle);
    return .disarm;
}

fn anon(l: *Lua) i32 {
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    l.checkType(2, .function);
    const t3 = l.typeOf(3);
    if (t3 != .function and t3 != .nil and t3 != .none) l.typeError(3, "function or nil");
    const promise = l.newUserdata(Promise, 2);
    _ = l.getMetatableRegistry("seamstress.async.Promise");
    l.setMetatable(-2);
    // resolve
    const newl = l.newThread();
    l.pushValue(2);
    // reject
    if (t3 == .function)
        l.pushValue(3)
    else
        l.pushFunction(ziglua.wrap(throw));
    l.xMove(newl, 2);
    l.setUserValue(-2, 1) catch unreachable;
    // previous promise
    l.pushValue(1);
    l.setUserValue(-2, 2) catch unreachable;
    promise.* = .{
        .timer = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new timer: %", .{@errorName(err).ptr}),
        .status = .waiting,
    };
    l.pushValue(-1);
    promise.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr});
    const wheel = lu.getWheel(l);
    promise.timer.run(&wheel.loop, &promise.c, 2, i32, &promise.handle, settleAnonPromise);
    return 1;
}

fn settleAnonPromise(ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch |err| panic("unexpected timer error! {s}", .{@errorName(err)});
    const l = Wheel.getLua(loop);
    const handle = ev.?.*;
    _ = l.rawGetIndex(ziglua.registry_index, handle);
    const promise = l.toUserdata(Promise, -1) catch return .disarm;
    _ = l.getUserValue(-1, 2) catch unreachable;
    const other = l.toUserdata(Promise, -1) catch unreachable;
    switch (other.status) {
        .waiting, .pending => {
            l.pop(2);
            promise.timer.run(loop, c, 2, i32, &promise.handle, settleAnonPromise);
            return .disarm;
        },
        else => {},
    }
    _ = l.getUserValue(-2, 1) catch unreachable;
    const lua = l.toThread(-1) catch unreachable;
    // we are .waiting, so our stack has both the resolve and reject functions on it
    // let's pop the right one
    lua.remove(if (other.status == .fulfilled) 2 else 1);
    // get the other promise's stack
    _ = l.getUserValue(-2, 1) catch unreachable;
    const o_lua = l.toThread(-1) catch unreachable;
    o_lua.xMove(lua, o_lua.getTop());
    var res: i32 = undefined;
    l.pop(4);
    if (lua.resumeThread(l, lua.getTop() - 1, &res)) |result| {
        switch (result) {
            .ok => {
                promise.status = .fulfilled;
            },
            .yield => {
                promise.status = .pending;
                lua.pop(res);
                // the previous promise settled, so we are just waiting normally
                promise.timer.run(loop, c, 2, i32, &promise.handle, settleLuaPromise);
                return .disarm;
            },
        }
    } else |_| {
        promise.status = .rejected;
    }
    l.unref(ziglua.registry_index, handle);
    return .disarm;
}

fn throw(l: *Lua) i32 {
    l.raiseError();
    return 0;
}

fn noOp(l: *Lua) i32 {
    return l.getTop();
}

fn catchFn(l: *Lua) i32 {
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    l.checkType(2, .function);
    l.pushFunction(ziglua.wrap(anon));
    l.pushValue(1);
    l.pushFunction(ziglua.wrap(noOp));
    l.pushValue(2);
    l.call(3, 1);
    return 1;
}

fn finally(l: *Lua) i32 {
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    l.checkType(2, .function);
    l.pushFunction(ziglua.wrap(anon));
    l.pushValue(1);
    l.pushValue(2);
    l.pushValue(2);
    l.call(3, 1);
    return 1;
}

fn xfer(l: *Lua) i32 {
    const i = Lua.upvalueIndex(1);
    const stack = l.toThread(i) catch unreachable;
    l.xMove(stack, l.getTop());
    return 0;
}

fn awaitContinues(l: *Lua, _: ziglua.Status, _: ziglua.Context) i32 {
    const promise = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    switch (promise.status) {
        .waiting, .pending => {
            l.yieldCont(0, 0, ziglua.wrap(awaitContinues));
        },
        .fulfilled, .rejected => {
            _ = l.getUserValue(1, 1) catch unreachable;
            const stack = l.toThread(-1) catch unreachable;
            l.pop(1);
            const n = stack.getTop();
            stack.xMove(l, n);
            return n;
        },
    }
}

fn awaitFn(l: *Lua) i32 {
    const promise = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    _ = promise; // autofix
    if (!l.isYieldable()) l.raiseErrorStr("cannot await a Promise outside of an async context (i.e. a coroutine or an async function)", .{});
    l.yieldCont(0, 0, ziglua.wrap(awaitContinues));
}

fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    if (m.self) |_| return;
    const self = try allocator.create(Async);
    errdefer allocator.destroy(self);
    m.self = self;
    self.* = .{};
    registerSeamstress(l);
}

fn deinit(m: *Module, _: *Lua, allocator: std.mem.Allocator, kind: Cleanup) void {
    const self: *Async = @ptrCast(@alignCast(m.self orelse return));
    if (kind != .full) return;
    allocator.destroy(self);
    m.self = null;
}

fn launch(_: *const Module, _: *Lua, _: *Wheel) anyerror!void {}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const xev = @import("xev");
const lu = @import("../lua_util.zig");
const std = @import("std");
const panic = std.debug.panic;
const Wheel = @import("../wheel.zig");
const Module = @import("../module.zig");
const Cleanup = @import("../seamstress.zig").Cleanup;
