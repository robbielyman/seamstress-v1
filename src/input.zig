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
    allocator = allocator_pointer;
    const term = std.os.getenv("TERM") orelse "";
    if (std.mem.eql(u8, term, "emacs") or std.mem.eql(u8, term, "dumb")) {
        readline = false;
        pid = try std.Thread.spawn(.{}, bare_input_run, .{});
    } else {
        pid = try std.Thread.spawn(.{}, input_run, .{});
    }
}

pub fn deinit() void {
    quit = true;
    std.io.getStdIn().close();
    pid.join();
}

fn input_run() !void {
    _ = c.rl_initialize();
    c.rl_prep_terminal(1);
    defer c.rl_deprep_terminal();
    c.using_history();
    c.stifle_history(500);
    const home = std.os.getenv("HOME");
    var history_file: []u8 = undefined;
    if (home) |h| {
        history_file = try std.fmt.allocPrintZ(allocator, "{s}/.seamstress_history", .{h});
        const file = try std.fs.createFileAbsolute(history_file, .{ .read = true, .truncate = false });
        file.close();
        _ = c.read_history(history_file.ptr);
    } else {
        logger.warn("unable to capture $HOME, history will not be saved!", .{});
    }
    defer if (home) |_| {
        _ = c.write_history(history_file.ptr);
        _ = c.history_truncate_file(history_file.ptr, 500);
        allocator.free(history_file);
    };
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
    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var fds = [1]std.os.pollfd{
        .{ .fd = 0, .events = std.os.POLL.IN, .revents = 0 },
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
