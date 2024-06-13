/// TUI interaction module
// @module _seamstress.tui
const Tui = @This();

l: *Lua,
vaxis: vx.Vaxis,
tty: vx.Tty,
watcher: vx.xev.TtyWatcher(Tui) = undefined,
launched: bool = false,

fn render(ctx: *anyopaque, lap_time_ns: u64) void {
    const lap_time_float: f64 = @floatFromInt(lap_time_ns);
    const dt = lap_time_float / std.time.ns_per_s;
    const tui: *Tui = @ptrCast(@alignCast(ctx));
    tui.vaxis.window().hideCursor();

    lu.getMethod(tui.l, "tui", "update");
    lu.getMethod(tui.l, "tui", "update");
    tui.l.pushNumber(dt);
    tui.l.call(2, 0);
    lu.getMethod(tui.l, "tui", "draw");
    lu.getMethod(tui.l, "tui", "draw");
    tui.l.call(1, 0);

    tui.vaxis.render(tui.tty.anyWriter()) catch panic("unable to draw to the terminal!", .{});
}

fn callback(ud: ?*Tui, _: *xev.Loop, _: *vx.xev.TtyWatcher(Tui), event: vx.xev.Event) xev.CallbackAction {
    const tui = ud.?;
    switch (event) {
        inline .key_press, .key_release => |key| {
            keyFn(tui.l, key, event == .key_press);
            lu.render(tui.l);
        },
        .mouse => |m| mouse(tui.l, m),
        .focus_in => {
            lu.getMethod(tui.l, "tui", "window_focus");
            tui.l.pushBoolean(true);
            tui.l.call(1, 0);
        },
        .focus_out => {
            lu.getMethod(tui.l, "tui", "window_focus");
            tui.l.pushBoolean(true);
            tui.l.call(1, 0);
        },
        .paste_start, .paste_end => {}, // since paste is already special, these seem not necessary?
        .paste => |txt| {
            paste(tui.l, txt);
            tui.vaxis.opts.system_clipboard_allocator.?.free(txt);
        },
        .color_report => |_| {},
        .color_scheme => |scheme| lu.setConfig(tui.l, "color_scheme", @tagName(scheme)),
        .winsize => |winsize| {
            tui.vaxis.resize(tui.l.allocator(), tui.tty.anyWriter(), winsize) catch panic("out of memory!", .{});
            tui.vaxis.queueRefresh();
            lu.getSeamstress(tui.l);
            if (tui.l.getField(-1, "tui") == .table) {
                tui.l.remove(-2);
                _ = tui.l.getField(-1, "resize");
                tui.l.remove(-2);
                tui.l.pushInteger(@intCast(winsize.cols));
                tui.l.pushInteger(@intCast(winsize.rows));
                tui.l.call(2, 0);
            } else tui.l.pop(2);
            lu.getSeamstress(tui.l);
            _ = tui.l.getField(-1, "tui");
            tui.l.remove(-2);
            tui.l.pushInteger(@intCast(winsize.cols));
            tui.l.setField(-2, "cols");
            tui.l.pushInteger(@intCast(winsize.rows));
            tui.l.setField(-2, "rows");
            tui.l.pop(1);
            lu.render(tui.l);
        },
    }
    return .rearm;
}

fn formatKey(key: vx.Key, writer: anytype) !void {
    if (key.mods.ctrl) try writer.writeAll("C-");
    if (key.mods.alt) try writer.writeAll("M-");
    if (key.mods.shift and key.shifted_codepoint == null) try writer.writeAll("S-");
    if (key.mods.super) try writer.writeAll("D-");
    if (key.mods.hyper) try writer.writeAll("H-");
    if (key.mods.meta) try writer.writeAll("G-");
    switch (key.codepoint) {
        vx.Key.tab => try writer.writeAll("tab"),
        vx.Key.enter, '\n' => try writer.writeAll("enter"),
        vx.Key.escape => try writer.writeAll("escape"),
        vx.Key.space => try writer.writeAll("space"),
        vx.Key.backspace => try writer.writeAll("backspace"),
        vx.Key.insert, vx.Key.kp_insert => try writer.writeAll("insert"),
        vx.Key.delete, vx.Key.kp_delete => try writer.writeAll("delete"),
        vx.Key.left, vx.Key.kp_left => try writer.writeAll("left"),
        vx.Key.right, vx.Key.kp_right => try writer.writeAll("right"),
        vx.Key.up, vx.Key.kp_up => try writer.writeAll("up"),
        vx.Key.down, vx.Key.kp_down => try writer.writeAll("down"),
        vx.Key.page_up, vx.Key.kp_page_up => try writer.writeAll("page_up"),
        vx.Key.page_down, vx.Key.kp_page_down => try writer.writeAll("page_down"),
        vx.Key.home, vx.Key.kp_home => try writer.writeAll("home"),
        vx.Key.end, vx.Key.kp_end => try writer.writeAll("end"),
        vx.Key.caps_lock => try writer.writeAll("caps_lock"),
        vx.Key.menu => try writer.writeAll("menu"),
        vx.Key.f1...vx.Key.f35 => try writer.print("f{d}", .{key.codepoint - vx.Key.f1 + 1}),
        vx.Key.kp_0...vx.Key.kp_9 => try writer.print("{d}", .{key.codepoint - vx.Key.kp_0}),
        vx.Key.media_play => try writer.writeAll("media_play"),
        vx.Key.media_pause => try writer.writeAll("media_pause"),
        vx.Key.media_play_pause => try writer.writeAll("media_play_pause"),
        vx.Key.media_reverse => try writer.writeAll("media_reverse"),
        vx.Key.media_stop => try writer.writeAll("media_stop"),
        vx.Key.media_fast_forward => try writer.writeAll("media_fast_forward"),
        vx.Key.media_rewind => try writer.writeAll("media_rewind"),
        vx.Key.media_track_next => try writer.writeAll("media_track_next"),
        vx.Key.media_track_previous => try writer.writeAll("media_track_previous"),
        vx.Key.media_record => try writer.writeAll("media_record"),
        vx.Key.lower_volume => try writer.writeAll("lower_volume"),
        vx.Key.raise_volume => try writer.writeAll("raise_volume"),
        vx.Key.mute_volume => try writer.writeAll("mute_volume"),
        vx.Key.left_shift => try writer.writeAll("left_shift"),
        vx.Key.left_control => try writer.writeAll("left_control"),
        vx.Key.left_alt => try writer.writeAll("left_alt"),
        vx.Key.left_super => try writer.writeAll("left_super"),
        vx.Key.left_hyper => try writer.writeAll("left_hyper"),
        vx.Key.left_meta => try writer.writeAll("left_meta"),
        vx.Key.right_shift => try writer.writeAll("right_shift"),
        vx.Key.right_control => try writer.writeAll("right_control"),
        vx.Key.right_alt => try writer.writeAll("right_alt"),
        vx.Key.right_super => try writer.writeAll("right_super"),
        vx.Key.right_hyper => try writer.writeAll("right_hyper"),
        vx.Key.right_meta => try writer.writeAll("right_meta"),
        else => {
            if (key.text) |txt| try writer.writeAll(txt) else {
                var buf: [16]u8 = undefined;
                const len = std.unicode.utf8Encode(if (key.shifted_codepoint) |s| s else key.codepoint, &buf) catch blk: {
                    logger.warn("unexpected codepoint 0x{x}", .{key.codepoint});
                    break :blk 0;
                };
                try writer.writeAll(buf[0..len]);
            }
        },
    }
}

fn keyFn(l: *Lua, key: vx.Key, is_press: bool) void {
    lu.getMethod(l, "tui", if (is_press) "key_down" else "key_up");
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    formatKey(key, stream.writer()) catch unreachable;
    var nargs: i32 = 0;
    _ = l.pushString(buf[0..stream.pos]);
    nargs += 1;
    if (key.text) |txt| {
        _ = l.pushString(txt);
        nargs += 1;
    }
    l.call(nargs, 0);
}

fn formatMouse(m: vx.Mouse, writer: anytype) !void {
    if (m.mods.ctrl) try writer.writeAll("C-");
    if (m.mods.alt) try writer.writeAll("M-");
    if (m.mods.shift) try writer.writeAll("S-");
    try writer.writeAll(@tagName(m.button));
}

fn mouse(l: *Lua, m: vx.Mouse) void {
    switch (m.button) {
        .wheel_up, .wheel_down => {
            lu.getMethod(l, "tui", "scroll");
            l.pushInteger(if (m.button == .wheel_up) 1 else -1);
            l.call(1, 0);
        },
        else => {
            var buf: [128]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            formatMouse(m, stream.writer()) catch unreachable;
            switch (m.type) {
                .press => lu.getMethod(l, "tui", "mouse_down"),
                .release => lu.getMethod(l, "tui", "mouse_up"),
                .motion => lu.getMethod(l, "tui", "hover"),
                .drag => lu.getMethod(l, "tui", "drag"),
            }
            _ = l.pushString(buf[0..stream.pos]);
            l.pushInteger(@intCast(m.col + 1));
            l.pushInteger(@intCast(m.row + 1));
            l.call(3, 0);
        },
    }
}

fn paste(l: *Lua, txt: []const u8) void {
    lu.getMethod(l, "tui", "paste");
    var iterator = std.mem.splitScalar(u8, txt, '\n');
    var idx: ziglua.Integer = 1;
    l.newTable();
    while (iterator.next()) |token| : (idx += 1) {
        _ = l.pushString(token);
        l.setIndex(-2, idx);
    }
    lu.doCall(l, 1, 0);
}

fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    if (m.self) |_| return;
    const self = try allocator.create(Tui);
    errdefer allocator.destroy(self);
    m.self = self;
    self.* = .{
        .l = l,
        .tty = try vx.Tty.init(),
        .vaxis = try vx.Vaxis.init(allocator, .{
            .system_clipboard_allocator = allocator,
        }),
    };
    @import("tui/color.zig").registerSeamstress(l);
    @import("tui/style.zig").registerSeamstress(l);
    @import("tui/line.zig").registerSeamstress(l, self);
    @import("tui/canvas.zig").registerSeamstress(l, self);
    lu.registerSeamstress(l, "tui", "redraw", redraw, self);
}

fn deinit(m: *Module, l: *Lua, allocator: std.mem.Allocator, kind: Cleanup) void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return));
    const wheel = lu.getWheel(l);
    wheel.render = null;
    self.vaxis.deinit(allocator, self.tty.anyWriter());
    self.tty.deinit();
    if (kind != .full) return;
    allocator.destroy(self);
    m.self = null;
}

fn launch(m: *const Module, _: *Lua, wheel: *Wheel) anyerror!void {
    const self: *Tui = @ptrCast(@alignCast(m.self.?));
    if (self.launched) return;
    self.launched = true;
    wheel.render = .{
        .ctx = self,
        .render_fn = render,
    };
    try self.watcher.init(&self.tty, &self.vaxis, &wheel.loop, self, callback);
    try self.vaxis.enterAltScreen(self.tty.anyWriter());
    try self.vaxis.setMouseMode(self.tty.anyWriter(), true);
    try self.vaxis.queryTerminalSend(self.tty.anyWriter());
}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

fn redraw(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const wheel = lu.getWheel(l);
    render(tui, wheel.timer.lap());
    return 0;
}

const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
const Module = @import("../module.zig");
const Seamstress = @import("../seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const Wheel = @import("../wheel.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const vx = @import("vaxis");
const panic = std.debug.panic;
const lu = @import("../lua_util.zig");
const xev = @import("xev");
const builtin = @import("builtin");
const logger = std.log.scoped(.tui);

test "ref" {
    _ = Tui;
    _ = @import("tui/canvas.zig");
    _ = @import("tui/color.zig");
    _ = @import("tui/line.zig");
    _ = @import("tui/style.zig");
}
