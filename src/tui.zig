/// TUI interaction module
const Tui = @This();

l: *Lua,
stderr: *BufferedWriter,
vaxis: vx.Vaxis,
tty: vx.Tty,
watcher: vx.xev.TtyWatcher(Tui) = undefined,
err: std.ArrayListUnmanaged(u8) = .{},

fn render(ctx: *anyopaque, lap_time_ns: u64) void {
    const lap_time_float: f64 = @floatFromInt(lap_time_ns);
    const dt = lap_time_float / std.time.ns_per_s;
    const tui: *Tui = @ptrCast(@alignCast(ctx));
    tui.stderr.flush() catch panic("out of memory!", .{});
    tui.vaxis.window().hideCursor();
    lu.getSeamstress(tui.l);
    _ = tui.l.getField(-1, "tui");
    tui.l.remove(-2);
    _ = tui.l.getField(-1, "logs");
    tui.l.remove(-2);
    var last = tui.l.rawLen(-1);
    var tokenizer = std.mem.splitScalar(u8, tui.err.items, '\n');
    while (tokenizer.next()) |token| {
        lu.getSeamstress(tui.l);
        _ = tui.l.getField(-1, "tuiLineNew");
        tui.l.remove(-2);
        _ = tui.l.pushString(token);
        _ = tui.l.pushString("log");
        tui.l.call(2, 1);
        tui.l.setIndex(-2, @intCast(last + 1));
        last += 1;
    }
    tui.l.pop(1);
    tui.err.clearRetainingCapacity();

    lu.getMethod(tui.l, "tui", "update");
    tui.l.pushNumber(dt);
    tui.l.call(1, 0);
    lu.getMethod(tui.l, "tui", "draw");
    tui.l.call(0, 0);

    tui.vaxis.render(tui.tty.anyWriter()) catch panic("unable to draw to the terminal!", .{});
}

fn callback(ud: ?*Tui, _: *xev.Loop, _: *vx.xev.TtyWatcher(Tui), event: vx.xev.Event) xev.CallbackAction {
    const tui = ud.?;
    switch (event) {
        .key_press => |key| {
            press(tui.l, key);
            lu.render(tui.l);
        },
        .key_release => |key| {
            tui.release(key);
            lu.render(tui.l);
        },
        .mouse => |m| tui.mouse(m),
        .focus_in => {
            lu.getMethod(tui.l, "tui", "focusIn");
            lu.doCall(tui.l, 0, 0);
        },
        .focus_out => {
            lu.getMethod(tui.l, "tui", "focusOut");
            lu.doCall(tui.l, 0, 0);
        },
        .paste_start => {},
        .paste_end => {},
        .paste => |txt| {
            tui.paste(txt);
            tui.vaxis.opts.system_clipboard_allocator.?.free(txt);
        },
        .color_report => |_| {},
        .color_scheme => |_| {},
        .winsize => |winsize| {
            tui.vaxis.resize(tui.l.allocator(), tui.tty.anyWriter(), winsize) catch panic("out of memory!", .{});
            tui.vaxis.queueRefresh();
            lu.getSeamstress(tui.l);
            if (tui.l.getField(-1, "tui") == .table) {
                tui.l.remove(-2);
                tui.l.pushInteger(@intCast(winsize.cols));
                tui.l.pushInteger(@intCast(winsize.rows));
                _ = tui.l.getField(-3, "resize");
                tui.l.remove(-4);
                lu.doCall(tui.l, 2, 0);
            } else tui.l.pop(2);
            lu.getSeamstress(tui.l);
            tui.l.pushInteger(@intCast(winsize.cols));
            tui.l.setField(-2, "tui_cols");
            tui.l.pushInteger(@intCast(winsize.rows));
            tui.l.setField(-2, "tui_rows");
            tui.l.pop(1);
            lu.render(tui.l);
        },
    }
    return .rearm;
}

fn press(l: *Lua, key: vx.Key) void {
    lu.getMethod(l, "tui", "key_down");
    if (key.matches(vx.Key.enter, .{ .shift = true })) {
        _ = l.pushString("S-enter");
        l.call(1, 0);
    } else if (key.matches(vx.Key.enter, .{})) {
        _ = l.pushString("enter");
        l.call(1, 0);
    } else if (key.matches('c', .{ .ctrl = true })) {
        _ = l.pushString("C-c");
        l.call(1, 0);
    } else if (key.matches(vx.Key.up, .{})) {
        _ = l.pushString("up");
        l.call(1, 0);
    } else if (key.matches(vx.Key.backspace, .{})) {
        _ = l.pushString("backspace");
        l.call(1, 0);
    } else if (key.text != null and key.text.?.len > 0) {
        _ = l.pushString("text");
        _ = l.pushString(key.text.?);
        l.call(2, 0);
    } else l.pop(1);
}

fn release(_: *Tui, _: vx.Key) void {}

fn mouse(_: *Tui, _: vx.Mouse) void {}

fn paste(_: *Tui, _: []const u8) void {}

fn init(m: *Module, vm: *Spindle, allocator: std.mem.Allocator) void {
    const self = allocator.create(Tui) catch panic("out of memory!", .{});
    m.self = self;
    self.* = .{
        .l = vm.l,
        .stderr = vm.stderr,
        .vaxis = vx.Vaxis.init(allocator, .{
            .system_clipboard_allocator = allocator,
        }) catch panic("unable to start TUI!", .{}),
        .tty = vx.Tty.init() catch panic("unable to open TTY!", .{}),
    };
    const replacement_stderr = allocator.create(std.ArrayListUnmanaged(u8).Writer) catch panic("out of memory!", .{});
    replacement_stderr.* = self.err.writer(allocator);
    self.stderr.unbuffered_writer = replacement_stderr.any();
    @import("tui/color.zig").registerSeamstress(vm.l);
    @import("tui/style.zig").registerSeamstress(vm.l);
    @import("tui/line.zig").registerSeamstress(vm.l, self);
    @import("tui/canvas.zig").registerSeamstress(vm.l, self);
    lu.registerSeamstress(vm.l, "tuiRedraw", redraw, self);
}

fn deinit(m: *const Module, _: *Lua, allocator: std.mem.Allocator, kind: Cleanup) void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return));
    self.vaxis.deinit(if (kind == .full) allocator else null, self.tty.anyWriter());
    self.tty.deinit();
    if (kind != .full) return;
    self.err.deinit(allocator);
    const Writer = std.ArrayListUnmanaged(u8).Writer;
    allocator.destroy(@as(*const Writer, @ptrCast(@alignCast(self.stderr.unbuffered_writer.context))));
    allocator.destroy(self);
}

fn launch(m: *const Module, l: *Lua, wheel: *Wheel) void {
    _ = l; // autofix
    const self: *Tui = @ptrCast(@alignCast(m.self.?));
    self.watcher.init(&self.tty, &self.vaxis, &wheel.loop, self, callback) catch panic("unable to start TTY watcher!", .{});
    wheel.render = .{
        .ctx = self,
        .render_fn = render,
    };
    self.vaxis.enterAltScreen(self.tty.anyWriter()) catch unreachable;
}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

fn redraw(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui).?;
    const wheel = lu.getWheel(l);
    render(tui, wheel.timer.lap());
    return 0;
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
const xev = @import("xev");
const builtin = @import("builtin");
const logger = std.log.scoped(.tui);
