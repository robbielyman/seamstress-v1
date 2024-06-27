/// functions in this file set up, configure and run seamstress
/// the main players are the event loop, the lua VM and the modules
/// modules are passed the loop and the vm to register functions and events with each
const Seamstress = @This();

/// single source of truth about seamstress's version
/// makes more sense to put in this file rather than main.zig
pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha-4",
};

/// the seamstress loop
pub fn run(self: *Seamstress) !void {
    const io: []const []const u8 = &.{ "cli", "tui" };
    for (io) |str| {
        const m = self.module_list.get(str).?;
        if (m.self) |_| try m.launch(self.l, &self.loop);
    }
    // run the event loop; blocks until we exit
    try self.loop.run();
    self.deinit(self.loop.kind);
}

// a member function so that elements of this struct have a stable pointer
pub fn init(self: *Seamstress, allocator: *const std.mem.Allocator, logger: ?*BufferedWriter, script: ?[:0]const u8) void {
    self.allocator = allocator.*;
    self.logger = logger;
    // set up the event loop
    self.loop.init();
    // set up the lua vm
    self.module_list = Module.list(self.allocator) catch std.debug.panic("out of memory!", .{});
    spindle.init(allocator, self, script);
    // set up the REPL at a minimum
    const term = std.process.getEnvVarOwned(self.allocator, "TERM") catch {
        self.module_list.get("cli").?.init(self.l, self.allocator) catch |err| std.debug.panic("unable to start CLI I/O! {s}", .{@errorName(err)});
        @import("config.zig").configure(self);
        return;
    };
    defer self.allocator.free(term);
    const which = if (std.mem.startsWith(u8, term, "dumb") or std.mem.startsWith(u8, term, "emacs")) "cli" else "tui";
    self.module_list.get(which).?.init(self.l, self.allocator) catch |err| std.debug.panic("unable to start CLI I/O! {s}", .{@errorName(err)});
    @import("config.zig").configure(self);
}

/// cleanup done at panic
/// pub because it is called from main.zig
pub fn panicCleanup(self: *Seamstress) void {
    if (self.panicked) return;
    self.panicked = true;
    @setCold(true);
    // used to, e.g. turn off grid lights, so should be called here
    spindle.cleanup(self.l);
    // shut down modules
    for (self.module_list.values()) |module| {
        module.deinit(self.l, self.allocator, .panic);
    }
    // flush logs
    if (self.logger) |l| l.flush() catch {};
}

/// used by modules to determine what and how much to clean up.
/// panic: something has gone wrong; clean up the bare minimum so that seamstress is a good citizen
/// clean: we're exiting normally, but don't bother freeing memory
/// full: we're exiting normally, but clean up everything
pub const Cleanup = enum { panic, clean, full };

/// pub because it's called by the loop using @fieldParentPtr
/// returns true if seamstress should start again
pub fn deinit(self: *Seamstress, kind: Cleanup) void {
    self.loop.kind = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .full,
        .ReleaseFast, .ReleaseSmall => .clean,
    };
    // e.g. turns off grid lights
    spindle.cleanup(self.l);
    // shut down modules
    for (self.module_list.values()) |module| {
        module.deinit(self.l, self.allocator, kind);
    }
    // flush logs
    if (self.logger) |l| l.flush() catch {};
    // uses stdout to print because the UI module is shut down
    sayGoodbye();
    // if we're doing a clean exit, now is the time to quit
    if (kind == .clean) {
        std.process.cleanExit();
        return;
    }
    // closes the lua VM and frees memory
    self.l.close();
    // frees module memory
    for (self.module_list.values()) |ptr| self.allocator.destroy(ptr);
    self.module_list.deinit(self.allocator);
}

/// should always simply print to stdout
fn sayGoodbye() void {
    if (builtin.is_test) return;
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();
    stdout.print("goodbye\n", .{}) catch return;
    bw.flush() catch return;
}

// the lua VM
l: *Lua,
// the event loop
loop: Wheel,
// the "global" default allocator
allocator: std.mem.Allocator,
// attempt to avoid shutting things down twice
panicked: bool = false,
// logger from main
logger: ?*BufferedWriter,
module_list: std.StaticStringMap(*Module),
go_again: bool = false,

const std = @import("std");
const builtin = @import("builtin");
const Module = @import("module.zig");
const spindle = @import("spindle.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Wheel = @import("wheel.zig");
const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);

test "ref" {
    _ = spindle;
    _ = Wheel;
    _ = Module;
}

// test "lifecycle" {
// var s: Seamstress = undefined;
// s.init(&std.testing.allocator, null, null);
// s.loop.quit_flag = true;
// try s.run();
// try std.testing.expect(s.loop.quit_flag);
// }
