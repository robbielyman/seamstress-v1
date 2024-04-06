/// TUI mode terminal interaction

// the main struct for interacting with the terminal window
pub const Tui = struct {
    pid: ?std.Thread = null,
    vx: Vaxis,
    state: State,
    print_ctx: Spindle.PrintContext,
    writers: Writers,
    pool: std.heap.MemoryPoolExtra(State.KeyEvent, .{}),

    fn create(vm: *Spindle) Error!*Tui {
        const self = try vm.allocator.create(Tui);
        self.* = .{
            .vx = Vaxis.init(.{}) catch return error.TUIFailed,
            .state = undefined,
            .print_ctx = undefined,
            .writers = undefined,
            .pool = try std.heap.MemoryPoolExtra(State.KeyEvent, .{}).initPreheated(vm.allocator, 128),
        };
        try self.state.init(&self.vx, vm);
        self.writers = .{
            .stderr_writer = self.state.stderr.writer(vm.allocator),
            .ev_writer = eventWriter(&self.vx),
            .old_writer = undefined,
        };
        self.print_ctx = .{
            .ready = self.writers.ev_writer.any(),
            .stdout = self.state.stdout_writer.any(),
        };
        return self;
    }

    // short that we can use `try` in the actual loop
    fn replLoop(self: *Tui, vm: *Spindle) void {
        self.inner(vm) catch |err| {
            // FIXME: this error usually doesn't make it to the screen lol
            logger.err("error: {}", .{err});
            lu.panic(vm, error.TUIFailed);
        };
    }

    // the real TUI loop
    fn inner(self: *Tui, vm: *Spindle) !void {
        try self.vx.queryTerminal();
        try self.vx.enterAltScreen();
        defer self.vx.exitAltScreen() catch {};

        while (true) {
            // wait till the next event; wake up this thread with a `quit` or `render` event
            const ev = self.vx.nextEvent();
            switch (ev) {
                // exits
                .quit => return,
                // renders
                .render => try self.render(vm),
                // resizes the window
                .winsize => |ws| {
                    try self.vx.resize(vm.allocator, ws);
                    self.vx.queueRefresh();
                    self.vx.postEvent(.render);
                },
                // parses input
                .key_press => |k| {
                    // special case: ctrl+c should quit
                    if (k.matches('c', .{ .ctrl = true })) {
                        lu.quit(vm);
                        return;
                    }
                    // process other keys on the main thread so they can go through Lua
                    // if the state of the tui demands it
                    try self.postKeyEvent(vm, k);
                },
            }
        }
    }

    // just passes the call to our state struct
    fn render(self: *Tui, vm: *Spindle) !void {
        try self.state.render(&self.vx, vm);
    }

    fn postKeyEvent(self: *Tui, vm: *Spindle, key: vaxis.Key) !void {
        const ev = try self.pool.create();
        ev.* = .{
            .tui = self,
            .vm = vm,
            .key = key,
        };
        vm.events.submit(&ev.node);
    }

    const Writers = struct {
        ev_writer: EventWriter,
        old_writer: std.io.AnyWriter,
        stderr_writer: std.ArrayListUnmanaged(u8).Writer,
    };
};

// returns th emodule interface
pub fn module() Module {
    return .{
        .vtable = &.{
            .init_fn = init,
            .deinit_fn = deinit,
            .launch_fn = launch,
        },
    };
}

// sets up the TUI module; monkey-patches our logger
fn init(m: *Module, vm: *Spindle) Error!void {
    // creates using vm.allocator
    const self = try Tui.create(vm);
    // grab the old writer
    const old_writer = vm.io.replaceUnderlyingStream(self.writers.stderr_writer.any());
    // save it
    self.writers.old_writer = old_writer;
    m.self = self;
    lu.registerSeamstress(vm, "_print", Spindle.printFn, &self.print_ctx);
    vm.hello = .{
        .ctx = self,
        .hello_fn = hello,
    };
}

// shuts down the TUI module
fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return));
    // stop getting from stdin
    self.vx.stopReadThread();
    // FIXME: is this too silly?
    _ = self.print_ctx.ready.write("q") catch {};
    // stop processing tui events
    if (self.pid) |p| {
        switch (cleanup) {
            .clean, .full => p.join(),
            .panic => p.detach(),
        }
    }
    // deinit our vaxis instance
    self.vx.deinit(if (cleanup == .full) vm.allocator else null);
    // put back the old stderr logger
    // the next call flushes our new stderr buffer to it
    _ = vm.io.replaceUnderlyingStream(self.writers.old_writer);
    // cleans up the tui state
    self.state.deinit(vm, cleanup);
    switch (cleanup) {
        .full => {
            self.pool.deinit();
            vm.allocator.destroy(self);
        },
        .clean, .panic => {},
    }
}

// starts the IO read thread and the TUI thread
fn launch(m: *const Module, vm: *Spindle) Error!void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return error.LaunchFailed));
    self.vx.startReadThread() catch return error.LaunchFailed;
    self.pid = std.Thread.spawn(.{}, Tui.replLoop, .{ self, vm }) catch return error.LaunchFailed;
}

// pretty prints a hello message
fn hello(ctx: *anyopaque) void {
    const self: *Tui = @ptrCast(@alignCast(ctx));
    const seamstress = "SEAMSTRESS";
    const colors: [10]u8 = .{
        224, 222, 220, 148, 150, 152, 153, 189, 188, 186,
    };
    for (seamstress, &colors) |letter, idx| {
        self.state.stdout.current_style.fg = .{ .index = idx };
        self.print_ctx.stdout.print("{c}", .{letter}) catch {};
    }
    self.state.stdout.current_style.fg = .default;
    self.print_ctx.stdout.print("\n", .{}) catch {};
    self.state.stdout.current_style.fg = .{ .index = 45 };
    self.print_ctx.stdout.print("seamstress version: ", .{}) catch {};
    self.state.stdout.current_style.fg = .{ .index = 79 };
    self.print_ctx.stdout.print("{}\n", .{@import("main.zig").VERSION}) catch {};
    self.state.stdout.current_style.fg = .default;
    _ = self.print_ctx.ready.write("r") catch {};
}

test "ref" {
    std.testing.refAllDecls(@This());
}

const EventWriter = std.io.GenericWriter(*Vaxis, error{BadInput}, eventWriteFn);

fn eventWriter(self: *Vaxis) EventWriter {
    return .{ .context = self };
}

// a "write" function for parity with the cli interface
fn eventWriteFn(vx: *Vaxis, bytes: []const u8) error{BadInput}!usize {
    if (bytes.len == 0) return 0;
    switch (bytes[0]) {
        'q' => vx.postEvent(.quit),
        'r' => vx.postEvent(.render),
        else => return error.BadInput,
    }
    return bytes.len;
}

// shuts down the tty when panicking
fn panic(ctx: ?*anyopaque) void {
    const tui: *Tui = @ptrCast(@alignCast(ctx orelse return));
    tui.vx.exitAltScreen() catch {};
    tui.vx.stopReadThread();
    tui.vx.deinit(null);
}

// pub for our nested imports
pub const logger = std.log.scoped(.tui);

const std = @import("std");
const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Io = @import("io.zig");
const State = @import("tui/state.zig");
const vaxis = @import("vaxis");
// pub for our nested imports
pub const Vaxis = vaxis.Vaxis(VxEvent);
// the events that our vaxis instance responds to
const VxEvent = union(enum) {
    winsize: vaxis.Winsize,
    key_press: vaxis.Key,
    quit,
    render,
};
const lu = @import("lua_util.zig");
