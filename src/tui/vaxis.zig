const VaxisLayer = @This();

vaxis: vx.Vaxis,
file: xev.File,
c: xev.Completion = .{},
parser: vx.Parser,
buf: [1024]u8 = undefined,
idx: usize = 0,
allocator: std.mem.Allocator,
winsize: vx.Winsize,

pub fn deinit(self: *VaxisLayer, kind: Cleanup) void {
    self.vaxis.deinit(if (kind == .full) self.allocator else null);
}

pub fn init(self: *VaxisLayer, allocator: std.mem.Allocator) !void {
    self.* = .{
        .vaxis = try vx.Vaxis.init(allocator, .{
            .system_clipboard_allocator = allocator,
        }),
        .file = undefined,
        .parser = .{ .grapheme_data = &self.vaxis.unicode.grapheme_data },
        .allocator = allocator,
        .winsize = undefined,
    };
    self.vaxis.tty = try vx.Tty.init();
    self.file = xev.File.initFd(self.vaxis.tty.?.fd);
}

pub fn launch(self: *VaxisLayer, wheel: *Wheel) void {
    self.winsize = vx.Tty.getWinsize(self.vaxis.tty.?.fd) catch panic("unable to get window size!", .{});

    self.vaxis.queryTerminalSend() catch panic("unable to query terminal!", .{});
    // handles SIGWINCH
    const WinchHandler = struct {
        var vax: *VaxisLayer = undefined;
        fn init(vx_arg: *VaxisLayer) !void {
            vax = vx_arg;
            var act: std.posix.Sigaction = .{
                .handler = .{ .handler = @This().handleWinch },
                .mask = switch (builtin.os.tag) {
                    .macos => 0,
                    .linux => std.posix.empty_sigset,
                    else => @compileError("os not supported"),
                },
                .flags = 0,
            };
            try std.posix.sigaction(std.posix.SIG.WINCH, &act, null);
        }
        fn handleWinch(_: c_int) callconv(.C) void {
            vax.winsize = vx.Tty.getWinsize(vax.vaxis.tty.?.fd) catch return;
        }
    };
    WinchHandler.init(self) catch panic("unable to set signal handler!", .{});

    self.file.read(&wheel.loop, &self.c, .{ .slice = &self.buf }, VaxisLayer, self, readCallback);
}

fn readCallback(
    userdata: ?*VaxisLayer,
    l: *xev.Loop,
    c: *xev.Completion,
    file: xev.File,
    buf: xev.ReadBuffer,
    r: xev.ReadError!usize,
) xev.CallbackAction {
    const self = userdata.?;
    const len = r catch panic("unable to read input!", .{});
    var start: usize = 0;
    var quit: bool = false;
    const tui: *Tui = @fieldParentPtr("vaxis", userdata.?);
    while (start < len) {
        const res = self.parser.parse(buf.slice[start..len], self.allocator) catch unreachable;
        if (res.n == 0) {
            const initial_start = start;
            while (start < len) : (start += 1) {
                self.buf[start - initial_start] = buf.slice[start];
            }
            self.idx = start - initial_start + 1;
            continue;
        }
        self.idx = 0;
        start += res.n;
        const event = res.event orelse continue;
        switch (event) {
            .key_press => |key| {
                if (tui.handlePress(key)) quit = true;
            },
            .key_release => |key| tui.handleRelease(key),
            .mouse => |mouse| tui.handleMouse(self.vaxis.translateMouse(mouse)),
            .cap_kitty_keyboard => self.vaxis.caps.kitty_keyboard = true,
            .cap_kitty_graphics => self.vaxis.caps.kitty_graphics = true,
            .cap_rgb => self.vaxis.caps.rgb = true,
            .cap_unicode => {
                self.vaxis.caps.unicode = .unicode;
                self.vaxis.screen.width_method = .unicode;
            },
            .cap_sgr_pixels => self.vaxis.caps.sgr_pixels = true,
            .cap_color_scheme_updates => self.vaxis.caps.color_scheme_updates = true,
            .cap_da1 => self.vaxis.enableDetectedFeatures() catch panic("unable to enable TUI features!", .{}),
            .focus_in => tui.focusIn(),
            .focus_out => tui.focusOut(),
            .paste_start => tui.pasteStart(),
            .paste_end => tui.pasteEnd(),
            .paste => |txt| tui.paste(txt),
            .color_report => |report| tui.colorReport(report),
            .color_scheme => |scheme| tui.colorScheme(scheme),
        }
    }
    if (quit) {
        lu.getWheel(tui.l).quit();
        return .disarm;
    }
    file.read(l, c, .{ .slice = self.buf[self.idx..] }, VaxisLayer, self, readCallback);
    return .disarm;
}

const std = @import("std");
const vx = @import("vaxis");
const xev = @import("libxev");
const Tui = @import("../tui.zig");
const logger = std.log.scoped(.tui);
const panic = std.debug.panic;
const Wheel = @import("../wheel.zig");
const builtin = @import("builtin");
const Cleanup = @import("../seamstress.zig").Cleanup;
const lu = @import("../lua_util.zig");
