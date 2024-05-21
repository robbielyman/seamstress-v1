/// functions in this file set up, configure and run seamstress
/// the main players are the event loop, the lua VM and the modules
/// modules should be aware of the loop and the vm to register functions with each
/// the loop and the lua vm should be more or less unaware of each other
const Seamstress = @This();

// single source of truth about seamstress's version
// makes more sense to put in this file than main.zig
pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha-2",
};

// the seamstress loop
pub fn run(self: *Seamstress) void {
    for (self.modules.items) |*module| {
        // modules should only return fatal errors, since they cause us to panic
        module.launch(self.vm.l, &self.loop) catch |err| self.panic(err);
    }
    self.sayHello();
    // drain the events queue
    self.loop.processAll() catch |err| self.panic(err);
    self.vm.callInit();
    // and we're off! blocks until we exit
    self.loop.run() catch |err| self.panic(err);
    self.deinit();
}

// a member function so that elements of this struct have a stable pointer
pub fn init(self: *Seamstress, allocator: *const std.mem.Allocator, stderr: *BufferedWriter) void {
    // set up the lua vm
    self.vm.init(allocator, stderr) catch @panic("unable to start lua vm!");
    self.allocator = allocator.*;
    self.modules = .{};
    // set up the event loop
    self.loop.init() catch |err| self.panic(err);
    // the lua VM parses the config
    // TODO: this is because we allow it to be a lua file!
    // using the config language you embed as a config language? groundbreaking
    const config = self.vm.parseConfig() catch |err| self.panic(err);
    config.consume(self) catch |err| self.panic(err);
    // set up the modules added by consuming the config
    for (self.modules.items) |*module| {
        module.init(&self.vm, &self.loop, self.allocator) catch |err| self.panic(err);
    }
}

// these are the only errors allowed for module code
// TODO: do these make sense?
pub const Error = error{ OutOfMemory, SeamstressCorrupted, LuaFailed, LaunchFailed, LoopFailed };

// used by modules to determine what and how much to clean up
// panic: something has gone wrong; clean up the bare minimum so that seamstress is a good citizen
// clean: we're exiting normally, but don't bother freeing memory (default in release modes)
// full: we're exiting normally, but clean up everything
pub const Cleanup = enum { panic, clean, full };

// pub because it's called by the loop using @fieldParentPtr
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
    self.vm.stderr.flush() catch {};
    // uses stdout to print because the UI module is shut down
    sayGoodbye();
    // if we're doing a clean exit, now is the time to quit
    if (kind == .clean) {
        std.process.cleanExit();
        return;
    }
    // closes the lua VM and events queue and frees memory
    self.vm.close();
    // frees the ArrayList memory
    self.modules.deinit(self.allocator);
}

// cleanup done at panic
// pub because it is called from main.zig
pub fn panicCleanup(self: *Seamstress) void {
    @setCold(true);
    // used to, e.g., turn off grid lights so should be called here
    self.vm.cleanup();
    // shut down modules
    for (self.modules.items) |*module| {
        module.deinit(self.vm.l, self.allocator, .panic);
    }
    // try printing anything in stderr we have leftover?
    self.vm.stderr.flush() catch {};
}

// our implementation of panicking
// pub because it's callep by our event loop
pub fn panic(self: *Seamstress, err: Error) noreturn {
    self.panicCleanup();

    switch (err) {
        error.LaunchFailed => std.debug.panic("module launch failed!", .{}),
        error.LuaFailed => std.debug.panic("the lua VM failed!", .{}),
        error.OutOfMemory => std.debug.panic("out of memory!", .{}),
        error.SeamstressCorrupted => std.debug.panic("_seamstress corrupted!", .{}),
        error.LoopFailed => std.debug.panic("the event loop crashed!", .{}),
    }
}

// should always simply print to stdout
fn sayGoodbye() void {
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();
    stdout.print("goodbye\n", .{}) catch return;
    bw.flush() catch return;
}

// ultimately defined by the terminal UI module
fn sayHello(self: *Seamstress) void {
    self.vm.sayHello();
}

// unmanaged because we store an allocator already
modules: std.ArrayListUnmanaged(Module),
// the lua VM
vm: Spindle,
// the event loop
loop: Wheel,
// the "global" default
allocator: std.mem.Allocator,

const std = @import("std");
const builtin = @import("builtin");
const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Wheel = @import("wheel.zig");
const Config = @import("config.zig");
const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
