/// TUI interaction module
// @module _seamstress.tui
const Tui = @This();

launched: bool,
vaxis: vx.Vaxis,
tty: vx.Tty,
watcher: vx.xev.TtyWatcher(Tui) = undefined,
c_c: xev.Completion = .{},

fn callback(ud: ?*Tui, loop: *xev.Loop, _: *vx.xev.TtyWatcher(Tui), event: vx.xev.Event) xev.CallbackAction {
    const tui = ud.?;
    if (!tui.launched) return .rearm;
    const l = Wheel.getLua(loop);
    switch (event) {
        inline .key_press, .key_release => |key| keyFn(l, key, event == .key_press),
        .mouse => |m| mouse(l, m),
        .focus_in => {
            lu.preparePublish(l, &.{ "tui", "window_focus" });
            l.pushBoolean(true);
            l.call(2, 1);
            const draw = lu.anyTruthy(l);
            l.pop(1);
            if (draw) {
                lu.preparePublish(l, &.{"draw"});
                l.call(1, 0);
            }
        },
        .focus_out => {
            lu.preparePublish(l, &.{ "tui", "window_focus" });
            l.pushBoolean(false);
            l.call(2, 1);
            const draw = lu.anyTruthy(l);
            l.pop(1);
            if (draw) {
                lu.preparePublish(l, &.{"draw"});
                l.call(1, 0);
            }
        },
        .paste_start, .paste_end => {}, // since paste is already special, these seem not necessary?
        .paste => |txt| {
            paste(l, txt);
            tui.vaxis.opts.system_clipboard_allocator.?.free(txt);
        },
        .color_report => |_| {},
        .color_scheme => |scheme| lu.setConfig(l, "color_scheme", @tagName(scheme)),
        .winsize => |winsize| {
            tui.vaxis.resize(l.allocator(), tui.tty.anyWriter(), winsize) catch panic("out of memory!", .{});
            lu.getSeamstress(l);
            _ = l.getField(-1, "tui");
            l.remove(-2);
            l.pushInteger(@intCast(winsize.cols));
            l.setField(-2, "cols");
            l.pushInteger(@intCast(winsize.rows));
            l.setField(-2, "rows");
            l.pop(1);
            lu.preparePublish(l, &.{ "tui", "resize" });
            l.pushInteger(@intCast(winsize.cols));
            l.pushInteger(@intCast(winsize.rows));
            l.call(3, 1);
            const draw = lu.anyTruthy(l);
            if (draw) {
                lu.preparePublish(l, &.{"draw"});
                l.call(1, 0);
            }
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
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    formatKey(key, stream.writer()) catch unreachable;
    lu.preparePublish(l, &.{ "tui", if (is_press) "key_down" else "key_up", buf[0..stream.pos] });
    var nargs: i32 = 1;
    _ = l.pushString(buf[0..stream.pos]);
    nargs += 1;
    if (key.text) |txt| {
        _ = l.pushString(txt);
        nargs += 1;
    }
    l.call(nargs, 1);
    const draw = lu.anyTruthy(l);
    l.pop(1);
    if (draw) {
        lu.preparePublish(l, &.{"draw"});
        l.call(1, 0);
    }
}

fn formatMouse(m: vx.Mouse, writer: anytype) !void {
    if (m.mods.ctrl) try writer.writeAll("C-");
    if (m.mods.alt) try writer.writeAll("M-");
    if (m.mods.shift) try writer.writeAll("S-");
    try writer.writeAll(@tagName(m.button));
}

fn mouse(l: *Lua, m: vx.Mouse) void {
    logger.debug("{any}", .{m});
    switch (m.button) {
        .wheel_up, .wheel_down => {
            lu.preparePublish(l, &.{ "tui", "scroll", if (m.button == .wheel_down) "down" else "up" });
            l.pushInteger(if (m.button == .wheel_up) 1 else -1);
            l.pushInteger(@intCast(m.col + 1));
            l.pushInteger(@intCast(m.row + 1));
            l.call(4, 1);
        },
        else => {
            var buf: [128]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            formatMouse(m, stream.writer()) catch unreachable;
            switch (m.type) {
                .press => lu.preparePublish(l, &.{ "tui", "mouse_down", buf[0..stream.pos] }),
                .release => lu.preparePublish(l, &.{ "tui", "mouse_up", buf[0..stream.pos] }),
                .motion => lu.preparePublish(l, &.{ "tui", "hover", buf[0..stream.pos] }),
                .drag => lu.preparePublish(l, &.{ "tui", "drag", buf[0..stream.pos] }),
            }
            _ = l.pushString(buf[0..stream.pos]);
            l.pushInteger(@intCast(m.col + 1));
            l.pushInteger(@intCast(m.row + 1));
            l.call(4, 1);
        },
    }
    const draw = lu.anyTruthy(l);
    l.pop(1);
    if (draw) {
        lu.preparePublish(l, &.{"draw"});
        l.call(1, 0);
    }
}

fn paste(l: *Lua, txt: []const u8) void {
    lu.preparePublish(l, &.{ "tui", "paste" });
    var iterator = std.mem.splitScalar(u8, txt, '\n');
    var idx: ziglua.Integer = 1;
    l.newTable();
    while (iterator.next()) |token| : (idx += 1) {
        _ = l.pushString(token);
        l.setIndex(-2, idx);
    }
    l.call(2, 1);
    const draw = lu.anyTruthy(l);
    l.pop(1);
    if (draw) {
        lu.preparePublish(l, &.{"draw"});
        l.call(1, 0);
    }
}

fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    if (m.self) |_| return;
    const self = try allocator.create(Tui);
    errdefer allocator.destroy(self);
    m.self = self;
    self.* = .{
        .tty = undefined,
        .vaxis = undefined,
        .launched = false,
    };
    @import("tui/color.zig").registerSeamstress(l);
    @import("tui/style.zig").registerSeamstress(l);
    @import("tui/line.zig").registerSeamstress(l, self);
    @import("tui/canvas.zig").registerSeamstress(l, self);
    lu.registerSeamstress(l, "tui", "renderCommit", redraw, self);
    lu.registerSeamstress(l, "tui", "setAltScreen", setAlt, self);
}

fn customDeinit(tui: *Tui, allocator: ?std.mem.Allocator, tty: std.io.AnyWriter, erase: bool) !void {
    if (erase) {
        try tty.writeByteNTimes('\r', tui.vaxis.screen.height -| 5);
        try tty.writeAll(vx.ctlseqs.erase_below_cursor);
    }
    if (tui.vaxis.state.kitty_keyboard) {
        try tty.writeAll(vx.ctlseqs.csi_u_pop);
        tui.vaxis.state.kitty_keyboard = false;
    }
    if (tui.vaxis.state.mouse) {
        try tui.vaxis.setMouseMode(tty, false);
    }
    if (tui.vaxis.state.bracketed_paste) {
        try tui.vaxis.setBracketedPaste(tty, false);
    }
    if (tui.vaxis.state.color_scheme_updates) {
        try tty.writeAll(vx.ctlseqs.color_scheme_reset);
        tui.vaxis.state.color_scheme_updates = false;
    }
    try tty.writeAll(vx.ctlseqs.show_cursor);

    if (allocator) |a| {
        tui.vaxis.screen.deinit(a);
        tui.vaxis.screen_last.deinit(a);
    }
    if (tui.vaxis.renders > 0) {
        const tpr = @divTrunc(tui.vaxis.render_dur, tui.vaxis.renders);
        log.debug("total renders = {d}\r", .{tui.vaxis.renders});
        log.debug("microseconds per render = {d}\r", .{tpr});
    }
    tui.vaxis.unicode.deinit();
}

const log = std.log.scoped(.vaxis);

fn deinit(m: *Module, _: *Lua, allocator: std.mem.Allocator, kind: Cleanup) void {
    const self: *Tui = @ptrCast(@alignCast(m.self orelse return));
    if (self.launched) {
        self.launched = false;
        if (!self.vaxis.state.alt_screen) {
            self.customDeinit(if (kind == .full) allocator else null, self.tty.anyWriter(), false) catch {};
        } else self.vaxis.deinit(if (kind == .full) allocator else null, self.tty.anyWriter());
        self.tty.deinit();
        act.?.ctx = null;
    }
    if (kind != .full) return;
    allocator.destroy(self);
    m.self = null;
}

fn handleKill(_: i32) callconv(.C) void {
    if (act) |a| if (a.ctx) |self| {
        if (!self.vaxis.state.alt_screen) {
            self.customDeinit(null, self.tty.anyWriter(), true) catch {};
        } else self.vaxis.deinit(null, self.tty.anyWriter());
        self.tty.deinit();
    };
    std.process.exit(1);
}

var act: ?struct {
    action: std.posix.Sigaction,
    ctx: ?*Tui,
} = null;

fn launch(m: *const Module, l: *Lua, wheel: *Wheel) anyerror!void {
    const self: *Tui = @ptrCast(@alignCast(m.self.?));
    if (self.launched) return;
    self.launched = true;
    self.tty = try vx.Tty.init();
    self.vaxis = try vx.Vaxis.init(l.allocator(), .{ .system_clipboard_allocator = l.allocator() });
    act = .{
        .action = .{
            .handler = .{ .handler = handleKill },
            .mask = switch (builtin.os.tag) {
                .macos => 0,
                .linux => std.posix.empty_sigset,
                else => @compileError("os not supported"),
            },
            .flags = 0,
        },
        .ctx = self,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &act.?.action, null) catch unreachable;
    try self.watcher.init(&self.tty, &self.vaxis, &wheel.loop, self, callback);
    try self.vaxis.enterAltScreen(self.tty.anyWriter());
    try self.vaxis.setMouseMode(self.tty.anyWriter(), true);
    try self.vaxis.queryTerminalSend(self.tty.anyWriter());
    logger.debug("launch TUI", .{});
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
    if (tui.launched) tui.vaxis.render(tui.tty.anyWriter()) catch panic("unable to draw to the terminal!", .{});
    return 0;
}

fn setAlt(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const alt = l.toBoolean(1);
    if (tui.vaxis.state.alt_screen and !alt) {
        tui.vaxis.exitAltScreen(tui.tty.anyWriter()) catch unreachable;
        tui.vaxis.setMouseMode(tui.tty.anyWriter(), false) catch unreachable;
    } else if (!tui.vaxis.state.alt_screen and alt) {
        tui.vaxis.enterAltScreen(tui.tty.anyWriter()) catch unreachable;
        tui.vaxis.setMouseMode(tui.tty.anyWriter(), true) catch unreachable;
    }
    return 0;
}

// fn resetTerminal(l: *Lua) i32 {
// const erase = l.toBoolean(1);
// const self = lu.closureGetContext(l, Tui);
// if (!self.launched) return 0;
// self.launched = false;
// if (erase) self.vaxis.deinit(l.allocator(), self.tty.anyWriter()) else {
// if (self.vaxis.state.alt_screen) self.vaxis.exitAltScreen(self.tty.anyWriter()) catch {};
// self.vaxis.deinit(l.allocator(), std.io.null_writer.any());
// }
// self.tty.deinit();
// return 0;
// }

const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
const Promise = @import("../async.zig");
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
