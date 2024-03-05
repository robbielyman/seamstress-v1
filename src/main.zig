const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const Seamstress = @import("seamstress.zig");
const Io = @import("io.zig");

// since this is called by logFn, global state is unavoidable
// defaults to using the CLI writing capabilities
// but is replaced by the TUI when enabled
// pub so that it can be altered in tui.zig
pub var logWriter: ?std.io.AnyWriter = null;

// single source of truth about seamstress's version
// pub so that it can be exposed to lua / printed
pub const VERSION: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha-0",
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
    // mutexes for IO
    var io: Io = .{};
    // CLI IO interface
    var clio = cli.Clio.init(&io);
    // sets up global state
    logWriter = clio.stderr.writer().any();

    // TODO: is GPA the best for the Lua VM?
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // TODO: does this really need to be on the heap just to have a stable pointer?
    // not a big deal either way for one struct
    var seamstress = Seamstress.create(&allocator, &io, &clio);
    // interestingly: in release modes this is never called by the magic of cleanExit
    defer allocator.destroy(seamstress);

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
