const std = @import("std");
const events = @import("events.zig");
pub const c = @import("readline.zig");

var quit = false;
pub var readline = true;
var pid: std.Thread = undefined;
var buffer: [32 * 1024]u8 = undefined;
const logger = std.log.scoped(.input);

pub fn init() !void {
    quit = false;
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var alloc = fba.allocator();
    const term = std.process.getEnvVarOwned(alloc, "TERM") catch |err| blk: {
        switch (err) {
            error.EnvironmentVariableNotFound => break :blk try alloc.dupe(u8, "nuttin"),
            else => return err,
        }
    };
    defer alloc.free(term);
    if (std.mem.eql(u8, term, "emacs") or std.mem.eql(u8, term, "dumb")) {
        readline = false;
        pid = try std.Thread.spawn(.{}, bare_input_run, .{});
    } else {
        try input_run();
    }
}

pub fn deinit() void {
    quit = true;
    const newstdin = std.posix.dup(std.io.getStdIn().handle) catch unreachable;
    std.io.getStdIn().close();
    pid.detach();
    if (readline) write_history();
    std.posix.dup2(newstdin, 0) catch unreachable;
}

fn write_history() void {
    var buf: [2 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = fba.allocator();
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return;
    const history_file = std.fs.path.joinZ(allocator, &.{ home, "seamstress_history" }) catch return;
    _ = c.write_history(history_file.ptr);
    _ = c.history_truncate_file(history_file.ptr, 500);
    allocator.free(history_file);
    allocator.free(home);
}

fn input_run() !void {
    var buf: [2 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = fba.allocator();
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
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    pid.setName("input_thread") catch {};
    while (!quit) {
        const c_line = c.readline("> ") orelse {
            quit = true;
            continue;
        };
        const line = try std.fmt.allocPrintZ(allocator, "{s}\n", .{c_line});
        if (std.mem.eql(u8, line, "quit\n")) {
            quit = true;
            allocator.free(line);
            std.heap.raw_c_allocator.free(std.mem.span(c_line));
            continue;
        }
        _ = c.add_history(c_line);
        events.post(.{ .Exec_Code_Line = .{ .line = line, .allocator = allocator } });
    }
    events.post(.{ .Quit = {} });
}

fn bare_input_run() !void {
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();
    pid.setName("input_thread") catch {};
    var stdin = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var fds = [1]std.posix.pollfd{
        .{ .fd = std.io.getStdIn().handle, .events = std.posix.POLL.IN, .revents = 0 },
    };
    try stdout.print("> ", .{});
    var buf: [1024]u8 = undefined;
    while (!quit) {
        const data = try std.posix.poll(&fds, 1);
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
        events.post(.{ .Exec_Code_Line = .{ .line = line, .allocator = allocator } });
    }
    events.post(.{ .Quit = {} });
}
