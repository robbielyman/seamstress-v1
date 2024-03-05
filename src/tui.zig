const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Io = @import("io.zig");

const std = @import("std");
const nc = @import("notcurses");

const logger = std.log.scoped(.tui);

// TODO: should this be its own file?
pub const Tuio = struct {
    io: *Io,
    stderr: Io.bwm.BufferedWriterMutex(4096, std.ArrayListUnmanaged(u8).Writer),
    stdout: Io.bwm.BufferedWriterMutex(4096, std.ArrayListUnmanaged(u8).Writer),

    pub fn init(io: *Io, stderr: std.ArrayListUnmanaged(u8).Writer, stdout: std.ArrayListUnmanaged(u8).Writer) Tuio {
        return .{
            .io = io,
            .stderr = io.bufferedWriterMutex(stderr),
            .stdout = io.bufferedWriterMutex(stdout),
        };
    }
};

// returns the module interface
pub fn module() Module {
    return .{
        .vtable = &.{
            .init_fn = init,
            .deinit_fn = deinit,
            .launch_fn = launch,
        },
    };
}

// sets up the TUI (actaully, enters TUI mode), hooking it up to the Lua VM
fn init(m: *Module, vm: *Spindle) Error!void {
    const self = try vm.allocator.create(Tui);
    self.* = .{
        // undefined so we can grab a clean pointer from stderr and stdout
        .tuio = undefined,
        // same here
        .reader = undefined,
        .stdin_buf = std.fifo.LinearFifo(u8, .Dynamic).init(vm.allocator),
        .nc = try Tui.NC.init(vm),
    };
    // see?
    self.tuio = Tuio.init(
        vm.io,
        self.stderr_buf.writer(vm.allocator),
        self.stdout_buf.writer(vm.allocator),
    );
    self.reader = self.stdin_buf.reader();
    m.self = self;
    vm.hello = .{
        .ctx = self,
        .hello_fn = hello,
    };
    // just one function to register
    // TODO: actually there will be many more!
    vm.registerSeamstress("_print", printFn, self);
}

// cleans up the TUI thread
fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    // nothing to clean up
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return));
    self.quit = true;
    // wake up the thread if it's sleeping
    self.tuio.io.cond.signal();

    blk: {
        const pid = self.pid orelse break :blk;
        switch (cleanup) {
            // TODO: detaching on panic is probably faster and fine right?
            .panic => pid.detach(),
            .clean, .full => pid.join(),
        }
    }
    self.nc.deinit(vm, cleanup);
    if (cleanup != .full) return;

    vm.allocator.destroy(self);
}

fn launch(m: *const Module, vm: *Spindle) Error!void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return error.LaunchFailed));
    self.pid = std.Thread.spawn(.{}, Tui.replLoop, .{ self, vm }) catch {
        logger.err("unable to start CLI thread!", .{});
        return error.LaunchFailed;
    };
}

const Tui = struct {
    tuio: Tuio,
    stderr_buf: std.ArrayListUnmanaged(u8) = .{},
    stdout_buf: std.ArrayListUnmanaged(u8) = .{},
    stdin_buf: std.fifo.LinearFifo(u8, .Dynamic),
    reader: std.fifo.LinearFifo(u8, .Dynamic).Reader,
    continuing: bool = false,
    nc: NC,
    pid: ?std.Thread = null,
    quit: bool = false,

    // contains all of the Notcurses aspects of Tui
    const NC = struct {
        // the main struct; used to create others
        notcurses: nc.Notcurses,
        // contains the main planes used for displaying the repl
        io_plane: IoPlane,
        // contains planes requested and managed by the script author / user
        display_planes: std.ArrayListUnmanaged(DisplayPlane) = .{},

        fn init(vm: *Spindle) error{NotCursesFailed}!NC {
            _ = vm; // autofix
            const notcurses = nc.Notcurses.coreInit(.{
                .flags = .{},
            }, null) catch return error.NotCursesFailed;
            const io_plane = IoPlane.init(notcurses);
            return .{
                .notcurses = notcurses,
                .io_plane = io_plane,
            };
        }

        fn deinit(self: *NC, vm: *Spindle, cleanup: Cleanup) void {
            self.notcurses.stop() catch return;
            if (cleanup != .full) return;
            for (self.display_planes.items) |*dp| {
                dp.deinit(vm);
            }
            self.io_plane.deinit(vm);
        }

        const DisplayPlane = struct {
            fn deinit(self: *DisplayPlane, vm: *Spindle) void {
                _ = self; // autofix
                _ = vm; // autofix
            }
        };

        const IoPlane = struct {
            fn init(notcurses: nc.Notcurses) IoPlane {
                _ = notcurses; // autofix
                return .{};
            }

            fn deinit(self: *IoPlane, vm: *Spindle) void {
                _ = self; // autofix
                _ = vm; // autofix
            }
        };
    };

    // the main REPL / display loop from the point of view of the TUI input handler
    fn replLoop(self: *Tui, vm: *Spindle) void {
        // grab a file to poll for input
        var poller = std.io.poll(vm.allocator, enum { stdin }, .{ .stdin = self.nc.notcurses.inputReadyFd() });
        defer poller.deinit();
        while (!self.quit) {
            // begin by rendering
            self.render(vm);
            // poll until there's input
            const ready = poller.poll() catch |err| blk: {
                logger.err("error while polling stdin! {s}, stopping input...", .{@errorName(err)});
                break :blk false;
            };
            // poll returns false when the file descriptor is no longer available
            if (!ready) {
                self.quit = true;
                continue;
            }

            self.tuio.io.mtx.lock();
            defer self.tuio.io.mtx.unlock();
            // this might call wait if we're waiting for seamstress to process our input
            self.processInput(vm);
        }
    }

    // TODO
    fn processInput(self: *Tui, vm: *Spindle) void {
        _ = vm; // autofix
        self.tuio.io.cond.wait(&self.tuio.io.mtx);
    }

    // TODO
    fn render(self: *Tui, vm: *Spindle) void {
        _ = self; // autofix
        _ = vm; // autofix
    }
};

/// prints using the TUI interface
/// replaces `print` under TUI operation
fn printFn(l: *Spindle.Lua) i32 {
    // how many things are we printing?
    const n = l.getTop();
    // get our closed-over value
    const idx = Spindle.Lua.upvalueIndex(1);
    const self = l.toUserdata(Tui, idx) catch return 0;
    // grab stdout
    const writer = self.tuio.stdout.writer();
    // while loop because for loops are limited to `usize` in zig
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        // grab a value from the stack
        const bytes = l.toBytes(i) catch |err| {
            logger.err("error while printing: {s}", .{@errorName(err)});
            return 0;
        };
        // write it out
        _ = writer.write(bytes) catch {};
        // separate multiple values with tabs
        // finish out with a newline
        if (i < n)
            _ = writer.write("\t") catch {}
        else
            _ = writer.write("\n") catch {};
    }
    // don't forget to flush!
    // (triggers a TUI render)
    self.tuio.stdout.flush() catch {};
    // nothing to return
    return 0;
}

// closure to print hello using the TUI interface
// using formatted print because Zig treats curly braces special
// and hey, I wanna demonstrate the syntax ;)
fn hello(ctx: *anyopaque) void {
    const self: *Tui = @ptrCast(@alignCast(ctx));
    const stdout = self.tuio.stdout.writer().any();
    stdout.print("{s}S{s}E{s}{s}A{s}M{s}S{s}T{s}R{s}E{s}S{s}S{s}\n", .{
        "{pink}",            "{/pink}{red}",
        "{/red}{orange}",    "{/orange}{yellow}",
        "{/yellow}{green}",  "{/green}{teal}",
        "{/teal}{blue}",     "{/blue}{indigo}",
        "{/indigo}{purple}", "{/purple}{white}",
        "{/white}{brown}",   "{/brown}",
    }) catch return;
    stdout.print("{s}seamstress version:{s} {s}{}{s}\n", .{
        "{pink}",  "{/pink}",
        "{blue}",  @import("main.zig").VERSION,
        "{/blue}",
    }) catch return;
    self.tuio.stdout.flush() catch return;
}
