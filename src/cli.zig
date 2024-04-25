/// CLI mode interaction over stdin/err/out.
/// writing to stderr and stdout is buffered to attempt to present a clean prompt to the user

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
    const self = try vm.allocator.create(Cli);
    // FIXME: I really like this approach to quitting. it might make porting to windows harder...
    // oh but it makes waking up on stdout trivial! love that
    const read_end, const write_end = std.posix.pipe() catch return error.LaunchFailed;
    const ready: std.fs.File = .{ .handle = write_end };
    self.* = .{
        .poller = std.io.poll(
            // we don't actually want to do this, but if we uncook the terminal slightly,
            // we could get away with an FBA here lol
            vm.allocator,
            Enum,
            .{ .stdin = std.io.getStdIn(), .quit_or_ready = .{ .handle = read_end } },
        ),
        .print_ctx = undefined,
        .stdout_writer = undefined,
        .file_writer = ready.writer(),
        .stdin_buffer = ThreadSafeBuffer(u8).init(vm.allocator),
    };
    const ev: Cli.ReplEvent = .{ .ctx = .{
        .buffer = &self.stdin_buffer,
        .length_to_read = 0,
        .discard = Cli.ReplEvent.discard,
    } };
    @memset(&self.pool, ev);
    self.stdout_writer = self.stdout_buf.writer(vm.allocator);
    self.print_ctx = .{
        .stdout = self.stdout_writer.any(),
        .ready = self.file_writer.any(),
    };
    m.self = self;
    vm.hello = .{ .ctx = self, .hello_fn = hello };
    // just one function to register
        lu.registerSeamstress(vm, "_print", Spindle.printFn, &self.print_ctx);
}

// cleans up the CLI thread
fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    // nothing to clean up
    const self: *Cli = @ptrCast(@alignCast(m.self orelse return));
    // write to the pipe to quit
    _ = self.print_ctx.ready.write("q") catch {};

    blk: {
        const pid = self.pid orelse break :blk;
        switch (cleanup) {
            .panic => pid.detach(),
            .clean, .full => pid.join(),
        }
    }
    if (cleanup != .full) return;

    self.stdin_buffer.deinit();
    self.stdout_buf.deinit(vm.allocator);
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

// files that replLoop polls
const Enum = enum { stdin, quit_or_ready };

const Cli = struct {
    pid: ?std.Thread = null,
    poller: std.io.Poller(Enum),
    continuing: usize = 0,
    stdout_buf: std.ArrayListUnmanaged(u8) = .{},
    stdout_writer: std.ArrayListUnmanaged(u8).Writer,
    print_ctx: Spindle.PrintContext,
    file_writer: std.fs.File.Writer,
    // pool for producing REPL events
    pool: [8]ReplEvent = undefined,
    stdin_buffer: ThreadSafeBuffer(u8),

    // the main REPL loop from the point of view of the CLI input handler
    fn replLoop(self: *Cli, vm: *Spindle) void {
        while (true) {
            // poll until there's input
            const ready = self.poller.poll() catch |err| blk: {
                logger.err("error while polling stdin! {s}, stopping input...", .{@errorName(err)});
                break :blk false;
            };
            // poll returns false when the file descriptor is no longer available
            if (!ready) break;

            // did we get something in the quit_or_ready fd?
            const quit_or_ready = self.poller.fifo(.quit_or_ready);
            // if quit, we quit, otherwise we continue
            while (quit_or_ready.readItem()) |char| {
                switch (char) {
                    'q' => {
                        lu.quit(vm);
                        return;
                    },
                    // our 'hello' function writes here, so we effectively begin by prompting
                    'r' => self.flushAndPrompt(vm),
                    else => unreachable,
                }
            }

            // it seems like a reasonable assumption that the terminal is "cooked",
            // so if there is input from stdin, it's a full line.
                const fifo = self.poller.fifo(.stdin);
            if (fifo.readableLength() > 0) {
                while (fifo.readableLength() > 0) {
                    const slice = fifo.readableSlice(0);
                    self.stdin_buffer.appendSlice(slice) catch {
                        lu.panic(vm, error.OutOfMemory);
                        return;
                    };
                    fifo.discard(slice.len);
                }
                self.postReplEvent(vm);
            }
        }
    }

    // slight enlargement of ReplContext to include a boolean flag for whether the event is in use
    const ReplEvent = struct {
        ctx: Spindle.ReplContext,
        in_use: bool = false,

        fn discard(ctx: *Spindle.ReplContext, _: ?*anyopaque) void {
            ctx.buffer.mtx.lock();
            defer ctx.buffer.mtx.unlock();
            const this: *ReplEvent = @fieldParentPtr("ctx", ctx);
            this.in_use = false;
        }
    };

    // posts a REPL event for the seamstress vm to respond to
        fn postReplEvent(self: *Cli, vm: *Spindle) void {
        const ev: *ReplEvent = ev: {
            self.stdin_buffer.mtx.lock();
            defer self.stdin_buffer.mtx.unlock();
            for (&self.pool) |*ev| {
                if (!ev.in_use) {
                    ev.in_use = true;
                    break :ev ev;
                }
            }
            // all eight elements of the pool are taken!
            logger.err("no REPL events free!", .{});
            return;
        };
        ev.ctx.length_to_read = self.stdin_buffer.readableLength();
        vm.events.submit(&ev.ctx.node);
    }

    // if anything is in our buffers, print it out and then prompt
    // by using the mutex, we should have a clean prompt in CLI mode
    // (printing from clocks and so forth is an unavoidable partial expeption)
    fn flushAndPrompt(self: *Cli, vm: *Spindle) void {
        // grab stdout (buffered to reduce syscalls)
        const stdout_file = std.io.getStdOut().writer();
        var bw = std.io.bufferedWriter(stdout_file);
        const stdout = bw.writer();

        // grab the IO mutex
        vm.io.mtx.lock();
        defer vm.io.mtx.unlock();
        // first, print anything that's accumulated in stderr
        vm.io.stderr.flush() catch {};
        // write what's accumulated in stdout
        stdout.print("{s}", .{self.stdout_buf.items}) catch {};
        // then prompt
        const prompt: []const u8 = if (self.continuing > 0) ">... " else "> ";
        stdout.print("{s}", .{prompt}) catch {};
        // don't forget to flush!
        bw.flush() catch {};
        // and drain the buffer
        self.stdout_buf.clearRetainingCapacity();
    }
};

// closure to print hello using the CLI interface
fn hello(ctx: *anyopaque) void {
    const self: *Cli = @ptrCast(@alignCast(ctx));
    const stdout = self.print_ctx.stdout;
    stdout.print("SEAMSTRESS\n", .{}) catch return;
    stdout.print("seamstress version: {}\n", .{@import("main.zig").VERSION}) catch return;
    _ = self.print_ctx.ready.write("r") catch {};
}

const std = @import("std");
const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Io = @import("io.zig");
const ThreadSafeBuffer = @import("thread_safe_buffer.zig").ThreadSafeBuffer;
const lu = @import("lua_util.zig");

const logger = std.log.scoped(.cli);
