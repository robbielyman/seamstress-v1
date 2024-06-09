pub fn registerSeamstress(l: *Lua) void {
    l.newMetatable("seamstress.tui.Style") catch unreachable;
    l.setFuncs(functions, 0);
    l.pop(1);

    lu.getSeamstress(l);
    _ = l.getField(-1, "tui");
    l.remove(-2);
    _ = l.pushStringZ("Style");
    l.pushFunction(ziglua.wrap(new));
    l.setTable(-3);
    l.pop(1);
}

const functions: []const ziglua.FnReg = &.{ .{
    .name = "__index",
    .func = ziglua.wrap(getIndex),
}, .{
    .name = "__eq",
    .func = ziglua.wrap(eql),
}, .{
    .name = "__tostring",
    .func = ziglua.wrap(toString),
}, .{
    .name = "__call",
    .func = ziglua.wrap(call),
} };

fn new(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const style: *vx.Style = l.newUserdata(vx.Style, 0);
    _ = l.getMetatableRegistry("seamstress.tui.Style");
    l.setMetatable(-2);
    style.* = .{};
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const key = l.checkString(1);
            lu.getSeamstress(l);
            _ = l.getField(-1, "tui");
            l.remove(-2);
            _ = l.getField(-1, "styles");
            l.remove(-2);
            const t1 = l.getField(-1, key);
            l.remove(-2);
            if (l.typeOf(-1) == .table) {
                inline for (.{ "fg", "bg", "ul" }) |name| {
                    const t2 = l.getField(-1, name);
                    switch (t2) {
                        .string => {
                            lu.getSeamstress(l);
                            _ = l.getField(-1, "tuiColorNew");
                            l.remove(-2);
                            l.pushValue(-2);
                            l.call(1, 1);
                            const col = l.toUserdata(vx.Color, -1) catch unreachable;
                            @field(style, name) = col.*;
                            l.pop(1);
                        },
                        .userdata => {
                            const col = l.toUserdata(vx.Color, -1) catch unreachable;
                            @field(style, name) = col.*;
                            l.pop(1);
                        },
                        .nil => {},
                        else => l.typeError(1, "string or tui.Color"),
                    }
                    l.pop(1);
                }

                _ = l.getField(-1, "ul_style");
                const ul_st = l.toStringEx(-1);
                for (uls) |ul_style| {
                    if (std.mem.eql(u8, ul_style[1], ul_st)) {
                        style.ul_style = ul_style[0];
                        break;
                    }
                } else style.ul_style = .off;
                l.pop(2);
                inline for (mods) |mod| {
                    _ = l.getField(-1, mod);
                    if (l.toBoolean(-1)) @field(style, mod) = true;
                    l.pop(1);
                }
            }
            l.pop(1);
            // defer l.pop(1);
            if (t1 != .userdata) return 1;
            const other = l.toUserdata(vx.Style, -1) catch return 1;
            style.* = other.*;
        },
        .table => {
            inline for (.{ "fg", "bg", "ul" }) |name| {
                const t1 = l.getField(1, name);
                switch (t1) {
                    .string => {
                        lu.getSeamstress(l);
                        _ = l.getField(-1, "tuiColorNew");
                        l.remove(-2);
                        l.rotate(-2, 1);
                        l.call(1, 1);
                        const col = l.toUserdata(vx.Color, -1) catch unreachable;
                        @field(style, name) = col.*;
                        l.pop(1);
                    },
                    .userdata => {
                        const col = l.toUserdata(vx.Color, -1) catch unreachable;
                        @field(style, name) = col.*;
                        l.pop(1);
                    },
                    .nil => {
                        l.pop(1);
                    },
                    else => l.typeError(1, "string or tui.Color"),
                }
            }

            _ = l.getField(1, "ul_style");
            const ul_st = l.toStringEx(-1);
            for (uls) |ul_style| {
                if (std.mem.eql(u8, ul_style[1], ul_st)) {
                    style.ul_style = ul_style[0];
                    break;
                }
            } else style.ul_style = .off;
            l.pop(2);
            inline for (mods) |mod| {
                _ = l.getField(1, mod);
                if (l.toBoolean(-1)) @field(style, mod) = true;
                l.pop(1);
            }
        },
        else => {},
    }
    return 1;
}

fn getIndex(l: *Lua) i32 {
    const style = l.checkUserdata(vx.Style, 1, "seamstress.tui.Style");
    const field = l.toStringEx(2);
    inline for (.{ "fg", "bg", "ul" }) |col| {
        if (std.mem.eql(u8, field, col)) {
            const color = l.newUserdata(vx.Color, 0);
            _ = l.getMetatableRegistry("tui.Color");
            l.setMetatable(-2);
            color.* = @field(style, col);
            return 1;
        }
    }
    if (std.mem.eql(u8, field, "ul_style")) {
        _ = l.pushStringZ(@tagName(style.ul_style));
        return 1;
    }
    inline for (mods) |mod| {
        if (std.mem.eql(u8, field, mod)) {
            const val = @field(style, mod);
            l.pushBoolean(val);
            return 1;
        }
    }
    return 0;
}

fn eql(l: *Lua) i32 {
    const a = l.checkUserdata(vx.Style, 1, "seamstress.tui.Style");
    const b = l.checkUserdata(vx.Style, 1, "seamstress.tui.Style");
    l.pushBoolean(a.eql(b.*));
    return 1;
}

fn toString(l: *Lua) i32 {
    const style = l.checkUserdata(vx.Style, 1, "seamstress.tui.Style");
    var buf: ziglua.Buffer = .{};
    const slice = buf.initSize(l, 1024);
    var stream = std.io.fixedBufferStream(slice);
    var writer = stream.writer();
    writer.writeAll("style(fg:") catch unreachable;
    switch (style.fg) {
        .default => writer.writeAll("color(default) ") catch unreachable,
        .rgb => |rgb| {
            writer.print("color(r:0x{x:0>2} g:0x{x:0>2} b:0x{x:0>2}) ", .{ rgb[0], rgb[1], rgb[2] }) catch unreachable;
        },
        else => unreachable,
    }
    writer.writeAll("bg:") catch unreachable;
    switch (style.bg) {
        .default => writer.writeAll("color(default) ") catch unreachable,
        .rgb => |rgb| {
            writer.print("color(r:0x{x:0>2} g:0x{x:0>2} b:0x{x:0>2}) ", .{ rgb[0], rgb[1], rgb[2] }) catch unreachable;
        },
        else => unreachable,
    }
    writer.writeAll("ul:") catch unreachable;
    switch (style.ul) {
        .default => writer.writeAll("color(default) ") catch unreachable,
        .rgb => |rgb| {
            writer.print("color(r:0x{x:0>2} g:0x{x:0>2} b:0x{x:0>2}) ", .{ rgb[0], rgb[1], rgb[2] }) catch unreachable;
        },
        else => unreachable,
    }
    writer.print("ul_style:{s}", .{@tagName(style.ul_style)}) catch unreachable;
    inline for (mods) |mod| {
        if (@field(style, mod)) {
            writer.print(" {s}", .{mod}) catch unreachable;
        }
    }
    writer.writeAll(")") catch unreachable;
    buf.pushResultSize(stream.pos);
    return 1;
}

const mods: [7][:0]const u8 = .{
    "bold", "dim", "italic", "blink", "reverse", "invisible", "strikethrough",
};

const uls: []const struct { vx.Style.Underline, []const u8 } = &.{
    .{ .single, "single" },
    .{ .double, "double" },
    .{ .curly, "curly" },
    .{ .dotted, "dotted" },
    .{ .dashed, "dashed" },
};

fn call(l: *Lua) i32 {
    const style = l.checkUserdata(vx.Style, 1, "seamstress.tui.Style");
    const t2 = l.typeOf(2);
    const start = l.optInteger(3) orelse 1;
    const end = l.optInteger(4) orelse -1;
    switch (t2) {
        .number, .string => {
            _ = l.toString(2) catch unreachable;
            lu.getSeamstress(l);
            _ = l.getField(-1, "tuiLineNew");
            l.remove(-2);
            l.pushValue(2);
            l.call(1, 1);
        },
        .userdata => {
            const line = l.checkUserdata(Line, 2, "tui.Line");
            const new_line = l.newUserdata(Line, 2);
            new_line.* = line.*;
            _ = l.getUserValue(2, 1) catch unreachable;
            l.setUserValue(-2, 1) catch unreachable;
            _ = l.getUserValue(2, 2) catch unreachable;
            l.setUserValue(-2, 2) catch unreachable;
        },
        else => l.typeError(2, "line or string"),
    }

    l.pushValue(-1); // copy the line
    l.pushValue(-1); // twice
    _ = l.getMetaField(-1, "sub") catch unreachable;
    l.rotate(-2, 1);
    l.pushInteger(1);
    l.pushInteger(start - 1);
    l.call(3, 1); // replace the first copy with line:sub(1, start - 1)
    l.rotate(-2, 1); // put it at the bottom
    _ = l.getMetaField(-1, "sub") catch unreachable;
    l.rotate(-2, 1);
    l.pushInteger(start);
    l.pushInteger(end);
    l.call(3, 1);
    const middle = l.toUserdata(Line, -1) catch unreachable;
    _ = l.getUserValue(-2, 1) catch unreachable;
    const text = l.toString(-1) catch unreachable;
    if (l.getUserValue(-2, 2) catch unreachable == .userdata and text.len > 0) {
        const segments = l.newUserdataSlice(Line.Segment, 1, 0);
        segments[0] = .{
            .byte_len = text.len,
            .grapheme_len = middle.grapheme_len,
            .width = middle.width,
            .style = style.*,
        };
        l.setUserValue(-3, 2) catch unreachable;
    }
    l.pop(2);
    _ = l.getMetaField(-2, "__concat") catch unreachable;
    l.insert(-3);
    l.call(2, 1);
    // do the last substitution
    l.rotate(-2, 1);
    _ = l.getMetaField(-1, "sub") catch unreachable;
    l.rotate(-2, 1);
    l.pushInteger(end + 1);
    l.pushInteger(-1);
    l.call(3, 1);
    _ = l.getMetaField(-2, "__concat") catch unreachable;
    l.insert(-3);
    l.call(2, 1);
    return 1;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const vx = @import("vaxis");
const lu = @import("../../lua_util.zig");
const Line = @import("line.zig").Line;
