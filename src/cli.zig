const Cli = @This();
const max_input_len = 2 * 1024;

buffer: std.ArrayList(u8),
c: xev.Completion = .{},
c_c: xev.Completion = .{},
file: xev.File,

/// creates the input buffer and xev.File associated to this struct
pub fn init(allocator: std.mem.Allocator) !Cli {
    return .{
        .buffer = std.ArrayList(u8).init(allocator),
        .file = try xev.File.init(std.io.getStdIn()),
    };
}

/// reads from the xev.File by using the event loop
pub fn setup(self: *Cli) !void {
    try self.buffer.ensureUnusedCapacity(max_input_len);
    const seamstress: *Seamstress = @fieldParentPtr("cli", self);
    self.file.read(&seamstress.loop, &self.c, .{
        .slice = self.buffer.unusedCapacitySlice(),
    }, Cli, self, struct {
        fn stdinCallback(
            m_cli: ?*Cli,
            loop: *xev.Loop,
            c: *xev.Completion,
            file: xev.File,
            _: xev.ReadBuffer,
            r: xev.ReadError!usize,
        ) xev.CallbackAction {
            const cli = m_cli.?;
            const s: *Seamstress = @fieldParentPtr("cli", cli);
            const length = r catch |err| {
                if (err != error.Canceled or err != error.EOF)
                    logger.err("error reading from stdin! {s}", .{@errorName(err)});
                if (err == error.EOF)
                    lu.quit(s.lua);
                return .disarm;
            };
            cli.buffer.items.len += length;
            if (std.mem.eql(u8, "quit\n", cli.buffer.items)) {
                lu.quit(s.lua);
                return .disarm;
            }
            var buf = std.io.bufferedWriter(std.io.getStdOut().writer());
            const stdout = buf.writer();
            const was_complete = lu.processChunk(s.lua, cli.buffer.items) catch blk: {
                stdout.writeAll(s.lua.toString(-1) catch unreachable) catch |err| {
                    logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                    s.lua.setTop(0);
                    return .disarm;
                };
                break :blk true;
            };
            defer s.lua.setTop(0);
            if (was_complete) {
                cli.buffer.clearRetainingCapacity();
                const n = s.lua.getTop();
                var i: i32 = 1;
                while (i <= n) : (i += 1) {
                    switch (s.lua.typeOf(i)) {
                        .number => if (s.lua.isInteger(i)) {
                            stdout.print("{d}", .{s.lua.toInteger(i) catch unreachable}) catch |err| {
                                logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                                return .disarm;
                            };
                        } else {
                            stdout.print("{d}", .{s.lua.toNumber(i) catch unreachable}) catch |err| {
                                logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                                return .disarm;
                            };
                        },
                        .string => stdout.print("{s}", .{s.lua.toString(i) catch unreachable}) catch |err| {
                            logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                            return .disarm;
                        },
                        .nil => stdout.print("nil", .{}) catch |err| {
                            logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                            return .disarm;
                        },
                        .boolean => stdout.print("{s}", .{if (s.lua.toBoolean(i)) "true" else "false"}) catch |err| {
                            logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                            return .disarm;
                        },
                        else => stdout.print("{s}", .{s.lua.toStringEx(i)}) catch |err| {
                            logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                            return .disarm;
                        },
                    }
                    stdout.writeAll(if (i != n) "\t" else "\n") catch |err| {
                        logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                        return .disarm;
                    };
                }
            }
            stdout.writeAll(if (was_complete) "> " else ">... ") catch |err| {
                logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                return .disarm;
            };
            buf.flush() catch |err| {
                logger.err("unable to write to stdout! {s}", .{@errorName(err)});
                return .disarm;
            };
            cli.buffer.ensureUnusedCapacity(max_input_len) catch
                logger.warn("out of memory; unable to grow input buffer!", .{});
            file.read(loop, c, .{
                .slice = cli.buffer.unusedCapacitySlice(),
            }, Cli, cli, @This().stdinCallback);
            return .disarm;
        }
    }.stdinCallback);
    seamstress.lua.pushLightUserdata(self);
    seamstress.lua.pushClosure(ziglua.wrap(struct {
        fn f(l: *Lua) i32 {
            const i = Lua.upvalueIndex(1);
            const cli = l.toUserdata(Cli, i) catch unreachable;
            cli.cancel();
            return 0;
        }
    }.f), 1);
    lu.addExitHandler(seamstress.lua, .quit);
}

/// stops reading from stdin
/// pub so that (for example) the TUI library can find it
pub fn cancel(self: *Cli) void {
    const seamstress: *Seamstress = @fieldParentPtr("cli", self);
    self.c_c = .{
        .op = .{ .cancel = .{ .c = &self.c } },
        .callback = xev.noopCallback,
    };
    seamstress.loop.add(&self.c_c);
}

/// frees buffer memory
pub fn deinit(self: *Cli) void {
    self.buffer.deinit();
}

const logger = std.log.scoped(.cli);

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const xev = @import("xev");
const lu = @import("lua_util.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
