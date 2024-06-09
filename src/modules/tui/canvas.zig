pub fn registerSeamstress(l: *Lua, tui: *Tui) void {
    lu.registerSeamstress(l, "tui", "drawInBox", display, tui);
    lu.registerSeamstress(l, "tui", "clearBox", clear, tui);
    lu.registerSeamstress(l, "tui", "showCursorInBox", showCursor, tui);
    // lu.getSeamstress(l);
    // l.pushFunction(ziglua.wrap(printFn));
    // l.setField(-2, "_print");
    // l.pop(1);
}

fn showCursor(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const window = tui.vaxis.window();
    var spec: WindowSpec = .{};
    var border: vx.Window.BorderOptions = .{};
    const x = l.checkInteger(1) - 1;
    const y = l.checkInteger(2) - 1;
    if (l.typeOf(3) == .table) {
        if (l.getField(3, "x") == .table) {
            _ = l.getIndex(-1, 1);
            spec.x[0] = l.toNumber(-1) catch 1;
            l.pop(1);
            _ = l.getIndex(-1, 2);
            spec.x[1] = l.toNumber(-1) catch -1;
            l.pop(1);
        }
        l.pop(1);

        if (l.getField(3, "y") == .table) {
            _ = l.getIndex(-1, 1);
            spec.y[0] = l.toNumber(-1) catch 1;
            l.pop(1);
            _ = l.getIndex(-1, 2);
            spec.y[1] = l.toNumber(-1) catch -1;
            l.pop(1);
        }
        l.pop(1);
        _ = l.getField(3, "border");
        border = parseBorder(l);
    }
    const child = childFromSpec(window, spec, border);
    child.showCursor(@intCast(x), @intCast(y));
    return 0;
}

const WindowSpec = struct {
    x: [2]ziglua.Number = .{ 1, -1 },
    y: [2]ziglua.Number = .{ 1, -1 },
};

fn childFromSpec(parent: vx.Window, spec: WindowSpec, border: vx.Window.BorderOptions) vx.Window {
    const default: vx.Window.ChildOptions = .{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = 0 },
        .height = .{ .limit = 0 },
        .border = .{},
    };

    const wid: ziglua.Integer = @intCast(parent.width);
    const spec_x_0: ziglua.Integer = @intFromFloat(spec.x[0]);
    const x_off: usize = switch (spec_x_0) {
        0 => 0,
        1...std.math.maxInt(ziglua.Integer) => @intCast(spec_x_0 - 1),
        else => @intCast(@max(0, spec_x_0 + wid)),
    };
    if (x_off >= parent.width) return parent.child(default);

    const hei: ziglua.Integer = @intCast(parent.height);
    const spec_y_0: ziglua.Integer = @intFromFloat(spec.y[0]);
    const y_off: usize = switch (spec_y_0) {
        0 => 0,
        1...std.math.maxInt(ziglua.Integer) => @intCast(spec_y_0 - 1),
        else => @intCast(@max(0, spec_y_0 + hei)),
    };
    if (y_off >= parent.height) return parent.child(default);

    const spec_x_1: ziglua.Integer = @intFromFloat(spec.x[1]);
    const width: usize = switch (spec_x_1) {
        1...std.math.maxInt(ziglua.Integer) => @as(usize, @intCast(spec_x_1)) -| x_off,
        0 => 0,
        else => @as(usize, @intCast(@max(0, spec_x_1 + wid + 1))) -| x_off,
    };
    if (width == 0) return parent.child(default);

    const spec_y_1: ziglua.Integer = @intFromFloat(spec.y[1]);
    const height: usize = switch (spec_y_1) {
        1...std.math.maxInt(ziglua.Integer) => @as(usize, @intCast(spec_y_1)) -| y_off,
        0 => 0,
        else => @as(usize, @intCast(@max(0, spec_y_1 + hei + 1))) -| y_off,
    };
    if (height == 0) return parent.child(default);
    return parent.child(.{
        .border = border,
        .x_off = x_off,
        .y_off = y_off,
        .width = .{ .limit = width },
        .height = .{ .limit = height },
    });
}

fn parseBorder(l: *Lua) vx.Window.BorderOptions {
    var border: vx.Window.BorderOptions = .{};
    const t = l.typeOf(-1);
    switch (t) {
        .string => {
            const str = l.toString(-1) catch unreachable;
            inline for (wheres) |here| {
                if (std.mem.eql(u8, here[0], str)) {
                    border = here[1];
                }
            }
        },
        .table => {
            if (l.getField(-1, "style") == .userdata) {
                const style = l.toUserdata(vx.Style, -1) catch unreachable;
                border.style = style.*;
            }
            l.pop(1);

            if (l.getIndex(-1, 1) == .string) {
                var str = l.toString(-1) catch unreachable;
                if (std.mem.eql(u8, "all", str)) {
                    border.where = .all;
                } else {
                    var locations: vx.Window.BorderOptions.Locations = .{};
                    var idx: i32 = 2;
                    while (idx <= 4) {
                        inline for (where) |here| {
                            if (std.mem.eql(u8, here, str)) {
                                @field(locations, here) = true;
                            }
                        }
                        l.pop(1);
                        if (l.getIndex(-1, idx) != .string) {
                            break;
                        }
                        str = l.toString(-1) catch unreachable;
                        idx += 1;
                    }
                    border.where = .{ .other = locations };
                }
            }
            l.pop(1);
        },
        else => {},
    }
    l.pop(1);
    return border;
}

fn clear(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const parent = tui.vaxis.window();

    var spec: WindowSpec = .{};
    var border: vx.Window.BorderOptions = .{};
    if (l.typeOf(1) == .table) {
        if (l.getField(1, "x") == .table) {
            _ = l.getIndex(-1, 1);
            spec.x[0] = l.toNumber(-1) catch 1;
            l.pop(1);
            _ = l.getIndex(-1, 2);
            spec.x[1] = l.toNumber(-1) catch -1;
            l.pop(1);
        }
        l.pop(1);

        if (l.getField(1, "y") == .table) {
            _ = l.getIndex(-1, 1);
            spec.y[0] = l.toNumber(-1) catch 1;
            l.pop(1);
            _ = l.getIndex(-1, 2);
            spec.y[1] = l.toNumber(-1) catch -1;
            l.pop(1);
        }
        l.pop(1);
        _ = l.getField(1, "border");
        border = parseBorder(l);
    }
    const child = childFromSpec(parent, spec, border);
    child.clear();
    return 0;
}

fn display(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const parent = tui.vaxis.window();

    var spec: WindowSpec = .{};
    var border: vx.Window.BorderOptions = .{};

    if (l.typeOf(2) == .table) {
        if (l.getField(2, "x") == .table) {
            _ = l.getIndex(-1, 1);
            spec.x[0] = l.toNumber(-1) catch 1;
            l.pop(1);
            _ = l.getIndex(-1, 2);
            spec.x[1] = l.toNumber(-1) catch -1;
            l.pop(1);
        }
        l.pop(1);

        if (l.getField(2, "y") == .table) {
            _ = l.getIndex(-1, 1);
            spec.y[0] = l.toNumber(-1) catch 1;
            l.pop(1);
            _ = l.getIndex(-1, 2);
            spec.y[1] = l.toNumber(-1) catch -1;
            l.pop(1);
        }
        l.pop(1);

        _ = l.getField(2, "border");
        border = parseBorder(l);
    }
    l.pop(1);

    const child = childFromSpec(parent, spec, border);

    const t1 = l.typeOf(1);
    switch (t1) {
        .userdata => {
            _ = l.checkUserdata(Line, 1, "tui.Line");
            _ = l.getUserValue(-1, 1) catch unreachable;
            const text = l.toString(-1) catch unreachable;
            if (l.getUserValue(-2, 2) catch unreachable == .userdata and text.len > 0) {
                const segs = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
                const segments = l.newUserdataSlice(vx.Segment, segs.len, 0);
                Line.toSegments(text, segs, segments);
                _ = child.print(segments, .{ .wrap = .none }) catch unreachable;
                l.pop(1);
            }
            l.pop(2);
        },
        .table => {
            l.len(1);
            const n = l.toInteger(-1) catch unreachable;
            var i: ziglua.Integer = 1;
            l.pop(1);
            while (i <= n) : (i += 1) {
                const t3 = l.getIndex(1, i);
                switch (t3) {
                    .userdata => {
                        _ = l.toUserdata(Line, -1) catch l.argError(1, "line or array of lines expected!");
                        _ = l.getUserValue(-1, 1) catch unreachable;
                        const text = l.toString(-1) catch unreachable;
                        if (l.getUserValue(-2, 2) catch unreachable == .userdata and text.len > 0) {
                            const segs = l.toUserdataSlice(Line.Segment, -1) catch unreachable;

                            const segments = l.newUserdataSlice(vx.Segment, segs.len, 0);
                            Line.toSegments(text, segs, segments);
                            _ = child.print(segments, .{
                                .row_offset = @intCast(i - 1),
                                .wrap = .none,
                            }) catch unreachable;
                            l.pop(1);
                        }
                        l.pop(3);
                    },
                    .string => {
                        lu.getSeamstress(l);
                        _ = l.getField(-1, "tuiLineNew");
                        l.remove(-2);
                        l.insert(-2);
                        l.call(1, 1);
                        _ = l.toUserdata(Line, -1) catch l.argError(1, "line or array of lines expected!");
                        _ = l.getUserValue(-1, 1) catch unreachable;
                        const text = l.toString(-1) catch unreachable;
                        if (l.getUserValue(-2, 2) catch unreachable == .userdata and text.len > 0) {
                            const segs = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
                            const segments = l.newUserdataSlice(vx.Segment, segs.len, 0);
                            Line.toSegments(text, segs, segments);
                            _ = child.print(segments, .{
                                .row_offset = @intCast(i - 1),
                                .wrap = .none,
                            }) catch unreachable;
                            l.pop(1);
                        }
                        l.pop(3);
                    },
                    .nil => {
                        l.pop(1);
                    },
                    else => l.typeError(1, "line or array of lines"),
                }
            }
        },
        else => l.typeError(1, "line or array of lines"),
    }
    return 0;
}

const wheres: [6]struct { []const u8, vx.Window.BorderOptions } = .{
    .{ "none", .{} },
    .{ "all", .{ .where = .all } },
    .{ "top", .{ .where = .top } },
    .{ "right", .{ .where = .right } },
    .{ "bottom", .{ .where = .bottom } },
    .{ "left", .{ .where = .left } },
};

const where: [4][]const u8 = .{ "top", "right", "bottom", "left" };

fn printFn(l: *Lua) i32 {
    // how many things are we printing?
    const n = l.getTop();
    // printing nothing should do nothing
    if (n == 0) return 0;
    var i: i32 = 1;
    // prepare a buffer
    var buf: ziglua.Buffer = undefined;
    buf.init(l);
    while (1 <= n) : (i += 1) {
        if (i > 1) buf.addChar('\t');
        const t = l.typeOf(i);
        switch (t) {
            .number => {
                if (l.isInteger(i)) {
                    const int = l.checkInteger(i);
                    var counter = std.io.countingWriter(std.io.null_writer);
                    var writer = counter.writer();
                    writer.print("{d}", .{int}) catch unreachable;
                    const slice = buf.prepSize(@intCast(writer.context.bytes_written));
                    _ = std.fmt.bufPrint(slice, "{d}", .{int}) catch unreachable;
                    buf.addSize(slice.len);
                } else {
                    const double = l.checkNumber(i);
                    var counter = std.io.countingWriter(std.io.null_writer);
                    var writer = counter.writer();
                    writer.print("{d}", .{double}) catch unreachable;
                    const slice = buf.prepSize(@intCast(writer.context.bytes_written));
                    _ = std.fmt.bufPrint(slice, "{d}", .{double}) catch unreachable;
                    buf.addSize(slice.len);
                }
            },
            .table => {
                const str = l.toString(i) catch {
                    var counter = std.io.countingWriter(std.io.null_writer);
                    var writer = counter.writer();
                    const ptr = l.toPointer(i) catch unreachable;
                    writer.print("table: 0x{x}", .{@intFromPtr(ptr)}) catch unreachable;
                    const slice = buf.prepSize(@intCast(writer.context.bytes_written));
                    _ = std.fmt.bufPrint(slice, "table: 0x{x}", .{@intFromPtr(ptr)}) catch unreachable;
                    buf.addSize(slice.len);
                    continue;
                };
                buf.addString(str);
            },
            .function => {
                var counter = std.io.countingWriter(std.io.null_writer);
                var writer = counter.writer();
                const ptr = l.toPointer(i) catch unreachable;
                writer.print("function: 0x{x}", .{@intFromPtr(ptr)}) catch unreachable;
                const slice = buf.prepSize(@intCast(writer.context.bytes_written));
                _ = std.fmt.bufPrint(slice, "function: 0x{x}", .{@intFromPtr(ptr)}) catch unreachable;
                buf.addSize(slice.len);
            },
            else => {
                const str = l.toStringEx(i);
                buf.addString(str);
            },
        }
    }
    buf.pushResult();
    const str = l.toString(-1);
    _ = str; // autofix
    lu.getSeamstress(l);
    _ = l.getField(-1, "tui");
    l.remove(-2);
    _ = l.getField(-1, "stdout");
    l.remove(-2);
    // what is the first free index in the table?
    var last = l.rawLen(-1) + 1;
    var tokenizer = std.mem.splitScalar(u8, buf.addr(), '\n');
    while (tokenizer.next()) |token| {
        lu.getSeamstress(l);
        _ = l.getField(-1, "tuiLineNew");
        l.remove(-2);
        _ = l.pushString(token);
        l.call(1, 1);
        l.setIndex(-2, @intCast(last));
        last += 1;
    }
    return 0;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("../../lua_util.zig");
const Tui = @import("../tui.zig");
const Line = @import("line.zig").Line;
const vx = @import("vaxis");
const std = @import("std");
const panic = std.debug.panic;
