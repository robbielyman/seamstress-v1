pub fn registerSeamstress(l: *Lua, tui: *Tui) void {
    const n = l.getTop();
    defer std.debug.assert(n == l.getTop());
    lu.getSeamstress(l); // seamstress
    _ = l.getField(-1, "tui"); // seamstress.tui
    l.remove(-2); // pop seamstress
    l.newTable(); // local t
    l.pushLightUserdata(tui); // push tui
    l.pushClosure(ziglua.wrap(get), 1); // push closure (consumes tui)
    l.setField(-2, "get"); // t.get = closure
    l.pushLightUserdata(tui); // push tui
    l.pushClosure(ziglua.wrap(set), 1); // push closure (consumes tui)
    l.setField(-2, "set"); // t.set = closure
    l.pushLightUserdata(tui); // push tui
    l.pushClosure(ziglua.wrap(print), 1); // push closure (consumes tui)
    l.setField(-2, "write"); // t.get = closure
    l.pushLightUserdata(tui); // push tui
    l.pushClosure(ziglua.wrap(placeCursor), 1); // push closure (consumes tui)
    l.setField(-2, "placeCursor"); // t.get = closure
    l.pushInteger(0);
    l.setField(-2, "rows");
    l.pushInteger(0);
    l.setField(-2, "cols");
    l.setField(-2, "buffer"); // seamstress.tui.buffer = t
    l.pop(1);
}

fn placeCursor(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const x = lu.checkAndFloorNumber(l, 1);
    const y = lu.checkAndFloorNumber(l, 2);
    const i = switch (lu.transformLuaRangeToUsize(x, tui.vaxis.screen.width)) {
        .in_range => |n| n,
        else => return 0,
    };
    const j: usize = switch (lu.transformLuaRangeToUsize(y, tui.vaxis.screen.height)) {
        .in_range => |n| n,
        else => return 0,
    };
    tui.vaxis.window().showCursor(i, j);
    return 0;
}

fn pushCellTable(l: *Lua, cell: vx.Cell) void {
    l.createTable(0, 7);
    _ = l.pushString(cell.char.grapheme);
    l.setField(-2, "char");
    l.pushInteger(@intCast(cell.char.width));
    l.setField(-2, "width");

    inline for (.{ "fg", "bg", "ul" }) |tag| {
        const ptr = l.newUserdata(vx.Color, 0);
        _ = l.getMetatableRegistry("seamstress.tui.Color");
        ptr.* = @field(cell.style, tag);
        l.setField(-2, tag);
    }
    _ = l.pushStringZ(@tagName(cell.style.ul_style));
    l.setField(-2, "ul_style");

    l.createTable(0, 7);
    inline for (.{ "bold", "dim", "italic", "blink", "reverse", "invisible", "strikethrough" }) |tag| {
        l.pushBoolean(@field(cell.style, tag));
        l.setField(-2, tag);
    }
    l.setField(-2, "modifiers");
}

fn get(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const x = lu.checkAndFloorNumber(l, 1);
    const y = lu.checkAndFloorNumber(l, 2);
    switch (lu.transformLuaRangeToUsize(x, tui.vaxis.screen.width)) {
        .in_range => |i| switch (lu.transformLuaRangeToUsize(y, tui.vaxis.screen.height)) {
            .in_range => |j| {
                const cell = tui.vaxis.screen.readCell(i, j).?;
                pushCellTable(l, cell);
            },
            else => l.pushNil(),
        },
        else => l.pushNil(),
    }
    return 1;
}

fn parseStyleFromTable(l: *Lua, idx: i32, arg: i32) vx.Style {
    var style: vx.Style = .{};

    inline for (.{ "fg", "bg", "ul" }) |key| {
        switch (l.getField(idx, key)) {
            .userdata => {
                const color = l.toUserdata(vx.Color, -1) catch l.typeError(arg, "seamstress.tui.Color");
                @field(style, key) = color.*;
            },
            else => {
                lu.getMethod(l, "tui", "Color");
                l.insert(-2);
                l.call(1, 1);
                const color = l.toUserdata(vx.Color, -1) catch l.typeError(arg, "seamstress.tui.Color");
                @field(style, key) = color.*;
            },
        }
        l.pop(1);
    }

    if (l.getField(idx, "ul_style") == .string) {
        const str = l.toString(-1) catch unreachable;
        const ul_info = @typeInfo(vx.Cell.Style.Underline);
        blk: {
            inline for (ul_info.Enum.fields) |key| {
                if (std.mem.eql(u8, key.name, str)) {
                    style.ul_style = @enumFromInt(key.value);
                    break :blk;
                }
            }
        }
    }
    l.pop(1);

    if (l.getField(idx, "modifiers") == .table) {
        inline for (.{ "bold", "dim", "italic", "blink", "reverse", "invisible", "strikethrough" }) |key| {
            _ = l.getField(-1, key);
            @field(style, key) = l.toBoolean(-1);
            l.pop(1);
        }
    }
    l.pop(1);

    return style;
}

fn parseBorder(l: *Lua, arg: i32) vx.Window.BorderOptions {
    _ = l.getField(arg, "border");
    var border: vx.Window.BorderOptions = .{};
    const t = l.typeOf(-1);
    switch (t) {
        .string => blk: {
            const str = l.toString(-1) catch unreachable;
            inline for (.{ .none, .all, .top, .right, .bottom, .left }) |here| {
                if (std.mem.eql(u8, @tagName(here), str)) {
                    border.where = here;
                    break :blk;
                }
            }
        },
        .table => {
            if (l.getField(-1, "style") == .table) {
                border.style = parseStyleFromTable(l, -1, arg);
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
                        inline for (.{ "top", "right", "bottom", "left" }) |here| {
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

fn print(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    var x_start: usize = undefined;
    var x_end: usize = undefined;
    var x_offset: usize = 0;
    var y_start: usize = undefined;
    var y_end: usize = undefined;
    var y_offset: usize = 0;
    var style: vx.Style = .{};
    switch (l.typeOf(1)) {
        .table => {
            _ = l.getIndex(1, 1);
            const x = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "list of two or three integers");
            x_start = switch (lu.transformLuaRangeToUsize(x, tui.vaxis.screen.width)) {
                .in_range => |n| n,
                .too_negative => 0,
                .too_positive => tui.vaxis.screen.width - 1,
            };
            l.pop(1);
            _ = l.getIndex(1, 2);
            const x2 = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "list of two or three integers");
            x_end = switch (lu.transformLuaRangeToUsize(x2, tui.vaxis.screen.width)) {
                .in_range => |n| n + 1,
                .too_negative => 0,
                .too_positive => tui.vaxis.screen.width,
            };
            l.pop(1);
            if (x_start >= x_end) return 0;
            const t = l.getIndex(1, 3);
            if (t != .nil and t != .none) {
                const x3 = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "list of two or three integers");
                x_offset = switch (lu.transformLuaRangeToUsize(x3, x_end - x_start)) {
                    .in_range => |n| n,
                    .too_negative => 0,
                    .too_positive => x_end - x_start,
                };
            }
            l.pop(1);
        },
        else => l.typeError(1, "list of two or three integers"),
    }
    switch (l.typeOf(2)) {
        .table => {
            _ = l.getIndex(2, 1);
            const y = lu.toAndFloorNumber(l, -1) catch l.typeError(2, "list of two or three integers");
            y_start = switch (lu.transformLuaRangeToUsize(y, tui.vaxis.screen.height)) {
                .in_range => |n| n,
                .too_negative => 0,
                .too_positive => tui.vaxis.screen.height - 1,
            };
            l.pop(1);
            _ = l.getIndex(2, 2);
            const y2 = lu.toAndFloorNumber(l, -1) catch l.typeError(2, "list of two or three integers");
            y_end = switch (lu.transformLuaRangeToUsize(y2, tui.vaxis.screen.height)) {
                .in_range => |n| n + 1,
                .too_negative => 0,
                .too_positive => tui.vaxis.screen.height,
            };
            l.pop(1);
            const t = l.getIndex(2, 3);
            if (t != .nil and t != .none) {
                const y3 = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "list of two or three integers");
                y_offset = switch (lu.transformLuaRangeToUsize(y3, y_end - y_start)) {
                    .in_range => |n| n,
                    .too_negative => 0,
                    .too_positive => y_end - y_start,
                };
                if (x_offset == x_end - x_start) {
                    x_offset = 0;
                    y_offset += 1;
                }
            }
            l.pop(1);
        },
        else => l.typeError(1, "list of two or three integers"),
    }

    const str = l.checkString(3);

    const border, const wrap, const dry_run = params: {
        if (l.typeOf(4) != .nil and l.typeOf(4) != .none) {
            style = parseStyleFromTable(l, 4, 4);
            const border = parseBorder(l, 4);
            const wrap: @TypeOf(@field(vx.Window.PrintOptions{}, "wrap")) = blk: {
                if (l.getField(4, "wrap") == .string) {
                    const wrap = l.toString(-1) catch unreachable;
                    inline for (.{ "none", "word", "char" }, .{ .none, .word, .grapheme }) |key, val| {
                        if (std.mem.eql(u8, wrap, key)) break :blk val;
                    }
                    break :blk .word;
                } else break :blk if (l.toBoolean(-1) or l.typeOf(-1) == .nil or l.typeOf(-1) == .none) .word else .none;
            };
            l.pop(1);

            _ = l.getField(4, "dry_run");
            const dry_run = l.toBoolean(-1);
            l.pop(1);
            break :params .{ border, wrap, dry_run };
        } else break :params .{ vx.Window.BorderOptions{}, .grapheme, false };
    };

    const parent = tui.vaxis.window();
    const child = parent.child(.{
        .x_off = x_start,
        .y_off = y_start,
        .width = .{ .limit = x_end - x_start },
        .height = .{ .limit = y_end - y_start },
        .border = border,
    });

    var row_offset = y_offset;
    var col_offset = x_offset;
    var iterator = std.mem.splitScalar(u8, str, '\n');
    var res: vx.Window.PrintResult = undefined;
    while (iterator.next()) |token| {
        res = child.printSegment(.{ .style = style, .text = token }, .{
            .row_offset = row_offset,
            .col_offset = col_offset,
            .wrap = wrap,
            .commit = !dry_run,
        }) catch |err| l.raiseErrorStr("unable to print! %s", .{@errorName(err)});
        col_offset = 0;
        row_offset = res.row + 1;
    }
    l.pushInteger(@intCast(res.col));
    l.pushInteger(@intCast(res.row));
    return 2;
}

fn set(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    var x_start: usize = undefined;
    var x_end: usize = undefined;
    var y_start: usize = undefined;
    var y_end: usize = undefined;
    var cell: vx.Cell = .{};
    switch (l.typeOf(1)) {
        .table => {
            _ = l.getIndex(1, 1);
            const x = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "integer or list of two integers");
            x_start = switch (lu.transformLuaRangeToUsize(x, tui.vaxis.screen.width)) {
                .in_range => |n| n,
                .too_negative => 0,
                .too_positive => return 0,
            };
            l.pop(1);
            _ = l.getIndex(1, 2);
            const x2 = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "integer or list of two integers");
            x_end = switch (lu.transformLuaRangeToUsize(x2, tui.vaxis.screen.width)) {
                .in_range => |n| n,
                .too_negative => return 0,
                .too_positive => tui.vaxis.screen.width,
            };
            l.pop(1);
        },
        else => {
            const x = lu.checkAndFloorNumber(l, 1);
            x_start = switch (lu.transformLuaRangeToUsize(x, tui.vaxis.screen.width)) {
                .in_range => |n| n,
                else => return 0,
            };
            x_end = x_start + 1;
        },
    }
    switch (l.typeOf(2)) {
        .table => {
            _ = l.getIndex(2, 1);
            const y = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "integer or list of two integers");
            y_start = switch (lu.transformLuaRangeToUsize(y, tui.vaxis.screen.height)) {
                .in_range => |n| n,
                .too_negative => 0,
                .too_positive => return 0,
            };
            l.pop(1);
            _ = l.getIndex(2, 2);
            const y2 = lu.toAndFloorNumber(l, -1) catch l.typeError(1, "integer or list of two integers");
            y_end = switch (lu.transformLuaRangeToUsize(y2, tui.vaxis.screen.height)) {
                .in_range => |n| n,
                .too_negative => return 0,
                .too_positive => tui.vaxis.screen.height,
            };
            l.pop(1);
        },
        else => {
            const y = lu.checkAndFloorNumber(l, 2);
            y_start = switch (lu.transformLuaRangeToUsize(y, tui.vaxis.screen.height)) {
                .in_range => |n| n,
                else => return 0,
            };
            y_end = y_start + 1;
        },
    }

    if (l.typeOf(3) != .nil and l.typeOf(3) != .none) {
        cell.style = parseStyleFromTable(l, 3, 3);

        if (l.getField(3, "char") == .string) {
            const str = l.toString(-1) catch unreachable;
            var iterator = grapheme.Iterator.init(str, &tui.vaxis.unicode.grapheme_data);
            if (iterator.next()) |g| {
                const bytes = g.bytes(str);
                cell.char.grapheme = bytes;
                cell.char.width = vx.gwidth.gwidth(bytes, tui.vaxis.caps.unicode, &tui.vaxis.unicode.width_data) catch unreachable;
                l.pushInteger(@intCast(cell.char.width));
                l.setField(3, "width");
            } else cell.char.grapheme = " ";
        } else cell.char.grapheme = " ";
        l.pop(2);
    }

    if (x_start < x_end + 1 and y_start < y_end + 1)
        for (x_start..x_end + 1) |col| {
            for (y_start..y_end + 1) |row| tui.vaxis.screen.writeCell(col, row, cell);
        };
    return 0;
}

const grapheme = @import("grapheme");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Tui = @import("../tui.zig");
const lu = @import("../../lua_util.zig");
const vx = @import("vaxis");
const std = @import("std");
