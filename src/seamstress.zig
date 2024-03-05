/// functions in this file set up, configure and run seamstress
/// this file should be unaware that the Lua VM exists
/// likewise the Lua VM should be unaware of the other modules
const std = @import("std");
const builtin = @import("builtin");
const Spindle = @import("spindle.zig");
const Module = @import("module.zig");
const Events = @import("events.zig");
const Io = @import("io.zig");
const cli = @import("cli.zig");
const Seamstress = @This();

// these are the errors that may be panicked on
// TODO: do these make sense?
pub const Error = error{ OutOfMemory, SeamstressCorrupted, NotCursesFailed, LaunchFailed };

// used by modules to determine what and how much to clean up
// panic: something has gone wrong; clean up the bare minimum so that seamstress is a good citizen
// clean: we're exiting normally, but don't bother freeing memory (default in release modes)
// full: we're exiting normally, but clean up everything
pub const Cleanup = enum { panic, clean, full };

// the Lua VM and events queue
vm: Spindle,
// unmanaged bc we can get away with it:
// vm stores an allocator, and we just reach in to use that
modules: std.ArrayListUnmanaged(Module),
// reference to the CLI IO set up in main;
// used to say goodbye
clio: *cli.Clio,

// our implementation of panicking
// pub because it's called by the events queue using @fieldParentPtr
pub fn panic(self: *Seamstress, err: Error) noreturn {
    @setCold(true);
    // used to, e.g. turn off grid lights so should be called here
    self.vm.cleanup();

    for (self.modules.items) |*module| {
        module.deinit(&self.vm, .panic);
    }

    // std.debug.panic exits the program with a message (and a stack trace if we're lucky)
    switch (err) {
        error.OutOfMemory => std.debug.panic("out of memory!", .{}),
        error.NotCursesFailed => std.debug.panic("TUI library failed!", .{}),
        error.LaunchFailed => std.debug.panic("module launch failed!", .{}),
        error.SeamstressCorrupted => std.debug.panic("_seamstress corrupted!", .{}),
    }
}

// called from main to run seamstress!
pub fn run(self: *Seamstress) void {
    // in TUI mode this queues up the hello message
    // but does not actually display it until the TUI is ready
    self.sayHello();
    for (self.modules.items) |*module| {
        // modules should only return fatal errors, since they cause us to panic
        module.launch(&self.vm) catch |err| self.panic(err);
    }
    // drain the events queue
    self.vm.events.processAll();
    self.vm.callInit();
    // and we're off! this blocks this thread until we exit
    self.vm.events.loop();
}

// pub because it's called by the events queue using @fieldParentPtr
pub fn deinit(self: *Seamstress) void {
    self.vm.cleanup();
    const kind: Cleanup = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .full,
        .ReleaseFast, .ReleaseSmall => .clean,
    };

    for (self.modules.items) |*module| {
        module.deinit(&self.vm, kind);
    }

    // uses the CLI IO we set up in main because the TUI is shut down
    sayGoodbye(self.clio);

    if (kind == .clean) {
        std.process.cleanExit();
        return;
    }
    // closes the Lua VM and events queue and frees memory
    self.vm.close();
    // frees the ArrayList memory
    self.modules.deinit(self.vm.allocator);
}

// heap allocates a struct so that it can have a stable pointer
// (or really, so that the Lua VM can)
pub fn create(allocator: *const std.mem.Allocator, io: *Io, clio: *cli.Clio) *Seamstress {
    // we haven't set anything up yet and don't need formatted panicking,
    // so @panic makes sense here
    const self = allocator.create(Seamstress) catch @panic("no memory!");
    self.vm.init(allocator, io) catch @panic("unable to start lua vm!");
    self.modules = .{};
    self.clio = clio;

    // it's the Lua VM's responsibility to get and parse the config
    // TODO: this is because the config will be a lua file!
    // using the config language you embed as a config language? groundbreaking
    const config = self.vm.parseConfig() catch |err| self.panic(err);
    self.consume(config) catch |err| self.panic(err);

    for (self.modules.items) |*module| {
        module.init(&self.vm) catch |err| self.panic(err);
    }

    return self;
}

// eats a Config struct to populate the list of modules
fn consume(self: *Seamstress, config: Config) Error!void {
    const tui_module = if (config.tui) @import("tui.zig").module() else @import("cli.zig").module();
    try self.modules.append(self.vm.allocator, tui_module);
}

// TODO: should this struct be its own file?
pub const Config = struct {
    tui: bool,
};

// should always simply print to stdout
fn sayGoodbye(clio: *cli.Clio) void {
    const stdout = clio.stdout.writer().any();
    stdout.print("goodbye\n", .{}) catch return;
    clio.stdout.flush() catch return;
}

// ultimately defined by the tui_module
fn sayHello(self: *Seamstress) void {
    self.vm.sayHello();
}