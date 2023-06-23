const std = @import("std");
const events = @import("events.zig");
pub const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
});

var quit = false;
var pid: std.Thread = undefined;
var allocator: std.mem.Allocator = undefined;
const logger = std.log.scoped(.input);

pub fn init(allocator_pointer: std.mem.Allocator) !void {
    allocator = allocator_pointer;
    pid = try std.Thread.spawn(.{}, input_run, .{});
}

pub fn deinit() void {
    quit = true;
    std.io.getStdIn().close();
    pid.join();
}

fn input_run() !void {
    c.using_history();
    c.stifle_history(500);
    var buf: [1024]u8 = undefined;
    const slice = try std.fs.selfExeDirPath(&buf);
    std.debug.print("{s}\n", .{slice});
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
    // var stdout = std.io.getStdOut().writer();
    // _ = stdout;
    // var fds = [1]std.os.pollfd{
    //     .{ .fd = 0, .events = std.os.POLL.IN, .revents = 0 },
    // };
    // try set_signal();
    while (!quit) {
        // const data = try std.os.poll(&fds, 1);
        // if (data == 0) continue;
        var c_line = c.readline("> ") orelse {
            quit = true;
            continue;
        };
        c.add_history(c_line);
        const line = try std.fmt.allocPrintZ(allocator, "{s}\n", .{c_line});
        if (std.mem.eql(u8, line, "quit\n")) {
            quit = true;
            allocator.free(line);
            continue;
        }
        // const len = stdin.read(buf) catch break;
        // if (len == 0) break;
        // if (len >= buf.len - 1) {
        //     try stdout.print("error: line too long!\n", .{});
        //     continue;
        // }
        // var line: [:0]u8 = try allocator.allocSentinel(u8, len, 0);
        // std.mem.copyForwards(u8, line, buf[0..len]);
        // if (std.mem.eql(u8, line, "quit\n")) {
        //     allocator.free(line);
        //     quit = true;
        //     continue;
        // }
        const event = .{ .Exec_Code_Line = .{ .line = line } };
        events.post(event);
    }
    events.post(.{ .Quit = {} });
}

// fn set_signal() !void {
//     try std.os.sigaction(
//         std.os.SIG.INT,
//         &.{
//             .handler = .{ .handler = signal_handler },
//             .mask = std.os.SIG.INT,
//             .flags = 0,
//         },
//         null,
//     );
// }
//
// fn signal_handler(signal: c_int) callconv(.C) void {
//     _ = signal;
//     // _ = c.rl_abort(0, 0);
//     events.post(.{ .Quit = {} });
// }
