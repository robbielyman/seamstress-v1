pub const c = @import("c.zig").c;
const std = @import("std");

pub const Error = error{NotCursesFailed};

test {
    const T = @This();
    inline for (comptime std.meta.declarations(@This())) |decl| {
        if (comptime std.mem.eql(u8, decl.name, "c")) continue;
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .Struct, .Enum, .Union, .Opaque => std.testing.refAllDeclsRecursive(@field(T, decl.name)),
                else => {},
            }
        }
        _ = &@field(T, decl.name);
    }
}

pub const Channel = packed struct(u32) {
    blue: u8 = 0,
    green: u8 = 0,
    red: u8 = 0,
    _unused: u3 = 0,
    palette: bool = false,
    alpha: enum(u2) {
        Opaque,
        Blend,
        Transparent,
        HighContrast,
    } = .Opaque,
    non_default: bool = false,
    _padding: bool = false,

    test "matches C" {
        const c_vals: []const u64 = &.{
            c.NC_BGDEFAULT_MASK,
            c.NC_BG_RGB_MASK,
            c.NCALPHA_HIGHCONTRAST,
            c.NCALPHA_BLEND,
            c.NCALPHA_TRANSPARENT,
            c.NCALPHA_OPAQUE,
            c.NC_BG_PALETTE,
        };
        const z_vals: []const Channel = &.{
            .{ .non_default = true },
            .{ .red = 255, .green = 255, .blue = 255 },
            .{ .alpha = .HighContrast },
            .{ .alpha = .Blend },
            .{ .alpha = .Transparent },
            .{ .alpha = .Opaque },
            .{ .palette = true },
        };
        for (c_vals, z_vals) |c_val, z_val| {
            const intermediate: u32 = @bitCast(z_val);
            try std.testing.expectEqual(c_val, @as(u64, intermediate));
        }
    }
};

pub const Channels = packed struct {
    fg: Channel,
    bg: Channel,
};

pub const Palette = extern struct {
    chans: [256]Channel,

    pub fn free(p: *Palette) void {
        c.ncpalette_free(@ptrCast(p));
    }
};

pub const Input = struct {
    id: u32,
    y: i32,
    x: i32,
    utf8: [5]u8,
    ev_type: EvType,
    modifiers: Modifiers,
    ypx: i32,
    xpx: i32,

    pub const EvType = enum { unknown, press, repeat, release };

    pub const Modifiers = packed struct(u32) {
        shift: bool,
        alt: bool,
        ctrl: bool,
        super: bool,
        hyper: bool,
        meta: bool,
        capslock: bool,
        numlock: bool,
        _padding: u24 = 0,
    };
};

pub const Notcurses = struct {
    handle: *c.notcurses,

    pub fn coreInit(opts: Options, file: ?*c.FILE) Error!Notcurses {
        const c_opts: c.notcurses_options = .{
            .termtype = if (opts.term_type) |p| p.ptr else null,
            .loglevel = @intFromEnum(opts.log_level),
            .margin_t = @intCast(opts.margin_t),
            .margin_r = @intCast(opts.margin_r),
            .margin_b = @intCast(opts.margin_b),
            .margin_l = @intCast(opts.margin_l),
            .flags = @bitCast(opts.flags),
        };
        return .{
            .handle = c.notcurses_core_init(&c_opts, file) orelse return error.NotCursesFailed,
        };
    }

    pub fn newPalette(nc: Notcurses) *Palette {
        return @ptrCast(c.ncpalette_new(nc.handle));
    }

    pub fn usePalette(nc: Notcurses, p: *const Palette) Error!void {
        try unwrap(c.ncpalette_use(nc.handle, @ptrCast(p)));
    }

    pub fn enterAlternateScreen(self: Notcurses) Error!void {
        try unwrap(c.notcurses_enter_alternate_screen(self.handle));
    }

    pub fn leaveAlternateScreen(self: Notcurses) Error!void {
        try unwrap(c.notcurses_leave_alternate_screen(self.handle));
    }

    pub fn stop(self: *Notcurses) Error!void {
        try unwrap(c.notcurses_stop(self.handle));
        self.* = undefined;
    }

    pub fn render(self: Notcurses) Error!void {
        try unwrap(c.notcurses_render(self.handle));
    }

    pub fn refresh(self: Notcurses) Error!struct { u32, u32 } {
        var y: u32 = undefined;
        var x: u32 = undefined;
        try unwrap(c.notcurses_refresh(self.handle, &y, &x));
        return .{ y, x };
    }

    pub fn stdplane(self: Notcurses) Error!Plane {
        return .{
            .handle = c.notcurses_stdplane(self.handle) orelse return error.NotCursesFailed,
        };
    }

    pub const InputError = error{NoInput} || Error;

    pub fn getBlocking(self: Notcurses) InputError!Input {
        var ni: c.ncinput = undefined;
        const err = c.notcurses_get_blocking(self.handle, &ni);
        if (err == 0) return error.NoInput;
        if (err == std.math.maxInt(u32)) return error.NotCursesFailed;
        return .{
            .ev_type = @enumFromInt(ni.evtype),
            .id = ni.id,
            .modifiers = @bitCast(ni.modifiers),
            .utf8 = ni.utf8,
            .x = ni.x,
            .y = ni.y,
            .xpx = ni.xpx,
            .ypx = ni.ypx,
        };
    }

    pub fn get(self: Notcurses) InputError!Input {
        var ni: c.ncinput = undefined;
        const err = c.notcurses_get_nblock(self.handle, &ni);
        if (err == 0) return error.NoInput;
        if (err == std.math.maxInt(u32)) return error.NotCursesFailed;
        return .{
            .ev_type = @enumFromInt(ni.evtype),
            .id = ni.id,
            .modifiers = @bitCast(ni.modifiers),
            .utf8 = ni.utf8,
            .x = ni.x,
            .y = ni.y,
            .xpx = ni.xpx,
            .ypx = ni.ypx,
        };
    }

    pub fn inputReadyFd(self: Notcurses) std.fs.File {
        const fd = c.notcurses_inputready_fd(self.handle);
        const file: std.fs.File = .{
            .handle = fd,
        };
        return file;
    }

    pub const Options = struct {
        term_type: ?[:0]const u8 = null,
        log_level: LogLevel = .Panic,
        margin_t: u32 = 0,
        margin_r: u32 = 0,
        margin_b: u32 = 0,
        margin_l: u32 = 0,
        flags: Flags = .{},

        pub const LogLevel = enum(c_int) {
            Silent = -1,
            Panic = 0,
            Fatal = 1,
            Error = 2,
            Warning = 3,
            Info = 4,
            Verbose = 5,
            Debug = 6,
            Trace = 7,
        };

        pub const Flags = packed struct(u64) {
            inhibit_setlocale: bool = false,
            no_clear_bitmaps: bool = false,
            no_winch_sighandler: bool = false,
            no_quit_sighandlers: bool = false,
            preserve_cursor: bool = false,
            suppress_banners: bool = false,
            no_alternate_screen: bool = false,
            no_font_changes: bool = false,
            drain_input: bool = false,
            scrolling: bool = false,
            _padding: u54 = 0,

            pub const cli_mode: Flags = .{
                .no_alternate_screen = true,
                .no_clear_bitmaps = true,
                .preserve_cursor = true,
                .scrolling = true,
            };
        };

        test "matches C" {
            const c_vals: []const u64 = &.{
                c.NCOPTION_CLI_MODE,
                c.NCOPTION_SCROLLING,
                c.NCOPTION_DRAIN_INPUT,
                c.NCOPTION_NO_FONT_CHANGES,
                c.NCOPTION_PRESERVE_CURSOR,
                c.NCOPTION_NO_CLEAR_BITMAPS,
                c.NCOPTION_SUPPRESS_BANNERS,
                c.NCOPTION_INHIBIT_SETLOCALE,
                c.NCOPTION_NO_ALTERNATE_SCREEN,
                c.NCOPTION_NO_QUIT_SIGHANDLERS,
                c.NCOPTION_NO_WINCH_SIGHANDLER,
            };
            const zig_vals: []const Flags = &.{
                Flags.cli_mode,
                .{ .scrolling = true },
                .{ .drain_input = true },
                .{ .no_font_changes = true },
                .{ .preserve_cursor = true },
                .{ .no_clear_bitmaps = true },
                .{ .suppress_banners = true },
                .{ .inhibit_setlocale = true },
                .{ .no_alternate_screen = true },
                .{ .no_quit_sighandlers = true },
                .{ .no_winch_sighandler = true },
            };
            for (c_vals, zig_vals) |c_val, z_val| {
                try std.testing.expectEqual(c_val, @as(u64, @bitCast(z_val)));
            }
        }
    };
};

pub const CResizeCallback = fn (?*c.ncplane) callconv(.C) c_int;
pub const ResizeCallback = fn (Plane) anyerror!void;

pub fn wrap(comptime Fn: ResizeCallback) CResizeCallback {
    return struct {
        fn Cfn(n: ?*c.ncplane) callconv(.C) c_int {
            const p: Plane = .{
                .handle = n orelse return -1,
            };
            @call(.always_inline, Fn, .{p}) catch return -1;
            return 0;
        }
    }.Cfn;
}

pub const Alignment = enum(c_uint) {
    unaligned,
    left_or_top,
    center,
    right_or_bottom,
};

test "matches C" {
    const c_vals: []const c_uint = &.{
        c.NCALIGN_UNALIGNED,
        c.NCALIGN_TOP,
        c.NCALIGN_LEFT,
        c.NCALIGN_RIGHT,
        c.NCALIGN_BOTTOM,
        c.NCALIGN_CENTER,
    };
    const z_vals: []const Alignment = &.{
        .unaligned,
        .left_or_top,
        .left_or_top,
        .right_or_bottom,
        .right_or_bottom,
        .center,
    };
    for (c_vals, z_vals) |c_val, z_val| {
        try std.testing.expectEqual(c_val, @intFromEnum(z_val));
    }
}

pub const Plane = struct {
    handle: *c.ncplane,

    pub fn create(parent_plane: Plane, opts: Options) Error!Plane {
        const c_opts: c.ncplane_options = .{
            .y = opts.y,
            .x = opts.x,
            .rows = opts.rows,
            .cols = opts.cols,
            .userptr = opts.userdata,
            .name = opts.name,
            .resizecb = opts.resize_cb,
            .flags = @bitCast(opts.flags),
            .margin_b = opts.margin_b,
            .margin_r = opts.margin_r,
        };
        return .{
            .handle = c.ncplane_create(parent_plane.handle, &c_opts) orelse return error.NotCursesFailed,
        };
    }

    pub fn parent(self: Plane) Error!Plane {
        return .{
            .handle = c.ncplane_parent(self.handle) orelse return error.NotCursesFailed,
        };
    }

    pub fn destroy(plane: *Plane) Error!void {
        try unwrap(c.ncplane_destroy(plane.handle));
        plane.* = undefined;
    }

    /// order y, x to follow notcurses practice
    pub fn dimensions(self: Plane) struct { u32, u32 } {
        var y: u32 = undefined;
        var x: u32 = undefined;
        c.ncplane_dim_yx(self.handle, &y, &x);
        return .{ y, x };
    }

    pub fn resize(
        self: Plane,
        keep_y: i32,
        keep_x: i32,
        keep_len_y: u32,
        keep_len_x: u32,
        y_off: i32,
        x_off: i32,
        y_len: u32,
        x_len: u32,
    ) Error!void {
        try unwrap(c.ncplane_resize(
            self.handle,
            keep_y,
            keep_x,
            keep_len_y,
            keep_len_x,
            y_off,
            x_off,
            y_len,
            x_len,
        ));
    }

    pub fn resizeSimple(self: Plane, y_len: u32, x_len: u32) Error!void {
        try unwrap(c.ncplane_resize_simple(self.handle, y_len, x_len));
    }

    pub fn moveYx(self: Plane, y: i32, x: i32) Error!void {
        try unwrap(c.ncplane_move_yx(self.handle, y, x));
    }

    pub fn moveRel(self: Plane, y: i32, x: i32) Error!void {
        try unwrap(c.ncplane_move_rel(self.handle, y, x));
    }

    pub fn setBaseCell(self: Plane, cell: *const Cell) Error!void {
        try unwrap(c.ncplane_set_base_cell(self.handle, @ptrCast(cell)));
    }

    pub fn putText(self: Plane, y: i32, a: Alignment, text: [:0]const u8) Error!struct { i32, usize } {
        var bytes: usize = undefined;
        const err = c.ncplane_puttext(self.handle, y, @intFromEnum(a), text.ptr, &bytes);
        try unwrap(err);
        return .{ err, bytes };
    }

    pub fn setFg(self: Plane, fg: Channel) Channels {
        const chans = c.ncplane_set_fchannel(self.handle, @bitCast(fg));
        return @bitCast(chans);
    }

    pub fn setBg(self: Plane, bg: Channel) Channels {
        const chans = c.ncplane_set_bchannel(self.handle, @bitCast(bg));
        return @bitCast(chans);
    }

    pub fn setColors(self: Plane, chans: Channels) void {
        c.ncplane_set_channels(self.handle, @bitCast(chans));
    }

    pub fn loadCell(self: Plane, cell: *Cell, gcluster: [*:0]const u8) Error!usize {
        const err = c.nccell_load(self.handle, @ptrCast(cell), gcluster);
        try unwrap(err);
        return @max(err, 0);
    }

    pub fn primeCell(self: Plane, cell: *Cell, gcluster: [*:0]const u8, mask: Cell.Mask, fg: Channel, bg: Channel) Error!usize {
        cell.fg = fg;
        cell.bg = bg;
        cell.mask = mask;
        const err = c.nccell_load(self.handle, @ptrCast(cell), gcluster);
        try unwrap(err);
        return @max(err, 0);
    }

    pub fn duplicateCell(self: Plane, dst: *Cell, src: *const Cell) Error!void {
        try unwrap(c.nccell_duplicate(self.handle, @ptrCast(dst), @ptrCast(src)));
    }

    pub fn releaseCell(self: Plane, cell: *Cell) void {
        c.nccell_release(self.handle, @ptrCast(cell));
    }

    pub fn releaseBox(self: Plane, box_ptr: *Box) void {
        c.nccell_release(self.handle, @ptrCast(&box_ptr.ul));
        c.nccell_release(self.handle, @ptrCast(&box_ptr.ur));
        c.nccell_release(self.handle, @ptrCast(&box_ptr.ll));
        c.nccell_release(self.handle, @ptrCast(&box_ptr.lr));
        c.nccell_release(self.handle, @ptrCast(&box_ptr.vline));
        c.nccell_release(self.handle, @ptrCast(&box_ptr.hline));
    }

    pub fn loadBox(self: Plane, styles: Cell.Mask, channels: Channels, gclusters: [*:0]const u8) Error!Box {
        var ret: Box = undefined;
        try unwrap(c.nccells_load_box(
            self.handle,
            @bitCast(styles),
            @bitCast(channels),
            @ptrCast(&ret.ul),
            @ptrCast(&ret.ur),
            @ptrCast(&ret.ll),
            @ptrCast(&ret.lr),
            @ptrCast(&ret.hline),
            @ptrCast(&ret.vline),
            gclusters,
        ));
        return ret;
    }

    pub const BoxPreset = enum { ascii, double, rounded, light, heavy };

    pub fn loadBoxPreset(self: Plane, styles: Cell.Mask, channels: Channels, preset: BoxPreset) Error!Box {
        var ret: Box = undefined;
        const err = switch (preset) {
            .ascii => c.nccells_ascii_box(
                self.handle,
                @bitCast(styles),
                @bitCast(channels),
                @ptrCast(&ret.ul),
                @ptrCast(&ret.ur),
                @ptrCast(&ret.ll),
                @ptrCast(&ret.lr),
                @ptrCast(&ret.hline),
                @ptrCast(&ret.vline),
            ),
            .double => c.nccells_double_box(
                self.handle,
                @bitCast(styles),
                @bitCast(channels),
                @ptrCast(&ret.ul),
                @ptrCast(&ret.ur),
                @ptrCast(&ret.ll),
                @ptrCast(&ret.lr),
                @ptrCast(&ret.hline),
                @ptrCast(&ret.vline),
            ),
            .rounded => c.nccells_rounded_box(
                self.handle,
                @bitCast(styles),
                @bitCast(channels),
                @ptrCast(&ret.ul),
                @ptrCast(&ret.ur),
                @ptrCast(&ret.ll),
                @ptrCast(&ret.lr),
                @ptrCast(&ret.hline),
                @ptrCast(&ret.vline),
            ),
            .light => c.nccells_light_box(
                self.handle,
                @bitCast(styles),
                @bitCast(channels),
                @ptrCast(&ret.ul),
                @ptrCast(&ret.ur),
                @ptrCast(&ret.ll),
                @ptrCast(&ret.lr),
                @ptrCast(&ret.hline),
                @ptrCast(&ret.vline),
            ),
            .heavy => c.nccells_heavy_box(
                self.handle,
                @bitCast(styles),
                @bitCast(channels),
                @ptrCast(&ret.ul),
                @ptrCast(&ret.ur),
                @ptrCast(&ret.ll),
                @ptrCast(&ret.lr),
                @ptrCast(&ret.hline),
                @ptrCast(&ret.vline),
            ),
        };
        try unwrap(err);
        return ret;
    }

    pub fn box(self: Plane, opts: *const Box, flags: Box.Flags, ystop: u32, xstop: u32) Error!void {
        try unwrap(c.ncplane_box(
            self.handle,
            @ptrCast(&opts.ul),
            @ptrCast(&opts.ur),
            @ptrCast(&opts.ll),
            @ptrCast(&opts.lr),
            @ptrCast(&opts.hline),
            @ptrCast(&opts.vline),
            ystop,
            xstop,
            @bitCast(flags),
        ));
    }

    pub fn perimeter(self: Plane, opts: *const Box, flags: Box.Flags) Error!void {
        try unwrap(c.ncplane_perimeter(
            self.handle,
            @ptrCast(&opts.ul),
            @ptrCast(&opts.ur),
            @ptrCast(&opts.ll),
            @ptrCast(&opts.lr),
            @ptrCast(&opts.hline),
            @ptrCast(&opts.vline),
            @bitCast(flags),
        ));
    }

    pub fn polyFill(self: Plane, y: i32, x: i32, cell: *const Cell) Error!usize {
        const err = c.ncplane_polyfill_yx(self.handle, y, x, @ptrCast(cell));
        try unwrap(err);
        return @max(0, err);
    }

    pub fn format(self: Plane, y: i32, x: i32, y_len: u32, x_len: u32, mask: Cell.Mask) Error!usize {
        const err = c.ncplane_format(self.handle, y, x, y_len, x_len, @bitCast(mask));
        try unwrap(err);
        return @max(0, err);
    }

    pub fn stain(self: Plane, y: i32, x: i32, y_len: u32, x_len: u32, ul: Channels, ur: Channels, ll: Channels, lr: Channels) Error!usize {
        const err = c.ncplane_stain(
            self.handle,
            y,
            x,
            y_len,
            x_len,
            @bitCast(ul),
            @bitCast(ur),
            @bitCast(ll),
            @bitCast(lr),
        );
        try unwrap(err);
        return @max(0, err);
    }

    pub fn erase(self: Plane) void {
        c.ncplane_erase(self.handle);
    }

    pub const Options = struct {
        y: i32,
        x: i32,
        rows: u32,
        cols: u32,
        userdata: ?*anyopaque,
        name: ?[*:0]const u8,
        resize_cb: ?*const CResizeCallback,
        flags: Flags,
        margin_b: u32,
        margin_r: u32,

        pub const Flags = packed struct(u64) {
            horizontally_aligned: bool = false,
            vertically_aligned: bool = false,
            /// treats 'y' and 'x' as top and left margins;
            /// 'rows' and 'cols' must be zero;
            /// cannot use with alignment flags
            marginalized: bool = false,
            fixed: bool = false,
            autogrow: bool = false,
            vertical_scroll: bool = false,
            _padding: u58 = 0,

            test "matches C" {
                const c_vals: []const u64 = &.{
                    c.NCPLANE_OPTION_FIXED,
                    c.NCPLANE_OPTION_VSCROLL,
                    c.NCPLANE_OPTION_AUTOGROW,
                    c.NCPLANE_OPTION_HORALIGNED,
                    c.NCPLANE_OPTION_VERALIGNED,
                    c.NCPLANE_OPTION_MARGINALIZED,
                };
                const z_vals: []const Flags = &.{
                    .{ .fixed = true },
                    .{ .vertical_scroll = true },
                    .{ .autogrow = true },
                    .{ .horizontally_aligned = true },
                    .{ .vertically_aligned = true },
                    .{ .marginalized = true },
                };
                for (c_vals, z_vals) |c_val, z_val| {
                    try std.testing.expectEqual(c_val, @as(u64, @bitCast(z_val)));
                }
            }
        };
    };
};

pub const Reader = struct {
    handle: *c.ncreader,

    pub fn create(plane: Plane, opts: Options) Error!Reader {
        const c_opts: c.ncreader_options = .{
            .flags = @bitCast(opts.flags),
            .tattrword = opts.attrword,
            .tchannels = opts.channels,
        };
        return .{
            .handle = c.ncreader_create(plane.handle, &c_opts) orelse return error.NotCursesFailed,
        };
    }

    pub fn destroy(self: *Reader, out_contents: ?*?[*:0]u8) void {
        c.ncreader_destroy(self.handle, out_contents);
        self.* = undefined;
    }

    pub fn clear(self: Reader) Error!void {
        try unwrap(c.ncreader_clear(self.handle));
    }

    pub fn offer(self: Reader, input: Input) bool {
        const ni: c.ncinput = .{
            .evtype = @intFromEnum(input.ev_type),
            .id = input.id,
            .modifiers = @bitCast(input.modifiers),
            .utf8 = input.utf8,
            .x = input.x,
            .y = input.y,
            .xpx = input.xpx,
            .ypx = input.ypx,
        };
        return c.ncreader_offer_input(self.handle, &ni);
    }

    /// should be destroyed with std.heap.raw_c_allocator.
    pub fn contents(self: Reader) Error![:0]u8 {
        const ptr: [*:0]u8 = c.ncreader_contents(self.handle) orelse return error.NotCursesFailed;
        return std.mem.sliceTo(ptr, 0);
    }

    pub const Options = struct {
        channels: u64,
        attrword: u32,
        flags: Flags,

        pub const Flags = packed struct(u64) {
            horizontal_scroll: bool = false,
            vertical_scroll: bool = false,
            no_cmd_keys: bool = false,
            cursor: bool = false,
            _padding: u60 = 0,

            test "matches C" {
                const c_vals: []const u64 = &.{
                    c.NCREADER_OPTION_CURSOR,
                    c.NCREADER_OPTION_HORSCROLL,
                    c.NCREADER_OPTION_VERSCROLL,
                    c.NCREADER_OPTION_NOCMDKEYS,
                };
                const z_vals: []const Flags = &.{
                    .{ .cursor = true },
                    .{ .horizontal_scroll = true },
                    .{ .vertical_scroll = true },
                    .{ .no_cmd_keys = true },
                };
                for (c_vals, z_vals) |c_val, z_val| {
                    try std.testing.expectEqual(c_val, @as(u64, @bitCast(z_val)));
                }
            }
        };
    };
};

pub const Cell = packed struct(u128) {
    gcluster: u32 = 0,
    backstop: u8 = 0,
    width: u8 = 0,
    mask: Mask = .{},
    fg: Channel = .{},
    bg: Channel = .{},

    comptime {
        std.debug.assert(@sizeOf(Cell) == @sizeOf(c.nccell));
        std.debug.assert(@bitSizeOf(Cell) == @bitSizeOf(c.nccell));
        std.debug.assert(@alignOf(Cell) >= @alignOf(c.nccell));
    }

    pub fn isDoubleWide(self: Cell) bool {
        return self.width >= 2;
    }

    pub fn isWideRight(self: Cell) bool {
        return self.isDoubleWide() and self.gcluster == 0;
    }

    pub fn isWideLeft(self: Cell) bool {
        return self.isDoubleWide() and self.gcluster != 0;
    }

    pub const Mask = packed struct(u16) {
        struck: bool = false,
        bold: bool = false,
        undercurl: bool = false,
        underline: bool = false,
        italic: bool = false,
        _unused: u11 = 0,

        test "matches C" {
            const c_vals: []const u32 = &.{
                c.NCSTYLE_BOLD,
                c.NCSTYLE_NONE,
                c.NCSTYLE_ITALIC,
                c.NCSTYLE_STRUCK,
                c.NCSTYLE_UNDERCURL,
                c.NCSTYLE_UNDERLINE,
            };
            const z_vals: []const Mask = &.{
                .{ .bold = true },
                .{},
                .{ .italic = true },
                .{ .struck = true },
                .{ .undercurl = true },
                .{ .underline = true },
            };
            for (c_vals, z_vals) |c_val, z_val| {
                try std.testing.expectEqual(@as(u16, @intCast(c_val)), @as(u16, @bitCast(z_val)));
            }
        }
    };
};

pub const Box = struct {
    ul: Cell,
    ur: Cell,
    ll: Cell,
    lr: Cell,
    hline: Cell,
    vline: Cell,

    /// the first four flags _skip_ that part of the box
    const Flags = packed struct(u32) {
        top: bool = false,
        right: bool = false,
        bottom: bool = false,
        left: bool = false,
        grad_top: bool = false,
        grad_right: bool = false,
        grad_bottom: bool = false,
        grad_left: bool = false,
        corner_mask: u2 = 0,
        _unused: u22 = 0,

        test "matches C" {
            const c_vals: []const u32 = &.{
                c.NCBOXMASK_TOP,
                c.NCBOXMASK_LEFT,
                c.NCBOXMASK_RIGHT,
                c.NCBOXMASK_BOTTOM,
                c.NCBOXGRAD_TOP,
                c.NCBOXGRAD_LEFT,
                c.NCBOXGRAD_RIGHT,
                c.NCBOXGRAD_BOTTOM,
                c.NCBOXCORNER_MASK,
            };
            const z_vals: []const Flags = &.{
                .{ .top = true },
                .{ .left = true },
                .{ .right = true },
                .{ .bottom = true },
                .{ .grad_top = true },
                .{ .grad_left = true },
                .{ .grad_right = true },
                .{ .grad_bottom = true },
                .{ .corner_mask = 3 },
            };
            for (c_vals, z_vals) |c_val, z_val| {
                try std.testing.expectEqual(c_val, @as(u32, @bitCast(z_val)));
            }
        }
    };
};

pub fn unwrap(err: c_int) Error!void {
    if (err < 0) return error.NotCursesFailed;
}
