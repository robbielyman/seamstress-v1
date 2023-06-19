const std = @import("std");
const builtin = @import("builtin");
const args = @import("args.zig");
const spindle = @import("spindle.zig");
const events = @import("events.zig");
const metros = @import("metros.zig");
const clocks = @import("clock.zig");
const osc = @import("serialosc.zig");
const input = @import("input.zig");
const curses = @import("curses.zig");
const screen = @import("screen.zig");
const midi = @import("midi.zig");
const c = @import("c_includes.zig").imported;

const VERSION = .{ .major = 0, .minor = 9, .patch = 1 };

pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = log;
};

var logfile: std.fs.File = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    try args.parse();
    if (!args.curses) {
        logfile = try std.fs.createFileAbsolute("/tmp/seamstress.log", .{});
    }
    defer if (!args.curses) logfile.close();
    try print_version();

    defer std.log.info("seamstress shutdown complete", .{});

    var general_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = general_allocator.allocator();
    defer _ = general_allocator.deinit();

    var allocated = true;
    const config = std.process.getEnvVarOwned(allocator, "SEAMSTRESS_CONFIG") catch |err| blk: {
        if (err == std.process.GetEnvVarOwnedError.EnvironmentVariableNotFound) {
            allocated = false;
            break :blk "'/usr/local/share/seamstress/lua/config.lua'";
        } else {
            return err;
        }
    };
    defer if (allocated) allocator.free(config);

    std.log.info("init events", .{});
    try events.init(allocator);
    defer events.deinit();

    std.log.info("init metros", .{});
    try metros.init(allocator);
    defer metros.deinit();

    std.log.info("init clocks", .{});
    try clocks.init(allocator);
    defer clocks.deinit();

    std.log.info("init spindle", .{});
    try spindle.init(config, allocator);
    defer spindle.deinit();

    std.log.info("init MIDI", .{});
    try midi.init(allocator);
    defer midi.deinit();

    std.log.info("init osc", .{});
    try osc.init(args.local_port, allocator);
    defer osc.deinit();

    std.log.info("init input", .{});
    try if (args.curses) curses.init(allocator) else input.init(allocator);
    defer if (args.curses) curses.deinit() else input.deinit();

    std.log.info("init screen", .{});
    const width = try std.fmt.parseUnsigned(u16, args.width, 10);
    const height = try std.fmt.parseUnsigned(u16, args.height, 10);
    try screen.init(width, height);
    defer screen.deinit();

    std.log.info("handle events", .{});
    try events.handle_pending();

    std.log.info("spinning spindle", .{});
    try spindle.startup(args.script_file);

    std.log.info("entering main loop", .{});
    try events.loop();
}

fn print_version() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("SEAMSTRESS\n", .{});
    try stdout.print("seamstress version: {d}.{d}.{d}\n", VERSION);
    try bw.flush();
}

fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    log_args: anytype,
) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
    if (args.curses) {
        const writer = logfile.writer();
        var line = std.fmt.allocPrint(allocator, prefix ++ format ++ "\n", log_args) catch return;
        defer allocator.free(line);
        _ = writer.write(line) catch return;
    } else {
        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();
        const stderr = std.io.getStdErr().writer();
        stderr.print(format ++ "\n\r", log_args) catch return;
    }
}
