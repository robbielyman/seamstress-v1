const Cli = @This();
const max_input_len = 2 * 1024;

buffer: std.ArrayListUnmanaged(u8) = .{},
c: xev.Completion = .{},
c_c: xev.Completion = .{},
stdin: Stdin,
running: bool = true,

pub fn register(l: *Lua) i32 {
    const cli = l.newUserdata(Cli, 0);
    cli.* = .{ .stdin = Stdin.init() };
    blk: {
        l.newMetatable("seamstress.cli") catch break :blk;
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__gc", .func = ziglua.wrap(__gc) },
            .{ .name = "__index", .func = ziglua.wrap(__index) },
            .{ .name = "__newindex", .func = ziglua.wrap(__newindex) },
            .{ .name = "__cancel", .func = ziglua.wrap(__cancel) },
        };
        l.setFuncs(funcs, 0);
    }
    l.pop(1);
    _ = l.getMetatableRegistry("seamstress.cli");
    l.setMetatable(-2);
    setup(l) catch l.raiseErrorStr("unable to start CLI!", .{});
    return 1;
}

/// reads from the xev.File by using the event loop
fn setup(lua: *Lua) !void {
    const self = try lua.toUserdata(Cli, -1);
    self.running = true;
    try self.buffer.ensureUnusedCapacity(lua.allocator(), max_input_len);
    const seamstress = lu.getSeamstress(lua);
    lua.pushValue(-1); // ref pops
    const h = try lua.ref(ziglua.registry_index);
    if (!builtin.is_test) try std.io.getStdOut().writeAll("> ");
    self.stdin.read(&seamstress.loop, &self.c, .{
        .slice = self.buffer.unusedCapacitySlice(),
    }, anyopaque, lu.ptrFromHandle(h), struct {
        fn stdinCallback(
            ptr: ?*anyopaque,
            loop: *xev.Loop,
            c: *xev.Completion,
            _: Stdin,
            _: xev.ReadBuffer,
            r: xev.ReadError!usize,
        ) xev.CallbackAction {
            const l = lu.getLua(loop);
            const handle = lu.handleFromPtr(ptr);
            _ = l.rawGetIndex(ziglua.registry_index, handle);
            const cli = l.toUserdata(Cli, -1) catch unreachable;

            const length = r catch |err| {
                const str = @errorName(err);
                l.unref(ziglua.registry_index, handle);
                cli.running = false;
                if (err != error.Canceled and err != error.EOF)
                    logger.err("error reading from stdin! {s}", .{str});
                if (err == error.EOF) {
                    lu.load(l, "seamstress");
                    _ = l.getField(-1, "stop");
                    l.rotate(-2, 1);
                    lu.doCall(l, 1, 0) catch {
                        lu.reportError(l);
                    };
                }
                return .disarm;
            };
            l.pop(1);

            cli.buffer.items.len += length;
            if (std.mem.eql(u8, "quit\n", cli.buffer.items)) {
                l.unref(ziglua.registry_index, handle);
                cli.running = false;
                lu.load(l, "seamstress");
                _ = l.getField(-1, "stop");
                l.rotate(-2, 1);
                lu.doCall(l, 1, 0) catch {
                    lu.reportError(l);
                };
                return .disarm;
            }
            var keep_going = true;
            defer if (!keep_going) {
                l.unref(ziglua.registry_index, handle);
                cli.running = false;
            };
            var buf = std.io.bufferedWriter(if (!builtin.is_test)
                std.io.getStdOut().writer()
            else
                std.io.null_writer);
            const stdout = buf.writer();
            lu.load(l, "seamstress.repl");
            _ = l.pushString(cli.buffer.items);
            lu.doCall(l, 1, ziglua.mult_return) catch {
                lu.reportError(l);
                cli.buffer.clearRetainingCapacity();
                cli.buffer.ensureUnusedCapacity(lu.allocator(l), max_input_len) catch
                    logger.warn("out of memory; unable to grow input buffer!", .{});
                cli.stdin.read(loop, c, .{
                    .slice = cli.buffer.unusedCapacitySlice(),
                }, anyopaque, ptr, @This().stdinCallback);
                return .disarm;
            };
            defer l.setTop(0);
            if (l.getTop() > 0 and l.typeOf(-1) == .string and std.mem.endsWith(u8, l.toString(-1) catch unreachable, "<eof>")) {
                stdout.writeAll(">... ") catch |err| {
                    logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                    keep_going = false;
                    return .disarm;
                };
            } else { // complete; let's print
                cli.buffer.clearRetainingCapacity();
                printAll(l, stdout) catch |err| {
                    logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                    keep_going = false;
                    return .disarm;
                };
                stdout.writeAll("> ") catch |err| {
                    logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                    keep_going = false;
                    return .disarm;
                };
            }
            buf.flush() catch |err| {
                logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                keep_going = false;
                return .disarm;
            };
            cli.buffer.ensureUnusedCapacity(lu.allocator(l), max_input_len) catch
                logger.warn("out of memory; unable to grow input buffer!", .{});
            cli.stdin.read(loop, c, .{
                .slice = cli.buffer.unusedCapacitySlice(),
            }, anyopaque, ptr, @This().stdinCallback);
            return .disarm;
        }
    }.stdinCallback);
}

fn printAll(l: *Lua, stdout: anytype) !void {
    const n = l.getTop();
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        switch (l.typeOf(i)) {
            .number => if (l.isInteger(i)) {
                try stdout.print("{d}", .{l.toInteger(i) catch unreachable});
            } else {
                try stdout.print("{d}", .{l.toNumber(i) catch unreachable});
            },
            .string => try stdout.print("{s}", .{l.toString(i) catch unreachable}),
            .nil => try stdout.print("nil", .{}),
            .boolean => try stdout.print("{s}", .{if (l.toBoolean(i)) "true" else "false"}),
            else => try stdout.print("{s}", .{l.toStringEx(i)}),
        }
        try stdout.writeAll(if (i != n) "\t" else "\n");
    }
}

fn __cancel(l: *Lua) i32 {
    const self = l.checkUserdata(Cli, 1, "seamstress.cli");
    if (!self.running) return 0;
    self.running = false;
    const seamstress = lu.getSeamstress(l);
    l.pushValue(1);
    const handle = l.ref(ziglua.registry_index) catch l.raiseErrorStr("unable to register CLI!", .{});
    self.c_c = .{
        .op = .{ .cancel = .{ .c = &self.c } },
        .userdata = lu.ptrFromHandle(handle),
        .callback = lu.unrefCallback,
    };
    seamstress.loop.add(&self.c_c);
    return 0;
}

fn __gc(l: *Lua) i32 {
    const self = l.checkUserdata(Cli, 1, "seamstress.cli");
    self.buffer.deinit(lu.allocator(l));
    return 0;
}

fn __index(l: *Lua) i32 {
    const cli = l.toUserdata(Cli, 1) catch unreachable;
    _ = l.pushStringZ("running");
    if (l.compare(-1, 2, .eq)) {
        l.pushBoolean(cli.running);
        return 1;
    }
    l.argError(2, "\"running\" expected");
}

fn __newindex(l: *Lua) i32 {
    const cli = l.toUserdata(Cli, 1) catch unreachable;
    _ = l.pushStringZ("running");
    if (l.compare(-1, 2, .eq)) {
        const running = l.toBoolean(3);
        if (!cli.running and running) {
            cli.running = true;
            l.pushValue(1);
            setup(l) catch l.raiseErrorStr("unable to start CLI!", .{});
        } else if (cli.running and !running) {
            cli.running = false;
            l.pushFunction(ziglua.wrap(__cancel));
            l.pushValue(1);
            l.call(1, 0);
        }
        return 0;
    }
    l.argError(2, "\"running\" expected");
}

const logger = std.log.scoped(.cli);

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const xev = @import("xev");
const lu = @import("lua_util.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Stdin = @import("cli/stdin.zig");
const builtin = @import("builtin");
