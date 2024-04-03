/// internals of the TUI state
const State = @This();

pub fn render(self: *State, vx: *Vaxis, vm: *Spindle) !void {
    {
        try vm.io.stderr.flush();
        // grab the IO mutex
        vm.io.mtx.lock();
        defer vm.io.mtx.unlock();
        // TODO: first we grab our stuff from stdin
        {
            const restore = self.output.text.current_style;
            defer self.output.text.current_style = restore;
            const writer = self.output.text.writer(vm.allocator).any();
            self.output.text.current_style = self.output.stderr_style;
            _ = try writer.writeAll(self.stderr.items);
            self.stderr.clearRetainingCapacity();
        }
        const tuple = try self.stdout.toOwnedSlices(vm.allocator);
        defer vm.allocator.free(tuple[1]);
        defer vm.allocator.free(tuple[2]);
        defer rt.freeCells(tuple[0], vm.allocator);
        try self.output.text.appendSlices(vm.allocator, tuple[0], tuple[1], tuple[2]);
    }
    const win = vx.window();
    const child_height = @max(self.input.lines.realLength(), 1);
    const child = win.initChild(0, win.height - child_height, .{ .limit = win.width }, .{ .limit = child_height });
    win.clear();
    child.clear();
    self.output.text.draw(win, self.output.current_line);
    self.input.draw(child, .{
        .first = "> ",
        .after = ">... ",
        .style = .{ .fg = .{ .index = 15 } },
    });
    try vx.render();
}

pub fn init(self: *State, vx: *Vaxis, vm: *Spindle) !void {
    self.* = .{
        .map = GraphemeMap.init(vm.allocator),
        .stdout_writer = undefined,
        .stdout = undefined,
        .output = undefined,
        .input = undefined,
        .allocator = vm.allocator,
        .repl_buffer = ThreadSafeBuffer(u8).init(vm.allocator),
    };

    self.input = .{ .map = &self.map };
    self.stdout = .{ .map = &self.map };
    self.output = .{ .text = .{ .map = &self.map } };
    self.stdout_writer = .{ .allocator = vm.allocator, .self = &self.stdout };
    const ev: ReplEvent = .{ .ctx = .{
        .spindle = vm,
        .buffer = &self.repl_buffer,
        .data = &self.input,
        .discard = ReplEvent.discard,
    } };
    @memset(&self.pool, ev);
    _ = vx; // autofix
}

pub fn deinit(self: *State, vm: *Spindle, cleanup: Cleanup) void {
    _ = vm.io.stderr.write(self.stderr.items) catch {};
    switch (cleanup) {
        .full => {
            self.stderr.deinit(self.allocator);
            self.stdout.deinit(self.allocator);
            self.output.text.deinit(self.allocator);
            self.input.deinit(self.allocator);
            self.repl_buffer.deinit();
        },
        .panic, .clean => {},
    }
}

map: GraphemeMap,
stderr: std.ArrayListUnmanaged(u8) = .{},
stdout: rt.RichText,
stdout_writer: rt.RichText.Writer,
output: Output,
input: RichTextBuffer,
repl_buffer: ThreadSafeBuffer(u8),
pool: [8]ReplEvent = undefined,
allocator: std.mem.Allocator,

const Output = struct {
    text: rt.RichText,
    max_len: usize = 500,
    current_line: usize = 0,
    stderr_style: vaxis.Style = .{
        .fg = .{ .index = 9 },
    },
    stdin_style: vaxis.Style = .{
        .fg = .{ .index = 14 },
    },
};

pub const KeyEvent = struct {
    tui: *tui.Tui,
    vm: *Spindle,
    key: vaxis.Key,
    node: Events.Node = .{
        .handler = Events.handlerFromClosure(KeyEvent, handle, "node"),
    },

    // TODO: completely handle the key event
    fn handle(self: *KeyEvent) void {
        defer self.tui.pool.destroy(self);
        if (self.key.matches(vaxis.Key.enter, .{})) {
            const cursor = self.tui.state.input.cursor;
            self.tui.state.input.moveToEnd();
            self.tui.state.input.addText(self.tui.state.allocator, "\n", .{}, .before) catch |err| {
                logger.err("error adding text: {s}", .{@errorName(err)});
            };
            self.tui.state.input.cursor = cursor;
            if (self.tui.state.findFreeEvent()) |ev| {
                self.tui.state.loadReplBuffer() catch |err| {
                    logger.err("error adding text: {s}", .{@errorName(err)});
                };
                ev.ctx.length_to_read = self.tui.state.repl_buffer.readableLength();
                ev.ctx.spindle.events.submit(&ev.ctx.node);
            }
        } else if (self.key.matches(vaxis.Key.backspace, .{})) {
            if (!self.tui.state.input.isEmpty())
                self.tui.state.input.deleteBack();
        } else if (self.key.text) |txt| {
            self.tui.state.input.addText(self.tui.state.allocator, txt, .{}, .before) catch |err| {
                logger.err("error adding text: {s}", .{@errorName(err)});
            };
        }
        self.tui.vx.postEvent(.render);
    }
};

// loads the contents of our input buffer into the sepl queue to send to the lua vm
fn loadReplBuffer(self: *State) !void {
    self.repl_buffer.mtx.lock();
    defer self.repl_buffer.mtx.unlock();
    const utf8_ptr = self.input.cells.slice().getPtr(.utf8);
    for (0..self.input.cells.realLength()) |i| {
        const j = self.input.cells.realIndex(i);
        const utf8 = self.input.map.get(&utf8_ptr[j]) catch unreachable;
        try self.repl_buffer.unprotected_fifo.write(utf8);
    }
}

fn findFreeEvent(self: *State) ?*ReplEvent {
    self.repl_buffer.mtx.lock();
    defer self.repl_buffer.mtx.unlock();
    for (&self.pool) |*ev| {
        if (!ev.in_use) {
            ev.in_use = true;
            return ev;
        }
    }
    logger.err("no REPL events free!", .{});
    return null;
}

// slight enlargement of ReplContext to include a boolean flag for whether the event is in use
const ReplEvent = struct {
    ctx: Spindle.ReplContext,
    in_use: bool = false,

    fn discard(ctx: *Spindle.ReplContext, data: ?*anyopaque) void {
        const buffer: *RichTextBuffer = @ptrCast(@alignCast(data.?));
        if (ctx.length_to_read > 0) {
            ctx.buffer.discard(ctx.length_to_read);
        } else {
            buffer.clearRetainingCapacity();
        }
        ctx.buffer.mtx.lock();
        defer ctx.buffer.mtx.unlock();
        const this = @fieldParentPtr(ReplEvent, "ctx", ctx);
        this.in_use = false;
    }
};

const std = @import("std");
const vaxis = @import("vaxis");
const Events = @import("../events.zig");
const Spindle = @import("../spindle.zig");
const Cleanup = @import("../seamstress.zig").Cleanup;
const tui = @import("../tui.zig");
const Vaxis = tui.Vaxis;
const logger = tui.logger;

const rt = @import("rich_text.zig");
const RichTextBuffer = @import("rich_text_buffer.zig");
const GraphemeMap = @import("grapheme_map.zig");
const ThreadSafeBuffer = @import("../thread_safe_buffer.zig").ThreadSafeBuffer;

test "ref" {
    std.testing.refAllDecls(State);
}
