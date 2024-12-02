pub fn main() !void {
    // logging
    const logfile = try std.fs.cwd().createFile("/tmp/seamstress.log", .{});
    var bw = std.io.bufferedWriter(logfile.writer());
    defer bw.flush() catch {};
    log_writer = bw.writer().any();

    // allocation
    var gpa: if (builtin.mode == .Debug) std.heap.GeneralPurposeAllocator(.{}) else void = if (builtin.mode == .Debug) .{};
    defer {
        if (builtin.mode == .Debug) _ = gpa.deinit();
    }
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;

    // arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    maybePrintSweetNothingsAndExit(args);
    const filename: ?[:0]const u8 = if (args.len > 1) args[1] else null;

    // lua files prefix
    const lua_files_path = lua_files_path: {
        const location = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(location);
        const path = std.process.getEnvVarOwned(allocator, "SEAMSTRESS_LUA_PATH") catch
            try std.fs.path.joinZ(allocator, &.{ location, "..", "share", "seamstress", "lua" });
        defer allocator.free(path);
        break :lua_files_path std.fs.realpathAlloc(allocator, path) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print(
                    \\unable to normalize given path: "{s}"
                    \\define $SEAMSTRESS_LUA_PATH to overwrite and try again
                    \\
                , .{path});
                std.process.exit(1);
            } else return err;
        };
    };
    defer allocator.free(lua_files_path);

    // handle SIGABRT (called by lua in Debug mode)
    const act: if (builtin.mode == .Debug) std.posix.Sigaction = if (builtin.mode == .Debug) .{
        .handler = .{
            .handler = struct {
                fn handleAbrt(_: c_int) callconv(.C) noreturn {
                    @call(.always_inline, std.debug.panic, .{ "abort called!", .{} });
                }
            }.handleAbrt,
        },
        .mask = if (builtin.os.tag == .linux) std.posix.empty_sigset else 0,
        .flags = 0,
    };
    if (builtin.mode == .Debug) try std.posix.sigaction(std.posix.SIG.ABRT, &act, null);

    var seamstress = try Seamstress.init(&allocator, &bw, lua_files_path);

    panic_closure = .{
        .ctx = &seamstress,
        .panic_fn = Seamstress.panicCleanup,
    };

    try seamstress.run(filename);
}

/// if we get an agrument starting with -h, --h, -v or --v, print usage and exit
fn maybePrintSweetNothingsAndExit(args: []const []const u8) void {
    const needles: []const []const u8 = &.{ "-h", "--h", "--v", "-v" };
    blk: {
        for (args) |arg| {
            for (needles) |needle| if (std.mem.startsWith(u8, arg, needle)) break :blk;
        }
        return;
    }
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print(
        \\SEAMSTRESS
        \\seamstress version: {}
        \\seamstress is an art engine,
        \\usage: seamstress [script_file_name]
        \\goodbye.
        \\
    , .{Seamstress.version}) catch {};
    bw.flush() catch {};
    std.process.exit(0);
}

// used by logFn (called by std.log), so global state is unavoidable
var log_writer: ?std.io.AnyWriter = null;

pub const std_options: std.Options = .{
    .logFn = struct {
        fn logFn(
            comptime level: std.log.Level,
            comptime scope: @TypeOf(.enum_literal),
            comptime fmt: []const u8,
            args: anytype,
        ) void {
            const w = log_writer orelse return;
            const prefix = "[" ++ @tagName(scope) ++ "]" ++ " (" ++ comptime level.asText() ++ "): ";
            w.print(prefix ++ fmt ++ "\n", args) catch {};
        }
    }.logFn,
    .log_level = switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => .warn,
        .Debug, .ReleaseSafe => .debug,
    },
};

// used by std.debug.panic, so global state is unavoidable
var panic_closure: ?struct {
    ctx: *Seamstress,
    panic_fn: *const fn (*Seamstress) void,
} = null;

// allows us to shut down cleanly when panicking
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (panic_closure) |p| {
        panic_closure = null;
        p.panic_fn(p.ctx);
    }
    // inline so that stack traces are correct
    @call(.always_inline, std.builtin.default_panic, .{ msg, error_return_trace, ret_addr });
}

const std = @import("std");
const builtin = @import("builtin");
const Seamstress = @import("seamstress.zig");

test "ref" {
    _ = Seamstress;
}
