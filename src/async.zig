pub fn registerSeamstress(l: *Lua) !void {
    lu.getSeamstress(l); // seamstress
    _ = l.pushStringZ("async"); // async
    l.newTable(); // t

    try l.newMetatable("seamstress.async"); // new metatable
    _ = l.pushStringZ("__call"); // __call
    l.pushFunction(ziglua.wrap(asyncFn)); // fn
    l.setTable(-3); // metatable.__call = fn
    l.setMetatable(-2); // setmetatable(t, metatable)

    try l.newMetatable("seamstress.async.Promise"); // new metatable
    l.setFuncs(functions, 0); // register functions

    _ = l.pushStringZ("__index"); // __index
    l.pushValue(-2); // metatable
    l.setTable(-3); // metatable.__index = metatable

    l.pop(1); // pop metatable
    _ = l.pushStringZ("Promise"); // Promise
    l.pushFunction(ziglua.wrap(newLuaPromise)); // function
    l.setTable(-3); // t.Promise = function
    l.setTable(-3); // seamstress.async = t
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

const Promise = @This();

status: enum { waiting, pending, fulfilled, rejected },
c: xev.Completion = .{},
handle: i32 = undefined,
ud: ?*anyopaque = null,

pub fn new(l: *Lua) !i32 {
    const p = l.newUserdata(Promise, 2);
    _ = l.getMetatableRegistry("seamstress.async.Promise");
    l.setMetatable(-2);
    const stack = l.newThread();
    stack.pushFunction(ziglua.wrap(noOp));
    stack.pushFunction(ziglua.wrap(throw));
    l.setUserValue(-2, 1) catch unreachable;
    const a = l.newUserdata(xev.Async, 0);
    a.* = try xev.Async.init();
    l.setUserValue(-2, 2) catch unreachable;
    const handle = try l.ref(ziglua.registry_index);
    p.* = .{
        .status = .pending,
        .handle = handle,
    };
    const wheel = lu.getWheel(l);
    a.wait(&wheel.loop, &p.c, i32, &p.handle, settle);
    logger.debug("new promise: 0x{x}", .{@intFromPtr(p)});
    return handle;
}

fn settle(ud: ?*i32, loop: *xev.Loop, _: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    logger.debug("settling promise", .{});
    const handle = ud.?.*;
    const l = Wheel.getLua(loop);
    _ = l.rawGetIndex(ziglua.registry_index, handle);
    const promise = l.toUserdata(Promise, -1) catch unreachable;
    _ = l.getUserValue(-1, 1) catch unreachable;
    const lua = l.toThread(-1) catch unreachable;
    _ = l.getUserValue(-2, 2) catch unreachable;
    const a = l.toUserdata(xev.Async, -1) catch unreachable;
    l.pop(3);
    a.deinit();
    if (lua.getTop() == 0) {
        promise.status = .fulfilled;
    } else {
        promise.status = if (lua.toBoolean(-1)) .fulfilled else .rejected;
        lua.pop(1);
    }
    _ = r catch |err| lua.raiseErrorStr("async error! %s", .{@errorName(err).ptr});
    l.unref(ziglua.registry_index, handle);
    // promise.a.deinit();
    logger.debug("promise is {s}", .{@tagName(promise.status)});
    return .disarm;
}

fn call(l: *Lua) i32 {
    const i = Lua.upvalueIndex(1);
    const n = l.getTop();
    const p = l.newUserdata(Promise, 2);
    _ = l.getMetatableRegistry("seamstress.async.Promise");
    l.setMetatable(-2);
    const newl = l.newThread();
    l.pushValue(i);
    var j: i32 = 1;
    while (j <= n) : (j += 1) {
        l.pushValue(j);
    }
    l.xMove(newl, n + 1);
    l.setUserValue(-2, 1) catch unreachable;
    const timer = l.newUserdata(xev.Timer, 0);
    timer.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new Promise: %s", .{@errorName(err).ptr});
    l.setUserValue(-2, 2) catch unreachable;
    p.* = .{
        .status = .waiting,
    };
    const wheel = lu.getWheel(l);
    l.pushValue(-1);
    p.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr});
    timer.run(&wheel.loop, &p.c, 2, i32, &p.handle, settleLuaPromise);
    return 1;
}

fn asyncFn(l: *Lua) i32 {
    const t = l.typeOf(2);
    if (t == .table or t == .userdata) {
        _ = l.getMetaField(2, "__call") catch {
            l.typeError(2, "callable");
        };
    } else l.checkType(2, .function);
    l.pushValue(2);
    l.pushClosure(ziglua.wrap(call), 1);
    return 1;
}

fn newLuaPromise(l: *Lua) i32 {
    const n = l.getTop();
    const newl = l.newThread();
    l.rotate(-n - 1, 1);
    l.xMove(newl, n);
    const p = l.newUserdata(Promise, 2);
    _ = l.getMetatableRegistry("seamstress.async.Promise");
    l.setMetatable(-2);
    l.rotate(-2, 1);
    l.setUserValue(-2, 1) catch unreachable;
    const timer = l.newUserdata(xev.Timer, 0);
    l.setUserValue(-2, 2) catch unreachable;
    timer.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new Promise: %s", .{@errorName(err).ptr});
    p.* = .{
        .status = .waiting,
    };
    const wheel = lu.getWheel(l);
    l.pushValue(-1);
    p.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr});
    timer.run(&wheel.loop, &p.c, 2, i32, &p.handle, settleLuaPromise);
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
    _ = l.getUserValue(-2, 2) catch unreachable;
    const timer = l.toUserdata(xev.Timer, -1) catch unreachable;
    l.pop(3);
    var res: i32 = undefined;
    if (lua.resumeThread(l, switch (promise.status) {
        .waiting => lua.getTop() - 1,
        .pending => 0,
        else => unreachable,
    }, &res)) |result| {
        switch (result) {
            .ok => {
                promise.status = .fulfilled;
                timer.deinit();
            },
            .yield => {
                promise.status = .pending;
                lua.pop(res);
                timer.run(loop, c, 2, i32, &promise.handle, settleLuaPromise);
                return .disarm;
            },
        }
    } else |_| {
        lua.xMove(l, lua.getTop());
        promise.status = .rejected;
        timer.deinit();
        l.raiseError();
    }
    logger.debug("lua promise is {s}", .{@tagName(promise.status)});
    l.unref(ziglua.registry_index, handle);
    return .disarm;
}

fn anon(l: *Lua) i32 {
    const p = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    logger.debug("other promise is {s}", .{@tagName(p.status)});
    l.checkType(2, .function);
    const t3 = l.typeOf(3);
    if (t3 != .function and t3 != .nil and t3 != .none) l.typeError(3, "function or nil");
    const promise = l.newUserdata(Promise, 3);
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
    l.setUserValue(-2, 3) catch unreachable;
    const timer = l.newUserdata(xev.Timer, 0);
    timer.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new timer: %", .{@errorName(err).ptr});
    l.setUserValue(-2, 2) catch unreachable;
    promise.* = .{
        .status = .waiting,
    };
    l.pushValue(-1);
    promise.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr});
    const wheel = lu.getWheel(l);
    timer.run(&wheel.loop, &promise.c, 2, i32, &promise.handle, settleAnonPromise);
    return 1;
}

fn settleAnonPromise(ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch |err| panic("unexpected timer error! {s}", .{@errorName(err)});
    const l = Wheel.getLua(loop);
    const handle = ev.?.*;
    _ = l.rawGetIndex(ziglua.registry_index, handle);
    const promise = l.toUserdata(Promise, -1) catch return .disarm;
    _ = l.getUserValue(-1, 3) catch unreachable;
    const other = l.toUserdata(Promise, -1) catch unreachable;
    _ = l.getUserValue(-2, 2) catch unreachable;
    const timer = l.toUserdata(xev.Timer, -1) catch unreachable;
    l.pop(1);
    switch (other.status) {
        .waiting, .pending => {
            l.pop(2);
            timer.run(loop, c, 2, i32, &promise.handle, settleAnonPromise);
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
                timer.deinit();
            },
            .yield => {
                promise.status = .pending;
                lua.pop(res);
                // the previous promise settled, so we are just waiting normally
                timer.run(loop, c, 2, i32, &promise.handle, settleLuaPromise);
                return .disarm;
            },
        }
    } else |_| {
        promise.status = .rejected;
        timer.deinit();
    }
    l.unref(ziglua.registry_index, handle);
    logger.debug("anon promise is {s}", .{@tagName(promise.status)});
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
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise");
    if (!l.isYieldable()) l.raiseErrorStr("cannot await a Promise outside of an async context (i.e. a coroutine or an async function)", .{});
    l.yieldCont(0, 0, ziglua.wrap(awaitContinues));
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const xev = @import("xev");
const lu = @import("lua_util.zig");
const std = @import("std");
const panic = std.debug.panic;
const Wheel = @import("wheel.zig");
const logger = std.log.scoped(.@"async");
