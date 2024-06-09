/// entry point!
pub fn main() void {
    const logfile: ?std.fs.File = std.fs.cwd().createFile("/tmp/seamstress.log", .{}) catch blk: {
        std.debug.print("unable to open a log file! logging will be disabled!!", .{});
        std.time.sleep(std.time.ns_per_s / 2);
        break :blk null;
    };
    var bw: ?std.io.BufferedWriter(4096, std.io.AnyWriter) = null;
    if (logfile) |f| {
        bw = std.io.bufferedWriter(f.writer().any());
        // set up logging
        log_writer = bw.?.writer().any();
    }

    // TODO: is the GPA best for seamstress?
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer {
        // in case we leaked memory, let's log it to stderr on exit
        log_writer = std.io.getStdErr().writer().any();
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch @panic("out of memory!");
    defer std.process.argsFree(allocator, args);

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-v") or std.mem.startsWith(u8, arg, "--v") or std.mem.startsWith(u8, arg, "-h") or std.mem.startsWith(u8, arg, "--h"))
            printSweetNothingsAndExit();
    }

    var act: std.posix.Sigaction = .{
        .handler = .{ .handler = handleAbrt },
        .mask = switch (builtin.os.tag) {
            .macos => 0,
            .linux => std.posix.empty_sigset,
            else => @compileError("os not supported"),
        },
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.ABRT, &act, null) catch @panic("not supported!");

    // stack-allocated, baby!
    var seamstress: Seamstress = undefined;
    var go_again = true;
    while (go_again) {
        // initialize
        seamstress.init(&allocator, if (bw) |*ptr| ptr else null);

        // ensures that we clean things up however we panic
        panic_closure = .{
            .ctx = &seamstress,
            .panic_fn = Seamstress.panicCleanup,
        };
        // gooooooooo
        seamstress.run();
        go_again = seamstress.go_again;
        seamstress.go_again = false;
    }
}

// since this is used by logFn (which is called by std.log), global state is unavoidable
var log_writer: ?std.io.AnyWriter = null;

// since this is called by std.debug.panic, global state is unavoidable.
var panic_closure: ?struct {
    ctx: *Seamstress,
    panic_fn: *const fn (*Seamstress) void,
} = null;

// pub so that std can find it
pub const std_options: std.Options = .{
    // allows functions under std.log to use our logging function
    .logFn = logFn,
    .log_level = switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => .warn,
        .Debug, .ReleaseSafe => .debug,
    },
};

// pretty basic logging function; called by std.log
fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const w = log_writer orelse return;
    const prefix = "[" ++ @tagName(scope) ++ "]" ++ "(" ++ comptime level.asText() ++ "): ";
    w.print(prefix ++ fmt ++ "\n", args) catch {};
}

// allows us to always shut down cleanly when panicking
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (panic_closure) |p| p.panic_fn(p.ctx);
    // inline so that the stack traces are correct
    @call(.always_inline, std.builtin.default_panic, .{ msg, error_return_trace, ret_addr });
}

// handles SIGABRT so that we get a stack trace when a Lua debug assertion fails
fn handleAbrt(_: c_int) callconv(.C) noreturn {
    @call(.always_inline, std.debug.panic, .{ "assertion failed!!", .{} });
}

// if we got an argument of -h or -v
fn printSweetNothingsAndExit() void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print(
        \\SEAMSTRESS
        \\seamstress version: {}
        \\seamstress is an art engine.
        \\usage: seamstress [script_file_name]
        \\goodbye.
        \\
    , .{Seamstress.version}) catch {};
    bw.flush() catch {};
    std.process.exit(0);
}

const std = @import("std");
const builtin = @import("builtin");
const Seamstress = @import("seamstress.zig");
