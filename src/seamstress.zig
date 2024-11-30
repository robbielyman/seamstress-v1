const Seamstress = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
lua: *Lua,
status: enum { suspended, running } = .suspended,

pub fn register(l: *Lua) i32 {
    addPackageSearcher(l) catch l.raiseErrorStr("unable to add package searcher!", .{});
    const seamstress = l.newUserdata(Seamstress, 1);
    l.newTable();
    lu.load(l, "seamstress.event");
    l.setField(-2, "event");
    lu.load(l, "seamstress.async");
    l.setField(-2, "async");
    lu.load(l, "seamstress.Timer");
    l.setField(-2, "Timer");
    l.setUserValue(-2, 1) catch unreachable;
    seamstress.init(l) catch l.raiseErrorStr("unable to create seamstress event loop!", .{});
    blk: {
        l.newMetatable("seamstress") catch break :blk;
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(__index) },
            .{ .name = "__newindex", .func = ziglua.wrap(__newindex) },
            .{ .name = "run", .func = ziglua.wrap(run) },
            .{ .name = "resume", .func = ziglua.wrap(@"resume") },
            .{ .name = "__gc", .func = ziglua.wrap(__gc) },
        };
        l.setFuncs(funcs, 0);
        l.newTable();
        const stop_fns: []const ziglua.FnReg = &.{
            .{ .name = "stop", .func = ziglua.wrap(stop) },
        };
        l.setFuncs(stop_fns, 1);
        l.newTable();
        const panic_fns: []const ziglua.FnReg = &.{
            .{ .name = "panic", .func = ziglua.wrap(panic) },
        };
        l.setFuncs(panic_fns, 1);
    }
    l.pop(1);
    _ = l.getMetatableRegistry("seamstress");
    l.setMetatable(-2);
    l.pushFunction(ziglua.wrap(clearRegistry));
    lu.addExitHandler(l, .stop);
    return 1;
}

/// adds a "package searcher" to the Lua environment that handles calls to requiring seamstress modules
fn addPackageSearcher(lua: *Lua) !void {
    const top = if (builtin.mode == .Debug) lua.getTop();
    defer if (builtin.mode == .Debug) std.debug.assert(top == lua.getTop());
    // package.searchers[#package.searchers + 1] = f
    _ = try lua.getGlobal("package");
    _ = lua.getField(-1, "searchers");
    lua.pushFunction(ziglua.wrap(struct {
        fn searcher(l: *Lua) i32 { // where this is f
            const name = l.checkString(1);
            if (modules.list.get(name)) |func| {
                l.pushFunction(func);
                return 1;
            }
            return 0;
        }
    }.searcher));
    lua.rawSetIndex(-2, @intCast(lua.rawLen(-2) + 1)); // add our searcher to the end
    lua.pop(2); // pop `package` and `package.searchers`
}

pub fn init(self: *Seamstress, l: *Lua) !void {
    self.* = .{
        .pool = xev.ThreadPool.init(.{ .max_threads = 16 }),
        .lua = l,
        .loop = try xev.Loop.init(.{ .thread_pool = &self.pool }),
    };
}

pub fn main(l: *Lua) !void {
    l.openLibs();
    // we want a zig stack trace
    _ = l.atPanic(ziglua.wrap(struct {
        fn panic(lua: *Lua) i32 { // function panic(error_msg)
            const error_msg = lua.toStringEx(-1);
            // add a lua stack trace
            lua.traceback(lua, error_msg, 1); // local with_stack_trace = debug.traceback(error_msg, 1)
            const with_stack_trace = lua.toString(-1) catch unreachable;
            @call(.always_inline, std.debug.panic, .{ "lua crashed: {s}", .{with_stack_trace} });
        }
        // no need to return anything since std.debug.panic is of type noreturn
    }.panic));
    lu.load(l, "seamstress");
    const seamstress = l.toUserdata(Seamstress, -1) catch unreachable;
    l.setGlobal("seamstress");
    lu.load(l, "seamstress.repl");
    l.pop(1);
    lu.load(l, "seamstress.cli");
    l.pop(1);
    var c: xev.Completion = .{};
    seamstress.loop.timer(&c, 0, seamstress, struct {
        fn f(ud: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, r: xev.Result) xev.CallbackAction {
            const s: *Seamstress = @ptrCast(@alignCast(ud.?));
            blk: {
                const args = std.process.argsAlloc(s.lua.allocator()) catch break :blk;
                defer std.process.argsFree(s.lua.allocator(), args);
                if (args.len < 2) break :blk;
                if (std.mem.eql(u8, "test", args[1])) {
                    lu.load(s.lua, "seamstress.test");
                    break :blk;
                }
                s.lua.doFile(args[1]) catch {
                    lu.reportError(s.lua);
                };
            }
            lu.preparePublish(s.lua, &.{"init"});
            lu.doCall(s.lua, 1, 0) catch {
                lu.reportError(s.lua);
                return .disarm;
            };
            _ = r.timer catch return .disarm;
            return .disarm;
        }
    }.f);
    seamstress.status = .running;
    try seamstress.loop.run(.until_done);
}

fn __index(l: *Lua) i32 {
    const seamstress = l.checkUserdata(Seamstress, 1, "seamstress");
    _ = l.pushStringZ("status");
    if (l.compare(-1, 2, .eq)) {
        _ = l.pushStringZ(@tagName(seamstress.status));
        return 1;
    }
    _ = l.getUserValue(1, 1) catch unreachable;
    l.pushValue(2);
    switch (l.getTable(-2)) {
        .nil, .none => {
            l.getMetatable(1) catch unreachable;
            l.pushValue(2);
            _ = l.getTable(-2);
            return 1;
        },
        else => return 1,
    }
}

fn __newindex(l: *Lua) i32 {
    _ = l.pushStringZ("status");
    if (l.compare(-1, 2, .eq)) l.raiseErrorStr("unable to assign to seamstress.status!", .{});
    _ = l.getUserValue(1, 1) catch unreachable;
    l.pushValue(2);
    l.pushValue(3);
    l.setTable(-3);
    return 0;
}

fn __gc(l: *Lua) i32 {
    const seamstress = l.checkUserdata(Seamstress, 1, "seamstress");
    seamstress.loop.deinit();
    seamstress.pool.shutdown();
    seamstress.pool.deinit();
    seamstress.* = undefined;
    return 0;
}

fn panic(l: *Lua) i32 {
    const seamstress = l.checkUserdata(Seamstress, 1, "seamstress");
    lu.preparePublish(l, &.{"panic"});
    lu.doCall(l, 1, 0) catch {
        std.log.scoped(.seamstress).err("error in event handler: {s}", .{l.toString(-1) catch unreachable});
        lu.reportError(l);
    };
    const i = Lua.upvalueIndex(1);
    l.pushNil();
    while (l.next(i)) {
        if (lu.isCallable(l, -1)) {
            lu.doCall(l, 0, 0) catch {
                std.log.scoped(.seamstress).err("error in panic handler: {s}", .{l.toString(-1) catch unreachable});
                lu.reportError(l);
            };
        } else {
            l.pushValue(-2);
            const key = l.toStringEx(-1);
            const value = l.toStringEx(-2);
            l.pop(2);
            lu.format(l, "panic handler at key {s} is not callable; value: {s}", .{ key, value });
            std.log.scoped(.seamstress).err("{s}", .{l.toString(-1) catch unreachable});
            lu.reportError(l);
        }
    }
    if (seamstress.status == .suspended) {
        std.debug.dumpCurrentStackTrace(@returnAddress());
        std.process.exit(1);
    }
    return 0;
}

fn stop(l: *Lua) i32 {
    const seamstress = l.checkUserdata(Seamstress, 1, "seamstress");
    lu.preparePublish(l, &.{"stop"});
    lu.doCall(l, 1, 0) catch {
        std.log.scoped(.seamstress).err("error in event handler: {s}", .{l.toString(-1) catch unreachable});
        lu.reportError(l);
    };
    const i = Lua.upvalueIndex(1);
    l.pushNil();
    while (l.next(i)) {
        if (lu.isCallable(l, -1)) {
            lu.doCall(l, 0, 0) catch {
                std.log.scoped(.seamstress).err("error in stop handler: {s}", .{l.toString(-1) catch unreachable});
                lu.reportError(l);
            };
        } else {
            l.pushValue(-2);
            const key = l.toStringEx(-1);
            const value = l.toStringEx(-2);
            l.pop(2);
            lu.format(l, "stop handler at key {s} is not callable; value: {s}", .{ key, value });
            lu.reportError(l);
        }
    }
    if (seamstress.status == .suspended) seamstress.loop.run(.until_done) catch
        l.raiseErrorStr("error running event loop!", .{});
    return 0;
}

fn run(l: *Lua) i32 {
    const seamstress = l.checkUserdata(Seamstress, 1, "seamstress");
    const t = l.getTop();
    if (t > 1) {
        lu.checkCallable(l, 2);
        lu.load(l, "seamstress.async.Promise");
        l.insert(2);
        l.call(t - 1, 0);
        if (seamstress.status == .suspended) {
            defer seamstress.status = .suspended;
            seamstress.status = .running;
            seamstress.loop.run(.until_done) catch
                l.raiseErrorStr("error running event loop!", .{});
        }
    }
    switch (seamstress.status) {
        .suspended => {
            seamstress.status = .running;
            defer seamstress.status = .suspended;
            seamstress.loop.run(.until_done) catch
                l.raiseErrorStr("error running event loop!", .{});
        },
        .running => l.raiseErrorStr("seamstress object already running!", .{}),
    }
    return 0;
}

fn @"resume"(l: *Lua) i32 {
    const seamstress = l.checkUserdata(Seamstress, 1, "seamstress");
    switch (seamstress.status) {
        .suspended => {
            seamstress.status = .running;
            defer seamstress.status = .suspended;
            seamstress.loop.run(.once) catch
                l.raiseErrorStr("error running event loop!", .{});
        },
        .running => l.raiseErrorStr("seamstress object already running!", .{}),
    }
    return 0;
}

/// creates a copy of the registry table and then, for each entry in the copy table,
/// checks to see if the entry has a __cancel metamethod and calls that metamethod if so
fn clearRegistry(l: *Lua) i32 {
    l.newTable();
    const tbl = l.getTop();
    l.pushNil();
    const key = l.getTop();
    var index: ziglua.Integer = 1;
    while (l.next(ziglua.registry_index)) {
        defer l.setTop(key);
        switch (l.typeOf(-1)) {
            .userdata, .table => {
                _ = l.getMetaField(-1, "__cancel") catch continue;
                l.pop(1);
                l.setIndex(tbl, index);
                index += 1;
            },
            else => {},
        }
    }
    const len = index;
    index = 1;
    while (index < len) : (index += 1) {
        _ = l.getIndex(tbl, index);
        _ = l.getMetaField(-1, "__cancel") catch {};
        l.rotate(-2, 1);
        l.call(1, 0);
    }
    return 0;
}

pub fn panicCleanup(l: *Lua) void {
    @setCold(true);
    lu.load(l, "seamstress");
    _ = l.getField(-1, "panic");
    l.rotate(-2, 1);
    lu.doCall(l, 1, 0) catch {
        std.debug.print("{s}\n", .{l.toString(-1) catch unreachable});
    };
}

pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha",
    .build = "241129",
};

const xev = @import("xev");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const lu = @import("lua_util.zig");
const modules = @import("modules.zig");
const builtin = @import("builtin");

test "ref" {
    _ = modules;
}

test "lifecycle" {
    std.testing.log_level = .debug;
    const l = try Lua.init(&std.testing.allocator);
    defer l.deinit();
    l.openLibs();
    lu.load(l, "seamstress");
    const seamstress = try l.toUserdata(Seamstress, -1);
    var c: xev.Completion = .{};
    var failed = false;
    seamstress.loop.timer(&c, 1, &failed, struct {
        fn f(ud: ?*anyopaque, loop: *xev.Loop, d: *xev.Completion, r: xev.Result) xev.CallbackAction {
            _ = r.timer catch unreachable;
            const boolean: *bool = @ptrCast(@alignCast(ud.?));
            const lua = lu.getLua(loop);
            for (modules.list.values()) |@"fn"| {
                lua.pushFunction(@"fn");
                lu.doCall(lua, 0, 0) catch {
                    std.debug.print("{s}\n", .{lua.toString(-1) catch unreachable});
                    lua.pop(1);
                    boolean.* = true;
                };
            }
            loop.timer(d, 500, lua, struct {
                fn f(ptr: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, res: xev.Result) xev.CallbackAction {
                    _ = res.timer catch unreachable;
                    const luaa: *Lua = @ptrCast(@alignCast(ptr.?));
                    lu.load(luaa, "seamstress");
                    _ = luaa.getField(-1, "stop");
                    luaa.rotate(-2, 1);
                    lu.doCall(luaa, 1, 0) catch return .disarm;
                    return .disarm;
                }
            }.f);
            return .disarm;
        }
    }.f);

    seamstress.status = .running;
    try seamstress.loop.run(.until_done);
    try std.testing.expect(failed == false);
}
