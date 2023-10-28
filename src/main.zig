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
const socket = @import("socket.zig");
const watcher = @import("watcher.zig");
const create = @import("create.zig");
const pthread = @import("pthread.zig");

const VERSION = .{ .major = 1, .minor = 0, .patch = 4 };

pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = log;
};

var timer: std.time.Timer = undefined;

var logfile: std.fs.File = undefined;
var main_thread: std.Thread = undefined;

pub fn main() !void {
    var go_again = true;
    timer = try std.time.Timer.start();

    var loc_buf = [_]u8{0} ** std.fs.MAX_PATH_BYTES;
    const location = try std.fs.selfExeDirPath(&loc_buf);

    const option = try args.parse(location);

    logfile = try std.fs.createFileAbsolute("/tmp/seamstress.log", .{});
    defer logfile.close();
    const logger = std.log.scoped(.app);

    if (option) |opt| try create.init(opt, location);
    defer if (option) |_| create.deinit();
    while (go_again) {
        var buf: [8 * 1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        var allocator = fba.allocator();
        if (!args.quiet) try print_version();
        const path = try std.fs.path.joinZ(allocator, &.{ location, "..", "share", "seamstress", "lua" });
        defer allocator.free(path);
        const prefix = try std.fs.realpathAlloc(allocator, path);
        defer allocator.free(prefix);
        defer logger.info("seamstress shutdown complete", .{});
        const config = std.process.getEnvVarOwned(allocator, "SEAMSTRESS_CONFIG") catch |err| blk: {
            if (err == std.process.GetEnvVarOwnedError.EnvironmentVariableNotFound) {
                break :blk try std.fs.path.join(allocator, &.{ prefix, "config.lua" });
            } else return err;
        };
        defer allocator.free(config);

        logger.info("init events", .{});
        try events.init();
        defer events.deinit();

        logger.info("init metros", .{});
        try metros.init(timer);
        defer metros.deinit();

        logger.info("init clocks", .{});
        try clocks.init(timer);
        defer clocks.deinit();

        logger.info("init spindle", .{});
        try spindle.init(prefix, config, timer);

        logger.info("init MIDI", .{});
        try midi.init();
        defer midi.deinit();

        logger.info("init osc", .{});
        try osc.init(args.local_port);
        defer osc.deinit();

        logger.info("init input", .{});
        try input.init();
        defer input.deinit();

        logger.info("init socket", .{});
        const sock = try std.fmt.parseUnsigned(u16, args.socket_port, 10);
        try socket.init(sock);
        defer socket.deinit();

        logger.info("init screen", .{});
        const width = try std.fmt.parseUnsigned(u16, args.width, 10);
        const height = try std.fmt.parseUnsigned(u16, args.height, 10);
        const assets_path = try std.fs.path.join(allocator, &.{ location, "..", "share", "seamstress", "resources" });
        defer allocator.free(assets_path);
        var assets_buf = [_]u8{0} ** std.fs.MAX_PATH_BYTES;
        const assets = try std.fs.realpath(assets_path, &assets_buf);
        try screen.init(width, height, assets);
        defer screen.deinit();

        main_thread = try std.Thread.spawn(.{}, inner, .{&go_again});
        defer main_thread.join();

        screen.loop();
    }
    std.io.getStdIn().close();
    if (!args.quiet) try print_goodbye();
    std.io.getStdOut().close();
}

fn print_goodbye() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("SEAMSTRESS: goodbye\n", .{});
    try bw.flush();
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
    const timestamp = @divTrunc(timer.read(), std.time.ns_per_us);
    writer.print(prefix ++ "+{d}: " ++ format ++ "\n", .{timestamp} ++ log_args) catch return;
}

fn inner(go_again: *bool) !void {
    main_thread.setName("seamstress_core") catch {};
    const logger = std.log.scoped(.main);
    pthread.set_priority(99);

    logger.info("handle events", .{});
    try events.handle_pending();

    logger.info("spinning spindle", .{});
    var buf: [1024]u8 = undefined;
    const filepath = try spindle.startup(args.script_file, &buf);

    if (args.watch and filepath != null) {
        logger.info("watching {s}", .{filepath.?});
        try watcher.init(filepath.?);
    }

    logger.info("entering main loop", .{});
    go_again.* = try events.loop();
    screen.quit = true;

    defer spindle.deinit();
    defer if (args.watch and filepath != null) watcher.deinit();
}
