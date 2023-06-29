const std = @import("std");
const builtin = @import("builtin");
const args = @import("args.zig");
const spindle = @import("spindle.zig");
const events = @import("events.zig");
const metros = @import("metros.zig");
const clocks = @import("clock.zig");
const osc = @import("serialosc.zig");
const input = @import("input.zig");
const screen = @import("screen.zig");
const midi = @import("midi.zig");

const VERSION = .{ .major = 0, .minor = 12, .patch = 4 };

pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = log;
};

var start_time: i64 = undefined;

var logfile: std.fs.File = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    start_time = std.time.milliTimestamp();
    var loc_buf = [_]u8{0} ** 1024;
    const location = try std.fs.selfExeDirPath(&loc_buf);
    const logger = std.log.scoped(.main);
    try args.parse();
    logfile = try std.fs.createFileAbsolute("/tmp/seamstress.log", .{});
    defer logfile.close();
    try print_version();

    var general_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = general_allocator.allocator();
    defer _ = general_allocator.deinit();

    const path = try std.fs.path.join(allocator, &.{ location, "..", "share", "seamstress", "lua" });
    defer allocator.free(path);
    var pref_buf = [_]u8{0} ** 1024;
    const prefix = try std.fs.realpath(path, &pref_buf);
    defer logger.info("seamstress shutdown complete", .{});
    const config = std.process.getEnvVarOwned(allocator, "SEAMSTRESS_CONFIG") catch |err| blk: {
        if (err == std.process.GetEnvVarOwnedError.EnvironmentVariableNotFound) {
            break :blk try std.fs.path.join(allocator, &.{ prefix, "config.lua" });
        } else return err;
    };
    defer allocator.free(config);

    logger.info("init events", .{});
    try events.init(allocator);
    defer events.deinit();

    logger.info("init metros", .{});
    try metros.init(allocator);
    defer metros.deinit();

    logger.info("init clocks", .{});
    try clocks.init(allocator);
    defer clocks.deinit();

    logger.info("init spindle", .{});
    try spindle.init(prefix, config, allocator);
    defer spindle.deinit();

    logger.info("init MIDI", .{});
    try midi.init(allocator);
    defer midi.deinit();

    logger.info("init osc", .{});
    try osc.init(args.local_port, allocator);
    defer osc.deinit();

    logger.info("init input", .{});
    try input.init(allocator);
    defer input.deinit();
    // try if (args.curses) curses.init(allocator) else input.init(allocator);
    // defer if (args.curses) curses.deinit() else input.deinit();

    logger.info("init screen", .{});
    const width = try std.fmt.parseUnsigned(u16, args.width, 10);
    const height = try std.fmt.parseUnsigned(u16, args.height, 10);
    const assets_path = try std.fs.path.join(allocator, &.{ location, "..", "share", "seamstress", "resources" });
    defer allocator.free(assets_path);
    var assets_buf = [_]u8{0} ** 1024;
    const assets = try std.fs.realpath(assets_path, &assets_buf);
    try screen.init(allocator, width, height, assets);
    defer screen.deinit();

    logger.info("handle events", .{});
    try events.handle_pending();

    logger.info("spinning spindle", .{});
    try spindle.startup(args.script_file);

    logger.info("entering main loop", .{});
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
    const scope_prefix = "(" ++ @tagName(scope) ++ ") ";
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
    const writer = logfile.writer();
    const timestamp = std.time.milliTimestamp() - start_time;
    writer.print(prefix ++ "+{d}: " ++ format ++ "\n", .{timestamp} ++ log_args) catch return;
}
