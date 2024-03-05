const std = @import("std");
const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Io = @import("io.zig");

const logger = std.log.scoped(.cli);
const Enum = enum { stdin };

// TODO: should this be its own file?
pub const Clio = struct {
    io: *Io,
    stderr: Io.bwm.BufferedWriterMutex(4096, std.fs.File.Writer),
    stdout: Io.bwm.BufferedWriterMutex(4096, std.fs.File.Writer),

    pub fn init(io: *Io) Clio {
        return .{
            .io = io,
            .stderr = io.bufferedWriterMutex(std.io.getStdErr().writer()),
            .stdout = io.bufferedWriterMutex(std.io.getStdOut().writer()),
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

// sets up the CLI, hooking it up to the Lua VM
fn init(m: *Module, vm: *Spindle) Error!void {
    // shenanigans to grab the Clio struct we created in main
    const seamstress = @fieldParentPtr(Seamstress, "vm", vm);
    const self = try vm.allocator.create(Cli);
    self.* = .{
        .clio = seamstress.clio,
        .poller = std.io.poll(
            vm.allocator,
            Enum,
            .{ .stdin = std.io.getStdIn() },
        ),
    };
    m.self = self;
    vm.hello = .{
        .ctx = self,
        .hello_fn = hello,
    };
    // just one function to register
    vm.registerSeamstress("_print", printFn, self);
}

// cleans up the CLI thread
fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    // nothing to clean up
    const self: *Cli = @ptrCast(@alignCast(m.self orelse return));
    self.quit = true;
    // wake up the thread if it's sleeping
    self.clio.io.cond.signal();

    blk: {
        const pid = self.pid orelse break :blk;
        switch (cleanup) {
            .panic => {
                // TODO: detaching on panic is probably faster and fine right?
                pid.detach();
                return;
            },
            .clean, .full => pid.join(),
        }
    }
    if (cleanup != .full) return;

    self.poller.deinit();
    vm.allocator.destroy(self);
}

// starts the CLI thread
fn launch(m: *const Module, vm: *Spindle) Error!void {
    const self: *Cli = @ptrCast(@alignCast(m.self orelse return error.LaunchFailed));
    self.pid = std.Thread.spawn(.{}, Cli.replLoop, .{ self, vm }) catch {
        logger.err("unable to start CLI thread!", .{});
        return error.LaunchFailed;
    };
}

const Cli = struct {
    clio: *Clio,
    pid: ?std.Thread = null,
    poller: std.io.Poller(Enum),
    quit: bool = false,
    continuing: bool = false,

    // the main REPL loop from the point of view of the CLI input handler
    fn replLoop(self: *Cli, vm: *Spindle) void {
        var ctx: Spindle.StdinContext = .{
            .continuing = &self.continuing,
            .spindle = vm,
        };
        while (!self.quit) {
            // begin by prompting
            self.flushAndPrompt();
            // poll until there's input
            const ready = self.poller.poll() catch |err| blk: {
                logger.err("error while polling stdin! {s}, stopping input...", .{@errorName(err)});
                break :blk false;
            };
            // poll returns false when the file descriptor is no longer available
            if (!ready) {
                self.quit = true;
                continue;
            }

            self.clio.io.mtx.lock();
            defer self.clio.io.mtx.unlock();
            const fifo = self.poller.fifo(.stdin);
            // do we have a full line here?
            // if not, go back to polling
            for (0..fifo.count) |idx| {
                if (fifo.peekItem(idx) == '\n') {
                    // post an event to grab the line (including newline)
                    vm.events.post(.{ .command = .{
                        .ctx = &ctx,
                        .reader = fifo.reader().any(),
                        .len = idx + 1,
                        .f = Spindle.stdinHandler,
                    } });
                    break;
                }
            } else continue;
            // we posted an event; we'll wait for it to be processed before prompting again
            self.clio.io.cond.wait(&self.clio.io.mtx);
        }
    }

    // if anything is in our buffers, print it out and then prompt
    // by using the mutex, we should have a clean prompt in CLI mode
    // (printing from clocks and so forth is an unavoidable partial expeption)
    fn flushAndPrompt(self: *Cli) void {
        self.clio.stdout.flush() catch {};
        self.clio.stderr.flush() catch {};
        const prompt: []const u8 = if (self.continuing) ">... " else "> ";
        self.clio.stdout.writer().any().print("{s}", .{prompt}) catch {};
        self.clio.stdout.flush() catch {};
    }
};

/// prints using the CLI interface
/// replaces `print` under CLI operation
fn printFn(l: *Spindle.Lua) i32 {
    // how many things are we printing?
    const n = l.getTop();
    // get our closed-over value
    const idx = Spindle.Lua.upvalueIndex(1);
    const self = l.toUserdata(Cli, idx) catch return 0;
    // grab stdout
    const writer = self.clio.stdout.writer();
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
    self.clio.stdout.flush() catch {};
    // nothing to return
    return 0;
}

// closure to print hello using the CLI interface
fn hello(ctx: *anyopaque) void {
    const self: *Cli = @ptrCast(@alignCast(ctx));
    const stdout = self.clio.stdout.writer().any();
    stdout.print("SEAMSTRESS\n", .{}) catch return;
    stdout.print("seamstress version: {}\n", .{@import("main.zig").VERSION}) catch return;
    self.clio.stdout.flush() catch return;
}
