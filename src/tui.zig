/// TUI interaction module
const Tui = @This();

l: *Lua,
stderr: *BufferedWriter,
any: std.io.AnyWriter,
vaxis: VaxisLayer,
allocator: std.mem.Allocator,
input: std.ArrayListUnmanaged(u8) = .{},
output: std.ArrayListUnmanaged(u8) = .{},
err: std.ArrayListUnmanaged(u8) = .{},

pub fn handlePress(self: *Tui, key: vx.Key) bool {
    if (key.matches('c', .{ .ctrl = true })) return true;
    if (key.text) |txt| self.input.appendSlice(self.allocator, txt) catch panic("out of memory!", .{});
    if (key.matches('\n', .{})) {
        if (std.mem.indexOf(u8, self.input.items, "quit\n")) |idx| {
            if (idx == 0 or self.input.items[idx - 1] == '\n') return true;
        }
        const continuing = lu.processChunk(self.l, self.input.items);
        if (!continuing) self.input.clearRetainingCapacity();
        lu.luaPrint(self.l);
    }
    return false;
}

pub fn handleRelease(_: *Tui, _: vx.Key) void {}

pub fn handleMouse(_: *Tui, _: vx.Mouse) void {}

pub fn focusIn(_: *Tui) void {}

pub fn focusOut(_: *Tui) void {}

pub fn pasteStart(_: *Tui) void {}

pub fn pasteEnd(_: *Tui) void {}

pub fn paste(_: *Tui, _: []const u8) void {}

pub fn colorReport(_: *Tui, _: vx.Color.Report) void {}

pub fn colorScheme(_: *Tui, _: vx.Color.Scheme) void {}

fn init(m: *Module, vm: *Spindle, allocator: std.mem.Allocator) void {
    const self = allocator.create(Tui) catch panic("out of memory!", .{});
    m.self = self;
    self.* = .{
        .l = vm.l,
        .stderr = vm.stderr,
        .vaxis = undefined,
        .any = undefined,
        .allocator = allocator,
    };
    self.vaxis.init(allocator) catch panic("unable to start TUI library!", .{});
    const replacement_stderr = allocator.create(std.ArrayListUnmanaged(u8).Writer) catch panic("out of memory!", .{});
    replacement_stderr.* = self.err.writer(allocator);
    self.stderr.unbuffered_writer = replacement_stderr.any();
    const any_backing = allocator.create(std.ArrayListUnmanaged(u8).Writer) catch panic("out of memory!", .{});
    any_backing.* = self.output.writer(allocator);
    self.any = any_backing.any();
    lu.registerSeamstress(vm.l, "_print", lu.printFn, &self.any);
}

fn deinit(m: *const Module, _: *Lua, allocator: std.mem.Allocator, kind: Cleanup) void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return));
    self.vaxis.deinit(kind);
    if (kind != .full) return;
    const Writer = std.ArrayListUnmanaged(u8).Writer;
    allocator.destroy(@as(*const Writer, @ptrCast(@alignCast(self.any.context))));
    allocator.destroy(@as(*const Writer, @ptrCast(@alignCast(self.stderr.unbuffered_writer.context))));
    allocator.destroy(self);
}

fn launch(m: *const Module, l: *Lua, wheel: *Wheel) void {
    _ = l; // autofix
    const self: *Tui = @ptrCast(@alignCast(m.self.?));
    self.vaxis.launch(wheel);
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
const Seamstress = @import("seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const Wheel = @import("wheel.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const vx = @import("vaxis");
const panic = std.debug.panic;
const lu = @import("lua_util.zig");
const xev = @import("libxev");
const builtin = @import("builtin");
const logger = std.log.scoped(.tui);
const VaxisLayer = @import("tui/vaxis.zig");
