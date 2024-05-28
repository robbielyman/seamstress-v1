/// bare-bones CLI communication layer
const Cli = @This();

l: *Lua,
stderr: *BufferedWriter,
stdout: BufferedWriter,
stdin_buf: std.ArrayList(u8),
file: xev.File,
c: xev.Completion = .{},
continuing: bool = false,
any: std.io.AnyWriter,

/// flushes stdout and stderr, and re-prompts (usually)
fn render(ctx: *anyopaque) void {
    const self: *Cli = @ptrCast(@alignCast(ctx));
    self.stderr.flush() catch {};
    const writer = self.stdout.writer();
    if (self.continuing)
        writer.writeAll(">... ") catch panic("unable to print!", .{})
    else
        writer.writeAll("> ") catch panic("unable to print!", .{});
    self.stdout.flush() catch panic("unable to print!", .{});
}

/// processes a chunk of stdin, renders, rinses and repeats
fn handleStdin(
    self: ?*Cli,
    l: *xev.Loop,
    c: *xev.Completion,
    f: xev.File,
    buf: xev.ReadBuffer,
    r: xev.ReadError!usize,
) xev.CallbackAction {
    const len = r catch 0;
    if (std.mem.indexOf(u8, buf.slice, "quit\n")) |idx| {
        if (idx == 0 or buf.slice[idx - 1] == '\n') {
            const wheel: *Wheel = @fieldParentPtr("loop", l);
            wheel.quit();
            return .disarm;
        }
    }
    self.?.stdin_buf.items.len += len;
    self.?.continuing = lu.processChunk(self.?.l, self.?.stdin_buf.items);
    if (!self.?.continuing) self.?.stdin_buf.clearRetainingCapacity();
    lu.luaPrint(self.?.l);
    f.read(l, c, .{ .slice = self.?.stdin_buf.unusedCapacitySlice() }, Cli, self, handleStdin);
    return .disarm;
}

/// says hello
fn hello(ctx: *anyopaque) void {
    const self: *Cli = @ptrCast(@alignCast(ctx));
    const writer = self.stdout.writer();
    writer.print("SEAMSTRESS\n", .{}) catch return;
    writer.print("seamstress version: {}\n", .{@import("seamstress.zig").version}) catch return;
    render(self);
}

fn init(m: *Module, vm: *Spindle, allocator: std.mem.Allocator) void {
    const self = allocator.create(Cli) catch panic("out of memory!", .{});
    const stdout_backing = allocator.create(std.fs.File.Writer) catch panic("out of memory!", .{});
    stdout_backing.* = std.io.getStdOut().writer();
    const any_backing = allocator.create(BufferedWriter.Writer) catch panic("out of memory!", .{});
    m.self = self;
    self.* = .{
        .l = vm.l,
        .stderr = vm.stderr,
        .stdout = std.io.bufferedWriter(stdout_backing.any()),
        .stdin_buf = std.ArrayList(u8).init(allocator),
        .file = xev.File.init(std.io.getStdIn()) catch panic("unable to open stdin!", .{}),
        .any = undefined,
    };
    any_backing.* = self.stdout.writer();
    self.any = any_backing.any();
    vm.hello = .{
        .ctx = self,
        .hello_fn = hello,
    };
    lu.registerSeamstress(vm.l, "_print", lu.printFn, &self.any);
}

fn deinit(m: *const Module, _: *Lua, allocator: std.mem.Allocator, kind: Cleanup) void {
    if (kind != .full) return;
    const self: *Cli = @ptrCast(@alignCast(m.self orelse return));
    self.stdin_buf.deinit();
    allocator.destroy(@as(*const std.fs.File.Writer, @ptrCast(@alignCast(self.stdout.unbuffered_writer.context))));
    allocator.destroy(@as(*const BufferedWriter.Writer, @ptrCast(@alignCast(self.any.context))));
    allocator.destroy(self);
}

fn launch(m: *const Module, l: *Lua, wheel: *Wheel) void {
    const self: *Cli = @ptrCast(@alignCast(m.self.?));
    self.stdin_buf.ensureUnusedCapacity(4096) catch panic("out of memory!", .{});
    const slice = self.stdin_buf.unusedCapacitySlice();
    wheel.render = .{
        .ctx = self,
        .render_fn = render,
    };
    self.file.read(&wheel.loop, &self.c, .{ .slice = slice[0..@min(slice.len, 4096)] }, Cli, self, handleStdin);
    _ = l; // autofix
}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
const Module = @import("module.zig");
const Spindle = @import("spindle.zig");
const Wheel = @import("wheel.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Cleanup = @import("seamstress.zig").Cleanup;
const std = @import("std");
const xev = @import("libxev");
const panic = std.debug.panic;
const lu = @import("lua_util.zig");
