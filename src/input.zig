const std = @import("std");
const events = @import("events.zig");
pub const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
});

var quit = false;
pub var readline = true;
var pid: std.Thread = undefined;
var allocator: std.mem.Allocator = undefined;
const logger = std.log.scoped(.input);

pub fn init(allocator_pointer: std.mem.Allocator) !void {
    quit = false;
    allocator = allocator_pointer;
    const term = std.process.getEnvVarOwned(allocator, "TERM") catch |err| blk: {
        switch (err) {
            error.EnvironmentVariableNotFound => break :blk try allocator.dupe(u8, "nuttin"),
            else => return err,
        }
    };
    defer allocator.free(term);
    if (std.mem.eql(u8, term, "emacs") or std.mem.eql(u8, term, "dumb")) {
        readline = false;
        pid = try std.Thread.spawn(.{}, bare_input_run, .{});
    } else {
        try input_run();
    }
}

pub fn deinit() void {
    quit = true;
    const newstdin = std.os.dup(std.io.getStdIn().handle) catch unreachable;
    std.io.getStdIn().close();
    pid.detach();
    if (readline) write_history();
    std.os.dup2(newstdin, 0) catch unreachable;
}

fn write_history() void {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return;
    const history_file = std.fs.path.joinZ(allocator, &.{ home, "seamstress_history" }) catch return;
    _ = c.write_history(history_file.ptr);
    _ = c.history_truncate_file(history_file.ptr, 500);
    allocator.free(history_file);
    allocator.free(home);
}

fn input_run() !void {
    _ = c.rl_initialize();
    c.rl_prep_terminal(1);
    c.using_history();
    c.stifle_history(500);
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch home: {
        logger.warn("unable to capture $HOME, history will not be saved!", .{});
        break :home null;
    };
    if (home) |h| {
        const history_file = try std.fs.path.joinZ(allocator, &.{ h, "seamstress_history" });
        const file = try std.fs.createFileAbsolute(history_file, .{ .read = true, .truncate = false });
        file.close();
        _ = c.read_history(history_file.ptr);
        allocator.free(history_file);
        allocator.free(h);
    }
    pid = try std.Thread.spawn(.{}, inner, .{});
}

fn inner() !void {
    pid.setName("input_thread") catch {};
    while (!quit) {
        var c_line = c.readline("> ") orelse {
            quit = true;
            continue;
        };
        const line = try std.fmt.allocPrintZ(allocator, "{s}\n", .{c_line});
        if (std.mem.eql(u8, line, "quit\n")) {
            quit = true;
            allocator.free(line);
            c.free(c_line);
            continue;
        }
        _ = c.add_history(c_line);
        const event = .{ .Exec_Code_Line = .{ .line = line } };
        events.post(event);
    }
    events.post(.{ .Quit = {} });
}

fn bare_input_run() !void {
    pid.setName("input_thread") catch {};
    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var fds = [1]std.os.pollfd{
        .{ .fd = std.io.getStdIn().handle, .events = std.os.POLL.IN, .revents = 0 },
    };
    try stdout.print("> ", .{});
    var buf: [1024]u8 = undefined;
    while (!quit) {
        const data = try std.os.poll(&fds, 1);
        if (data == 0) continue;
        const len = stdin.read(&buf) catch break;
        if (len == 0) break;
        if (len >= buf.len - 1) {
            std.debug.print("error: line too long!\n", .{});
            continue;
        }
        const line: [:0]u8 = try allocator.dupeZ(u8, buf[0..len]);
        if (std.mem.eql(u8, line, "quit\n")) {
            allocator.free(line);
            quit = true;
            continue;
        }
        const event = .{
            .Exec_Code_Line = .{ .line = line },
        };
        events.post(event);
    }
    events.post(.{ .Quit = {} });
}
