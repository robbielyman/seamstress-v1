/// JavaScript-inspired asynchronous events.
/// A `Promise` is an opaque handle to an operation.
/// `Promise` objects always execute and cannot be canceled or altered once created.
/// `Promise` methods allow the user to sequence actions following the completion
/// or handling the failure of the given operation.
/// Also provided is an `async` function, which takes in a function as an argument
/// and returns a function that, when called, creates a `Promise`
/// of the original function's eventual completion.
/// @module seamstress.async
/// @author Rylee Alanza Lyman
const Promise = @This();

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
    l.createTable(0, 3); // s
    l.createTable(0, 1); // its metatable
    _ = l.pushStringZ("__call"); // __call
    l.pushFunction(ziglua.wrap(newLuaPromise)); // function
    l.setTable(-3); // metatable.__call = function
    l.setMetatable(-2); // setmetatable(s, metatable)
    _ = l.pushStringZ("all"); // all
    l.pushFunction(ziglua.wrap(multiPromise(.all))); // function
    l.setTable(-3); // s.all = function
    _ = l.pushStringZ("any"); // any
    l.pushFunction(ziglua.wrap(multiPromise(.any))); // function
    l.setTable(-3); // s.any = function
    _ = l.pushStringZ("race"); // race
    l.pushFunction(ziglua.wrap(multiPromise(.race))); // function
    l.setTable(-3); // s.race = function
    l.setTable(-3); // t.Promise = s
    l.setTable(-3); // seamstress.async = t
    l.pop(1); // pop seamstress
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

/// Creates an asynchronous function with body `f`.
/// Internally `f` is executed on a coroutine,
/// so calling `coroutine.yield()` and awaiting `Promise` objects
/// from within `f` is valid.
/// @function seamstress.async
/// @tparam function f
/// @treturn function(...):Promise
/// The returned function creates a new `Promise`
/// with `f` and its arguments, schedules its asynchronous execution
/// and returns the `Promise`.
fn asyncFn(l: *Lua) i32 {
    lu.checkCallable(l, 2);
    l.pushClosure(ziglua.wrap(call), 1);
    return 1;
}

/// @type seamstress.async.Promise
status: enum { waiting, pending, fulfilled, rejected },
c: xev.Completion = .{},
handle: i32 = undefined,
ud: ?*anyopaque = null,

// creates a Promise, returning on success an integer representing a Lua handle to it
// to fulfill this Promise, push `true` onto its stack after pushing any relevant results
// to reject it, push `false`
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
    return handle;
}

// settles a promise whose second UserValue is an xev.Async
fn settle(ud: ?*i32, loop: *xev.Loop, _: *xev.Completion, r: xev.Async.WaitError!void) xev.CallbackAction {
    const handle = ud.?.*;
    const l = Wheel.getLua(loop);
    _ = l.rawGetIndex(ziglua.registry_index, handle); // pushes the Promise onto the stack
    const promise = l.toUserdata(Promise, -1) catch unreachable;
    _ = l.getUserValue(-1, 1) catch unreachable; // pushes the Promise's Lua thread onto the stack
    const lua = l.toThread(-1) catch unreachable;
    _ = l.getUserValue(-2, 2) catch unreachable; // pushes the Promise's second UserValue onto the stack
    const a = l.toUserdata(xev.Async, -1) catch unreachable; // that UserValue is an xev.Async
    l.pop(3); // clear the stack
    a.deinit(); // close the Async
    if (lua.getTop() == 0) {
        promise.status = .fulfilled; // technically a misuse of the type
    } else {
        promise.status = if (lua.toBoolean(-1)) .fulfilled else .rejected; // to fulfill this kind of promise, push `true` onto its stack
        lua.pop(1);
    }
    _ = r catch |err| lua.raiseErrorStr("async error! %s", .{@errorName(err).ptr});
    l.unref(ziglua.registry_index, handle); // allows the Promise to be garbage-collected
    return .disarm;
}

// calls an async function, returning a new Promise
fn call(l: *Lua) i32 {
    const i = Lua.upvalueIndex(1); // the function we passed into `seamstress.async`
    const n = l.getTop(); // the number of arguments to the function
    const p = l.newUserdata(Promise, 2); // create a Promise
    _ = l.getMetatableRegistry("seamstress.async.Promise"); // grab the metatable
    l.setMetatable(-2); // setmetable(promise, metatable)
    const newl = l.newThread(); // create a thread
    l.pushValue(i); // push the function
    var j: i32 = 1;
    while (j <= n) : (j += 1) {
        l.pushValue(j); // for each function argument, push it onto the stack
    }
    l.xMove(newl, n + 1); // move the function and its arguments to the new thread
    l.setUserValue(-2, 1) catch unreachable; // assign the thread to the Promise
    const timer = l.newUserdata(xev.Timer, 0); // create a timer
    timer.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new Promise: %s", .{@errorName(err).ptr});
    l.setUserValue(-2, 2) catch unreachable; // assign the timer to the Promise
    p.* = .{
        .status = .waiting,
    };
    const wheel = lu.getWheel(l);
    l.pushValue(-1); // push the Promise again
    p.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr}); // ref pops
    timer.run(&wheel.loop, &p.c, 2, i32, &p.handle, settleLuaPromise); // add to the event loop
    return 1;
}

/// Executes its function argument asynchronously.
/// @function seamstress.async.Promise
/// @tparam function f to be executed asynchronously.
/// @param[opt] ... will be passed to f
/// @treturn Promise
fn newLuaPromise(l: *Lua) i32 {
    l.remove(1); // we don't need the metatable
    const n = l.getTop(); // the function and its arguments
    const newl = l.newThread(); // createa thread
    l.rotate(-n - 1, 1); // put it at the bottom of the stack
    l.xMove(newl, n); // move the function and its arguments to the thread
    const p = l.newUserdata(Promise, 2); // create a Promise
    _ = l.getMetatableRegistry("seamstress.async.Promise"); // grab the metatable
    l.setMetatable(-2); // setmetatable(promise, metatable)
    l.rotate(-2, 1); // put the Promise below the thread
    l.setUserValue(-2, 1) catch unreachable; // assign the thread to the Promise
    const timer = l.newUserdata(xev.Timer, 0); // create a timer
    l.setUserValue(-2, 2) catch unreachable; // assign it to the Promise
    timer.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new Promise: %s", .{@errorName(err).ptr});
    p.* = .{
        .status = .waiting,
    };
    const wheel = lu.getWheel(l);
    l.pushValue(-1); // push the Promise
    p.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr}); // ref pops
    timer.run(&wheel.loop, &p.c, 2, i32, &p.handle, settleLuaPromise); // add to the event loop
    return 1;
}

// attempts to resolve a promise created with seamstress.async.Promise by resuming its coroutine
fn settleLuaPromise(ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch |err| panic("unexpected timer error! {s}", .{@errorName(err)});
    const l = Wheel.getLua(loop);
    const handle = ev.?.*;
    _ = l.rawGetIndex(ziglua.registry_index, handle); // push the Promise onto the stack
    const promise = l.toUserdata(Promise, -1) catch unreachable;
    _ = l.getUserValue(-1, 1) catch unreachable; // get the thread
    const lua = l.toThread(-1) catch unreachable;
    _ = l.getUserValue(-2, 2) catch unreachable; // get the timer
    const timer = l.toUserdata(xev.Timer, -1) catch unreachable;
    l.pop(3); // remove from the stack
    var res: i32 = undefined;
    if (lua.resumeThread(l, switch (promise.status) {
        .waiting => lua.getTop() - 1, // pass the arguments to the function
        .pending => 0, // otherwise nothing to pass
        else => unreachable,
    }, &res)) |result| {
        switch (result) {
            .ok => {
                promise.status = .fulfilled; // the function returned!
                timer.deinit(); // the timer is done
            },
            .yield => {
                promise.status = .pending; // the function yielded
                lua.pop(res); // remove the values it passed to yield
                timer.run(loop, c, 2, i32, &promise.handle, settleLuaPromise); // try again in 2ms
                return .disarm;
            },
        }
    } else |_| {
        promise.status = .rejected; // the function had an error
        timer.deinit();
    }
    l.unref(ziglua.registry_index, handle); // if we got here, the promise is settled, and we don't need the reference
    return .disarm;
}

/// Sequences actions to take after the resolution of `self`.
/// The name is chosen for expressions like "I shall return anon":
/// in JavaScript the same functionality is provided by a function named "then",
/// which is a reserved word in Lua.
/// Values (or errors) returned by the `Promise` are passed as arguments
/// to the appropriate function.
/// @function seamstress.async.Promise:anon
/// @tparam function resolve executed if the `Promise` is resolved successfully
/// @tparam[opt] function reject executed if the `Promise` resolves with errors
/// @treturn Promise `Promise` objects are immutable, so a new `Promise` is returned.
fn anon(l: *Lua) i32 {
    const t3 = l.typeOf(3);
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise"); // self should be a Promise
    const promise = l.newUserdata(Promise, 3);
    _ = l.getMetatableRegistry("seamstress.async.Promise");
    l.setMetatable(-2);
    const newl = l.newThread();
    lu.checkCallable(l, 2); // second argument should be callable
    if (t3 != .nil and t3 != .none) {
        lu.checkCallable(l, 3); // third argument should be nil or callable
    } else {
        l.pushFunction(ziglua.wrap(throw));
    }
    l.xMove(newl, 2); // move both functions to the new thread
    l.setUserValue(-2, 1) catch unreachable; // assign the thread to the Promise
    l.pushValue(1); // push previous promise
    l.setUserValue(-2, 3) catch unreachable; // assign it to the Promise
    const timer = l.newUserdata(xev.Timer, 0); // create a timer
    timer.* = xev.Timer.init() catch |err| l.raiseErrorStr("error creating new timer: %", .{@errorName(err).ptr});
    l.setUserValue(-2, 2) catch unreachable; // assign it to the Promise
    promise.* = .{
        .status = .waiting,
    };
    l.pushValue(-1); // push the promise
    promise.handle = l.ref(ziglua.registry_index) catch |err| l.raiseErrorStr("unable to register Promise! %s", .{@errorName(err).ptr}); // ref pops
    const wheel = lu.getWheel(l);
    timer.run(&wheel.loop, &promise.c, 2, i32, &promise.handle, settleAnonPromise); // add the new promise to the event loop
    return 1;
}

// attempt to settle a promise created with anon
fn settleAnonPromise(ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch |err| panic("unexpected timer error! {s}", .{@errorName(err)});
    const l = Wheel.getLua(loop);
    const handle = ev.?.*;
    _ = l.rawGetIndex(ziglua.registry_index, handle);
    const promise = l.toUserdata(Promise, -1) catch unreachable; // push the Promise
    _ = l.getUserValue(-1, 3) catch unreachable; // push the other Promise
    const other = l.toUserdata(Promise, -1) catch unreachable;
    _ = l.getUserValue(-2, 2) catch unreachable; // push the timer
    const timer = l.toUserdata(xev.Timer, -1) catch unreachable;
    l.pop(1); // pop the timer
    switch (other.status) {
        .waiting, .pending => {
            l.pop(2); // pop the Promises
            timer.run(loop, c, 2, i32, &promise.handle, settleAnonPromise); // try again in 2ms
            return .disarm;
        },
        else => {},
    }
    _ = l.getUserValue(-2, 1) catch unreachable; // get our stack
    const lua = l.toThread(-1) catch unreachable;
    // we are .waiting, so our stack has both the resolve and reject functions on it
    // let's pop the right one
    lua.remove(if (other.status == .fulfilled) 2 else 1);
    // get the other promise's stack
    _ = l.getUserValue(-2, 1) catch unreachable;
    const o_lua = l.toThread(-1) catch unreachable;
    o_lua.xMove(lua, o_lua.getTop()); // move return values from the other stack to ours
    var res: i32 = undefined;
    l.pop(4); // remove the stacks and the promises
    if (lua.resumeThread(l, lua.getTop() - 1, &res)) |result| { // call our function
        switch (result) {
            .ok => {
                promise.status = .fulfilled; // that went ok! we're fulfilled
                timer.deinit();
            },
            .yield => {
                promise.status = .pending; // we yielded
                lua.pop(res); // pop anything the yield passed us
                // the previous promise settled, so we are just waiting normally
                timer.run(loop, c, 2, i32, &promise.handle, settleLuaPromise);
                return .disarm;
            },
        }
    } else |_| { // our function had an error
        promise.status = .rejected; // we reject
        timer.deinit();
    }
    l.unref(ziglua.registry_index, handle); // if we got here, our promise is settled
    return .disarm;
}

// default promise rejection handler
fn throw(l: *Lua) i32 {
    l.raiseError(); // throws an error, so there's a potential crash here
    return 0;
}

// default promise resolution handler
fn noOp(l: *Lua) i32 {
    return l.getTop();
}

/// Convenient alias for `self:anon(function(...) return ... end, f)`.
/// @function seamstress.async.Promise:catch
/// @tparam function f executed if `self` resolves with errors
/// The error message raised by the `Promise` is passed as an argument to `f`.
/// @treturn Promise `Promise` objects are immutable, so a new `Promise` is returned.
fn catchFn(l: *Lua) i32 {
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise"); // self is a Promise
    l.pushFunction(ziglua.wrap(anon)); // we're going to call self:anon
    l.pushValue(1); // on self
    l.pushFunction(ziglua.wrap(noOp)); // catch "does nothing" if the promise resolves
    lu.checkCallable(l, 2); // the second argument should be callable (pushes it)
    l.call(3, 1); // call
    return 1; // return the new Promise
}

/// Convenient alias for `self:anon(f, f)`.
/// @function seamstress.async.Promise:finally
/// @tparam function f executed regardless of whether `self` succeeds or fails.
/// Values (or errors) returned by the `Promise` are passed as arguments to `f`.
/// @treturn Promise `Promise` objects are immutable, so a new `Promise` is returned.
fn finally(l: *Lua) i32 {
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise"); // self is a Promise
    l.pushFunction(ziglua.wrap(anon)); // we're going to call self:anon
    l.pushValue(1); // on self
    lu.checkCallable(l, 2); // the second argument should be callable (pushes it)
    l.pushValue(2); // push it again
    l.call(3, 1); // call
    return 1; // return the new Promise
}

// the business end of await
fn awaitContinues(l: *Lua, _: ziglua.Status, _: ziglua.Context) i32 {
    const promise = l.checkUserdata(Promise, 1, "seamstress.async.Promise"); // we're awaiting a Promise
    switch (promise.status) {
        .waiting, .pending => {
            l.yieldCont(0, 0, ziglua.wrap(awaitContinues)); // we'll keep waiting
        },
        .fulfilled, .rejected => {
            _ = l.getUserValue(1, 1) catch unreachable; // get the Promise's stack
            const stack = l.toThread(-1) catch unreachable;
            l.pop(1); // pop it
            const n = stack.getTop(); // move to our stack
            stack.xMove(l, n);
            if (promise.status == .rejected) l.raiseError();
            return n; // return the values
        },
    }
}

/// Waits on the successful completion of a `Promise` and returns its return values.
/// Because awaiting a promise yields execution, `await`
/// may only be called from within a coroutine or asynchronous context,
/// like an async function or a `Promise`.
/// The following code snippets are equivalent; both will print "the number is 25".
///     local a = seamstress.async(function(x) return x + 12 end)
///     local b = seamstress.async.Promise(function()
///       a(13):anon(function(x) print('the number is ' .. x) end)
///     end)
///     local c = seamstress.async.Promise(function()
///       local x = a(13):await()
///       print('the number is ' .. x)
///     end)
/// @see seamstress.async
/// @function seamstress.async.Promise:await
/// @return ... the return values of `self`.
fn awaitFn(l: *Lua) i32 {
    _ = l.checkUserdata(Promise, 1, "seamstress.async.Promise"); // we're awaiting a Promise
    if (!l.isYieldable()) l.raiseErrorStr("cannot await a Promise outside of an async context (i.e. a coroutine or an async function)", .{}); // we'd better be able to yield
    l.yieldCont(0, 0, ziglua.wrap(awaitContinues)); // 'cause we're gonna
}

// creates a Promise that references all the Promises passed in
fn oneFromMany(l: *Lua) !*Promise {
    const n = l.getTop(); // how many promises?
    var i: i32 = 1;
    const p = l.newUserdata(Promise, 3 + n); // thread, timer, n, ...
    _ = l.getMetatableRegistry("seamstress.async.Promise"); // fetch metatable
    l.setMetatable(-2); // setmetatable(promise, metatable)
    const stack = l.newThread(); // new thread
    stack.pushFunction(ziglua.wrap(noOp)); // push defaults
    stack.pushFunction(ziglua.wrap(throw));
    l.setUserValue(-2, 1) catch unreachable; // assign to promise
    const t = l.newUserdata(xev.Timer, 0); // create timer
    t.* = try xev.Timer.init();
    l.setUserValue(-2, 2) catch unreachable; // assign to promise
    l.pushInteger(n); // push n
    l.setUserValue(-2, 3) catch unreachable; // assign to promise
    while (i <= n) : (i += 1) {
        _ = l.checkUserdata(Promise, i, "seamstress.async.Promise");
        l.pushValue(i); // push other promise
        l.setUserValue(-2, 3 + i) catch unreachable; // assign to our promise
    }
    l.pushValue(-1); // push the promise
    const handle = try l.ref(ziglua.registry_index); // ref pops
    p.* = .{
        .status = .pending,
        .handle = handle,
    };
    return p; // return the promise
}

const Which = enum { any, all, race };

// generic over which Promise method we're calling
fn settleFn(comptime which: Which) fn (ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const inner = struct {
        fn f(ev: ?*i32, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
            _ = r catch |err| panic("unexpected timer error! {s}", .{@errorName(err)});
            const l = Wheel.getLua(loop);
            const handle = ev.?.*;
            _ = l.rawGetIndex(ziglua.registry_index, handle); // push the Promise onto the stack
            const promise = l.toUserdata(Promise, -1) catch unreachable;
            _ = l.getUserValue(-1, 1) catch unreachable; // get the thread
            const lua = l.toThread(-1) catch unreachable;
            _ = l.getUserValue(-2, 2) catch unreachable; // get the timer
            const timer = l.toUserdata(xev.Timer, -1) catch unreachable;
            l.pop(2); // leave the Promise on the stack
            _ = l.getUserValue(-1, 3) catch unreachable;
            const n = l.toInteger(-1) catch unreachable; // get the number of associated promises
            l.pop(1); // pop that number
            var i: i32 = 1;
            // special case: no promises passed in
            if (n == 0) {
                switch (which) {
                    .any => promise.status = .rejected, // we reject
                    .all => promise.status = .fulfilled, // we fulfill
                    .race => promise.status = .fulfilled, // TODO: does this match expectations?
                }
                l.unref(ziglua.registry_index, handle); // the promise is settled, and we don't need the reference
                timer.deinit();
                return .disarm;
            }
            var all_of_em = true;
            while (i <= n) : (i += 1) {
                _ = l.getUserValue(-1, 3 + i) catch unreachable; // grab the ith Promise
                const other = l.toUserdata(Promise, -1) catch unreachable;
                switch (which) {
                    .any => switch (other.status) {
                        .fulfilled => {
                            promise.status = .fulfilled; // we fulfill
                            _ = l.getUserValue(-1, 1) catch unreachable;
                            const stack = l.toThread(-1) catch unreachable;
                            l.pop(2);
                            stack.xMove(lua, stack.getTop()); // pull from its stack
                            lua.remove(2); // remove the reject handler
                            var res: i32 = undefined;
                            _ = lua.resumeThread(l, lua.getTop() - 1, &res) catch unreachable;
                            break;
                        },
                        .rejected => {},
                        else => all_of_em = false,
                    },
                    .all => switch (other.status) {
                        .fulfilled => {},
                        .rejected => {
                            promise.status = .rejected; // we reject
                            _ = l.getUserValue(-1, 1) catch unreachable; // grab the other promise's stack
                            const stack = l.toThread(-1) catch unreachable;
                            l.pop(2);
                            stack.xMove(lua, stack.getTop()); // pull from it
                            lua.remove(1); // remove the resolve handler
                            var res: i32 = undefined;
                            _ = lua.resumeThread(l, lua.getTop() - 1, &res) catch {}; // should always error
                            break;
                        },
                        else => all_of_em = false,
                    },
                    .race => switch (other.status) {
                        .fulfilled => {
                            promise.status = .fulfilled; // we fulfill
                            _ = l.getUserValue(-1, 1) catch unreachable; // grab the other promise's stack
                            const stack = l.toThread(-1) catch unreachable;
                            l.pop(2);
                            stack.xMove(lua, stack.getTop()); // pull from it
                            lua.remove(2); // remove the reject handler
                            var res: i32 = undefined;
                            _ = lua.resumeThread(l, lua.getTop() - 1, &res) catch unreachable;
                            break;
                        },
                        .rejected => {
                            promise.status = .rejected; // we reject
                            _ = l.getUserValue(-1, 1) catch unreachable; // grab the other promise's stack
                            const stack = l.toThread(-1) catch unreachable;
                            l.pop(2);
                            stack.xMove(lua, stack.getTop()); // pull from it
                            lua.remove(1); // remove the resolve handler
                            var res: i32 = undefined;
                            _ = lua.resumeThread(l, lua.getTop() - 1, &res) catch {}; // should always error
                            break;
                        },
                        else => all_of_em = false,
                    },
                }
                l.pop(1); // pop it
            } else {
                if (all_of_em) {
                    promise.status = if (which == .all) .fulfilled else .rejected;
                    var j: i32 = 1;
                    while (j <= n) : (j += 1) {
                        _ = l.getUserValue(-1, 3 + j) catch unreachable; // grab the jth Promise
                        _ = l.getUserValue(-1, 1) catch unreachable; // grab the other promise's stack
                        const stack = l.toThread(-1) catch unreachable;
                        l.pop(2);
                        stack.xMove(lua, if (promise.status == .fulfilled) stack.getTop() else 1); // pull from it
                    }
                    if (promise.status == .rejected) {
                        var k: i32 = 3; // the first two values are functions
                        const m = lua.getTop();
                        lua.newTable();
                        while (k <= m) : (k += 1) {
                            lua.pushValue(3);
                            lua.setIndex(-2, k - 2);
                            lua.remove(3);
                        }
                    }
                    lua.remove(if (promise.status == .fulfilled) 2 else 1); // remove the handler
                    var res: i32 = undefined;
                    _ = lua.resumeThread(l, lua.getTop() - 1, &res) catch {};
                    // the promise is settled, and we don't need the reference
                    l.unref(ziglua.registry_index, handle);
                    timer.deinit();
                    return .disarm;
                }
                // we're not done, so go again
                timer.run(loop, c, 2, i32, &promise.handle, settleFn(which)); // try again in 2ms
                return .disarm;
            }
            // if we got here, the promise is settled, and we don't need the reference
            l.unref(ziglua.registry_index, handle);
            timer.deinit();
            return .disarm;
        }
    };
    return inner.f;
}

// generic over which Promise method we're callind
fn multiPromise(comptime which: Which) fn (l: *Lua) i32 {
    const inner = struct {
        fn f(l: *Lua) i32 {
            const p = oneFromMany(l) catch |err| l.raiseErrorStr("unable to create promise %s", .{@errorName(err).ptr}); // create Promise
            _ = l.getUserValue(-1, 2) catch unreachable; // grab the timer
            const t = l.toUserdata(xev.Timer, -1) catch unreachable;
            l.pop(1); // pop it
            const wheel = lu.getWheel(l);
            t.run(&wheel.loop, &p.c, 2, i32, &p.handle, settleFn(which)); // add to the event loop
            return 1; // return the new Promise
        }
    };
    return inner.f;
}

/// Creates a new `Promise` which fulfills when all of its arguments fulfill.
/// The `Promise` rejects if any of its arguments reject.
/// @function seamstress.async.Promise.all
/// @tparam[opt] Promise promises zero or more `Promise` objects
/// @treturn Promise `Promise` objects are immutable, so a new `Promise` is returned.
const ziglua = @import("ziglua");
/// Creates a new `Promise` which fulfills when any of its arguments fulfill.
/// The `Promise` rejects if all of its arguments reject.
/// @function seamstress.async.Promise.any
/// @tparam[opt] Promise promises zero or more `Promise` objects
/// @treturn Promise `Promise` objects are immutable, so a new `Promise` is returned.
const Lua = ziglua.Lua;
/// Creates a new `Promise` which settles when any of its arguments settle.
/// @function seamstress.async.Promise.race
/// @tparam[opt] Promise promises zero or more `Promise` objects
/// @treturn Promise `Promise` objects are immutable, so a new `Promise` is returned.
const xev = @import("xev");
const lu = @import("lua_util.zig");
const std = @import("std");
const panic = std.debug.panic;
const Wheel = @import("wheel.zig");
const logger = std.log.scoped(.@"async");
