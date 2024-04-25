const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const Seamstress = @import("seamstress.zig");
const Io = @import("io.zig");

// since this is called by logFn, global state is unavoidable.
// only modified (or even available) in this file, which feels like a win
var logWriter: ?std.io.AnyWriter = null;

// since this is called by std.debug.panic, global state is unavoidable.
var panic_closure: ?struct {
    ctx: *Seamstress,
    panic_fn: *const fn (*Seamstress) void,
} = null;

// single source of truth about seamstress's version
// pub so that it can be exposed to lua / printed
pub const VERSION: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha-1",
};

// allows functions under std.log (like each file's logger) to use our logging function
// pub so that std.log can find it
pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => .warn,
        .Debug, .ReleaseSafe => .debug,
    },
};

// entry point!
pub fn main() void {
    // grab stderr
    const stderr = std.io.getStdErr().writer().any();
    // set up mutexes for IO
    var io = Io.init(stderr);
    // sets up global state---only modified here, thanks to Io.replaceUnderlyingStream.
    logWriter = io.stderr.writer().any();

    // TODO: is GPA the best for the Lua VM?
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer {
        // in case we leaked memory, better not to crash about it
        logWriter = stderr;
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    // stack-allocated, baby!
    var seamstress: Seamstress = undefined;
    // initialize
    seamstress.init(&allocator, &io);

    // set up our special panic
    panic_closure = .{
        .ctx = &seamstress,
        .panic_fn = Seamstress.panicCleanup,
    };

    // gooooo
    seamstress.run();
}

// TODO: write more tests!
test "refAllDecls" {
    std.testing.refAllDeclsRecursive(@This());
}

// pretty basic logging function; called by std.log functions
// could get fancier by selectively enabling more verbose logging?
// could stand to write more logging statements too tho
fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const w = logWriter orelse return;
    const prefix = "[" ++ @tagName(scope) ++ "] " ++ "(" ++ comptime level.asText() ++ "): ";
    w.print(prefix ++ fmt ++ "\n", args) catch return;
}

// allows us to always shut down cleanly when panicking
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (panic_closure) |p| {
        p.panic_fn(p.ctx);
    }
    @call(.always_inline, std.builtin.default_panic, .{ msg, error_return_trace, ret_addr });
}
