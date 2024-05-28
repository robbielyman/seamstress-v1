/// functions in this file set up, configure and run seamstress
/// the main players are the event loop, the lua VM and the modules
/// modules are passed the loop and the vm to register functions and events with each
/// the loop and the lua vm are more or less unaware of each other
const Seamstress = @This();

/// single source of truth about seamstress's version
/// makes more sense to put in this file rather than main.zig
pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha-3",
};

/// the seamstress loop
pub fn run(self: *Seamstress) void {
    for (self.modules.items) |*module| {
        module.launch(self.vm.l, &self.loop);
    }
    self.sayHello();
    // drain the events queue
    self.loop.processAll();
    self.vm.callInit();
    // run the event loop; blocks until we exit
    self.loop.run();
    self.deinit();
}

// a member function so that elements of this struct have a stable pointer
pub fn init(self: *Seamstress, allocator: *const std.mem.Allocator, stderr: *BufferedWriter) void {
    // set up the lua vm
    self.vm.init(allocator, stderr);
    self.allocator = allocator.*;
    self.modules = .{};
    @import("config.zig").configure(self);
    // set up the event loop
    self.loop.init();
    for (self.modules.items) |*module| {
        module.init(&self.vm, self.allocator);
    }
}

/// cleanup done at panic
/// pub because it is called from main.zig
pub fn panicCleanup(self: *Seamstress) void {
    @setCold(true);
    // used to, e.g. turn off grid lights, so should be called here
    self.vm.cleanup();
    // shut down modules
    for (self.modules.items) |*module| {
        module.deinit(self.vm.l, self.allocator, .panic);
    }
    // try printing anything in stderr we have leftover?
    self.vm.stderr.unbuffered_writer = std.io.getStdErr().writer().any();
    self.vm.stderr.flush() catch {};
}

/// used by modules to determine what and how much to clean up.
/// panic: something has gone wrong; clean up the bare minimum so that seamstress is a good citizen
/// clean: we're exiting normally, but don't bother freeing memory
/// full: we're exiting normally, but clean up everything
pub const Cleanup = enum { panic, clean, full };

/// pub because it's called by the loop using @fieldParentPtr
pub fn deinit(self: *Seamstress) void {
    // e.g. turns off grid lights
    self.vm.cleanup();
    const kind: Cleanup = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .full,
        .ReleaseFast, .ReleaseSmall => .clean,
    };
    // shut down modules
    for (self.modules.items) |*module| {
        module.deinit(self.vm.l, self.allocator, kind);
    }
    // flush logs
    self.vm.stderr.unbuffered_writer = std.io.getStdErr().writer().any();
    self.vm.stderr.flush() catch {};
    // uses stdout to print because the UI module is shut down
    sayGoodbye();
    // if we're doing a clean exit, now is the time to quit
    if (kind == .clean) {
        std.process.cleanExit();
        return;
    }
    // closes the lua VM and frees memory
    self.vm.close();
    // frees memory
    self.modules.deinit(self.allocator);
}

/// should always simply print to stdout
fn sayGoodbye() void {
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();
    stdout.print("goodbye\n", .{}) catch return;
    bw.flush() catch return;
}

/// ultimately defined by the terminal UI module
fn sayHello(self: *Seamstress) void {
    self.vm.sayHello();
}

// unmanaged because we store an allocator
modules: std.ArrayListUnmanaged(Module),
// the lua VM
vm: Spindle,
// the event loop
loop: Wheel,
// the "global" default allocator
allocator: std.mem.Allocator,

const std = @import("std");
const builtin = @import("builtin");
const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Wheel = @import("wheel.zig");
const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
