/// entry point!
pub fn main() void {
    // grab stderr
    const stderr = std.io.getStdErr().writer().any();
    // buffer it—allows us to redirect but also print only when we're ready to.
    var buffered_stderr = std.io.bufferedWriter(stderr);
    // set up logging
    log_writer = buffered_stderr.writer().any();

    // TODO: is the GPA best for seamstress?
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer {
        // in case we leaked memory, let's log it to stderr on exit
        log_writer = std.io.getStdErr().writer().any();
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

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
    // initialize
    seamstress.init(&allocator, &buffered_stderr);

    // ensures that we clean things up however we panic
    panic_closure = .{
        .ctx = &seamstress,
        .panic_fn = Seamstress.panicCleanup,
    };
    // gooooooooo
    seamstress.run();
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

fn handleAbrt(_: c_int) callconv(.C) noreturn {
    @call(.always_inline, std.debug.panic, .{ "assertion failed!!", .{} });
}

const std = @import("std");
const builtin = @import("builtin");
const Seamstress = @import("seamstress.zig");
