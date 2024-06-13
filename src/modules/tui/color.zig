/// @module _seamstress.tui.Color
pub fn registerSeamstress(l: *Lua) void {
    const n = l.getTop();
    blk: {
        l.newMetatable("seamstress.tui.Color") catch break :blk;
        for (functions) |val| {
            _ = l.pushStringZ(val.name);
            l.pushFunction(val.func.?);
            l.setTable(-3);
        }
    }
    l.pop(1);
    lu.getSeamstress(l);
    _ = l.getField(-1, "tui");
    l.remove(-2);
    _ = l.pushStringZ("Color");
    l.pushFunction(ziglua.wrap(new));
    l.setTable(-3); // _seamstress.tuiColorNew = new
    l.pop(1);
    std.debug.assert(n == l.getTop());
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
}, .{
    .name = "__add",
    .func = ziglua.wrap(add),
}, .{
    .name = "__sub",
    .func = ziglua.wrap(subtract),
}, .{
    .name = "__mul",
    .func = ziglua.wrap(multiply),
}, .{
    .name = "__div",
    .func = ziglua.wrap(div),
}, .{
    .name = "__unm",
    .func = ziglua.wrap(negate),
} };

/// tests whether two Color objects are equal:
// the default color is equal only to itself,
// while other colors are compared by RGB values
// @tparam Color a
// @tparam Color b
// @treturn bool
// @function Color.__eq
fn eql(l: *Lua) i32 {
    const a = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
    const b = l.checkUserdata(vx.Color, 2, "seamstress.tui.Color");
    l.pushBoolean(a.eql(b.*));
    return 1;
}

fn toString(l: *Lua) i32 {
    const color = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
    switch (color.*) {
        .default => _ = l.pushStringZ("color(default)"),
        .rgb => |rgb| {
            var buf: ziglua.Buffer = .{};
            const slice = buf.initSize(l, 32);
            const res = std.fmt.bufPrint(slice, "color(r:0x{x:0>2} g:0x{x:0>2} b:0x{x:0>2})", .{ rgb[0], rgb[1], rgb[2] }) catch unreachable;
            buf.pushResultSize(res.len);
        },
        else => unreachable,
    }
    return 1;
}

fn new(l: *Lua) i32 {
    const top = l.getTop();
    if (top != 0 and top != 1 and top != 3) l.raiseErrorStr("bad number of args to constructor!", .{});
    const color = l.newUserdata(vx.Color, 0);
    _ = l.getMetatableRegistry("seamstress.tui.Color");
    l.setMetatable(-2);
    switch (top) {
        0 => color.* = .default,
        1 => {
            const t = l.typeOf(1);
            switch (t) {
                .string => {
                    const key = l.checkString(1);
                    if (key[0] == '#' and key.len == 7) {
                        const lower = std.ascii.allocLowerString(l.allocator(), key[1..]) catch std.debug.panic("out of memory!", .{});
                        defer l.allocator().free(lower);
                        const col = std.fmt.parseInt(u24, lower, 16) catch {
                            color.* = .default;
                            return 1;
                        };
                        const rgb: [3]u8 = @bitCast(col);
                        color.* = .{ .rgb = .{ rgb[2], rgb[1], rgb[0] } };
                        return 1;
                    }
                    lu.getSeamstress(l);
                    _ = l.getField(-1, "tui");
                    l.remove(-2);
                    _ = l.getField(-1, "palette");
                    l.remove(-2);
                    const t1 = l.getField(-1, key);
                    l.remove(-2);
                    if (l.typeOf(-1) == .string) {
                        const k = l.toString(-1) catch unreachable;
                        if (k[0] == '#' and k.len == 7) {
                            const lower = std.ascii.allocLowerString(l.allocator(), k[1..]) catch std.debug.panic("out of memory!", .{});
                            defer l.allocator().free(lower);
                            const col = std.fmt.parseInt(u24, lower, 16) catch {
                                color.* = .default;
                                return 1;
                            };
                            const rgb: [3]u8 = @bitCast(col);
                            color.* = .{ .rgb = .{ rgb[2], rgb[1], rgb[0] } };
                            l.pop(1);
                            return 1;
                        }
                    }
                    if (t1 != .userdata) {
                        l.pop(1);
                        color.* = .default;
                        return 1;
                    }
                    const other = l.toUserdata(vx.Color, -1) catch {
                        l.pop(1);
                        color.* = .default;
                        return 1;
                    };
                    color.* = other.*;
                },
                .table => {
                    _ = l.getIndex(1, 1);
                    const r = l.toNumber(-1) catch l.argError(1, "expected a list of numbers!");
                    l.argCheck(0 <= r and r <= 255, 1, "number between 0 and 255 expected!");
                    _ = l.getIndex(1, 2);
                    const g = l.toNumber(-1) catch l.argError(1, "expected a list of numbers!");
                    l.argCheck(0 <= g and g <= 255, 1, "number between 0 and 255 expected!");
                    _ = l.getIndex(1, 3);
                    const b = l.toNumber(-1) catch l.argError(1, "expected a list of numbers!");
                    l.argCheck(0 <= b and b <= 255, 1, "number between 0 and 255 expected!");
                    color.* = .{ .rgb = .{ @intFromFloat(r), @intFromFloat(g), @intFromFloat(b) } };
                    l.pop(3);
                },
                else => color.* = .default,
            }
        },
        3 => {
            const r = l.checkNumber(1);
            l.argCheck(0 <= r and r <= 255, 1, "number between 0 and 255 expected!");
            const g = l.checkNumber(2);
            l.argCheck(0 <= g and g <= 255, 2, "number between 0 and 255 expected!");
            const b = l.checkNumber(3);
            l.argCheck(0 <= b and b <= 255, 3, "number between 0 and 255 expected!");
            color.* = .{ .rgb = .{ @intFromFloat(r), @intFromFloat(g), @intFromFloat(b) } };
        },
        else => unreachable,
    }
    return 1;
}

fn getIndex(l: *Lua) i32 {
    const color = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
    switch (color.*) {
        .default => return 0,
        .rgb => {
            const t = l.typeOf(2);
            switch (t) {
                .string => {
                    const key = l.checkString(2);
                    if (std.mem.eql(u8, key, "r") or std.mem.eql(u8, key, "red")) {
                        l.pushInteger(color.rgb[0]);
                        return 1;
                    } else if (std.mem.eql(u8, key, "g") or std.mem.eql(u8, key, "green")) {
                        l.pushInteger(color.rgb[1]);
                        return 1;
                    } else if (std.mem.eql(u8, key, "b") or std.mem.eql(u8, key, "blue")) {
                        l.pushInteger(color.rgb[2]);
                        return 1;
                    } else l.argError(2, "expected red, green or blue");
                },
                .number => {
                    const idx = l.checkInteger(2);
                    l.argCheck(1 <= idx and idx <= 3, 2, "index between 1 and 3 expected");
                    l.pushInteger(color.rgb[@intCast(idx - 1)]);
                    return 1;
                },
                else => l.argError(2, "string or number expected!"),
            }
        },
        else => unreachable,
    }
}

fn add(l: *Lua) i32 {
    const t1 = l.typeOf(1);
    const t2 = l.typeOf(2);
    const ret = l.newUserdata(vx.Color, 0);
    _ = l.getMetatableRegistry("seamstress.tui.Color");
    l.setMetatable(-2);
    ret.* = .default;
    switch (t1) {
        .number => {
            const num = l.checkInteger(1);
            const color = l.checkUserdata(vx.Color, 2, "seamstress.tui.Color");
            switch (color.*) {
                .default => {},
                .rgb => |rgb| {
                    var nrgb: [3]u8 = undefined;
                    for (&rgb, &nrgb) |old, *n| {
                        var tmp = num;
                        tmp +|= @intCast(old);
                        n.* = @min(255, @max(0, tmp));
                    }
                    ret.* = .{ .rgb = nrgb };
                },
                else => unreachable,
            }
        },
        .userdata => {
            const color = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
            switch (t2) {
                .number => {
                    const num = l.checkInteger(2);
                    switch (color.*) {
                        .default => {},
                        .rgb => |rgb| {
                            var nrgb: [3]u8 = undefined;
                            for (&rgb, &nrgb) |old, *n| {
                                var tmp = num;
                                tmp +|= @intCast(old);
                                n.* = @min(255, @max(0, tmp));
                            }
                            ret.* = .{ .rgb = nrgb };
                        },
                        else => unreachable,
                    }
                },
                .userdata => {
                    const other = l.checkUserdata(vx.Color, 2, "seamstress.tui.Color");
                    switch (color.*) {
                        .default => {},
                        .rgb => |rgb| {
                            switch (other.*) {
                                .default => {},
                                .rgb => |orgb| {
                                    var nrgb: [3]u8 = undefined;
                                    for (&rgb, &orgb, &nrgb) |a, b, *c| {
                                        var tmp: u16 = a;
                                        tmp += b;
                                        c.* = @intCast(@divFloor(tmp, 2));
                                    }
                                    ret.* = .{ .rgb = nrgb };
                                },
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
                else => l.argError(2, "incompatible types!"),
            }
        },
        else => l.argError(1, "incompatible types!"),
    }
    return 1;
}

fn negate(l: *Lua) i32 {
    const color = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
    const ret = l.newUserdata(vx.Color, 0);
    _ = l.getMetatableRegistry("seamstress.tui.Color");
    l.setMetatable(-2);
    ret.* = .default;
    switch (color.*) {
        .default => {},
        .rgb => |rgb| {
            ret.* = .{ .rgb = .{ 255 - rgb[0], 255 - rgb[1], 255 - rgb[2] } };
        },
        else => unreachable,
    }
    return 1;
}

fn subtract(l: *Lua) i32 {
    l.pushValue(2);
    l.arith(.negate);
    l.pushValue(1);
    l.arith(.add);
    return 1;
}

fn multiply(l: *Lua) i32 {
    const t1 = l.typeOf(1);
    const t2 = l.typeOf(2);
    const ret = l.newUserdata(vx.Color, 0);
    _ = l.getMetatableRegistry("seamstress.tui.Color");
    l.setMetatable(-2);
    ret.* = .default;
    switch (t1) {
        .number => {
            const num = l.checkNumber(1);
            const color = l.checkUserdata(vx.Color, 2, "seamstress.tui.Color");
            switch (color.*) {
                .default => {},
                .rgb => |rgb| {
                    var nrgb: [3]u8 = undefined;
                    for (&rgb, &nrgb) |o, *n| {
                        var tmp: f64 = num;
                        tmp *= @floatFromInt(o);
                        n.* = @intFromFloat(@min(255, @max(0, tmp)));
                    }
                    ret.* = .{ .rgb = nrgb };
                },
                else => unreachable,
            }
        },
        .userdata => {
            const color = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
            switch (t2) {
                .number => {
                    const num = l.checkNumber(2);
                    switch (color.*) {
                        .default => {},
                        .rgb => |rgb| {
                            var nrgb: [3]u8 = undefined;
                            for (&rgb, &nrgb) |o, *n| {
                                var tmp: f64 = num;
                                tmp *= @floatFromInt(o);
                                n.* = @intFromFloat(@min(255, @max(0, tmp)));
                            }
                            ret.* = .{ .rgb = nrgb };
                        },
                        else => unreachable,
                    }
                },
                .userdata => {
                    const other = l.checkUserdata(vx.Color, 2, "seamstress.tui.Color");
                    switch (color.*) {
                        .default => {},
                        .rgb => |rgb| {
                            switch (other.*) {
                                .default => {},
                                .rgb => |orgb| {
                                    var nrgb: [3]u8 = undefined;
                                    for (&rgb, &orgb, &nrgb) |a, b, *n| {
                                        var tmp: f64 = @floatFromInt(a);
                                        tmp *= @floatFromInt(b);
                                        tmp /= 255;
                                        n.* = @intFromFloat(@min(255, tmp));
                                    }
                                    ret.* = .{ .rgb = nrgb };
                                },
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
                else => l.argError(2, "incompatible types!"),
            }
        },
        else => l.argError(1, "incompatible types!"),
    }
    return 1;
}

fn div(l: *Lua) i32 {
    const t2 = l.typeOf(2);
    switch (t2) {
        .number => {
            l.pushNumber(1);
            l.pushValue(2);
            l.arith(.div);
            l.pushValue(1);
            l.arith(.mul);
        },
        .userdata => {
            l.pushValue(2);
            l.arith(.negate);
            l.pushValue(1);
            l.arith(.mul);
        },
        else => l.argError(2, "incompatible types!"),
    }
    return 1;
}

fn call(l: *Lua) i32 {
    const color = l.checkUserdata(vx.Color, 1, "seamstress.tui.Color");
    const t2 = l.typeOf(2);
    // const start = l.optInteger(4) orelse 1;
    // const end = l.optInteger(5) orelse -1;
    const which = l.checkString(3);
    for (&colors) |mod| {
        if (std.mem.eql(u8, mod, which)) break;
    } else l.argError(3, "expected 'fg', 'bg' or 'ul'");
    switch (t2) {
        .number, .string => {
            _ = l.toString(2) catch unreachable;
            const old = l.getTop();
            lu.getMethod(l, "tui", "Line");
            l.pushValue(2);
            l.call(1, ziglua.mult_return);
            const n = l.getTop() - old;
            var i: ziglua.Integer = 1;
            while (i <= n) : (i += 1) {
                _ = l.getMetaField(1, "__call") catch unreachable;
                l.pushValue(1);
                l.pushValue(@intCast(-n - 2));
                l.pushValue(3);
                l.call(3, 1);
                l.remove(@intCast(-n - 1));
            }
            return n;
        },
        .userdata => {
            const line = l.checkUserdata(Line, 2, "seamstress.tui.Line");
            const new_line = l.newUserdata(Line, 2);
            _ = l.getMetatableRegistry("seamstress.tui.Line");
            l.setMetatable(-2);
            new_line.* = line.*;
            _ = l.getUserValue(2, 1) catch unreachable;
            l.setUserValue(-2, 1) catch unreachable;
            _ = l.getUserValue(2, 2) catch unreachable;
            l.setUserValue(-2, 2) catch unreachable;
        },
        .table => {
            l.len(2);
            const n = l.toInteger(-1) catch unreachable;
            l.pop(1);
            var i: ziglua.Integer = 1;
            l.createTable(@intCast(n), 0);
            while (i <= n) : (i += 1) {
                _ = l.getMetaField(1, "__call") catch unreachable;
                l.pushValue(1);
                _ = l.getIndex(2, i);
                l.pushValue(3);
                l.call(3, 1);
                l.setIndex(-2, i);
            }
            return 1;
        },
        else => l.typeError(2, "line or string or array thereof"),
    }
    // l.pushValue(-1); // copy the line three times
    // l.pushValue(-1);
    // _ = l.getMetaField(-1, "sub") catch unreachable;
    // l.rotate(-2, 1);
    // l.pushInteger(1);
    // l.pushInteger(start - 1);
    // l.call(3, 1); // replace the first copy with line:sub(1, start - 1)
    // l.rotate(-2, 1); // put it below another copy
    // _ = l.getMetaField(-1, "sub") catch unreachable;
    // l.rotate(-2, 1);
    // l.pushInteger(start);
    // l.pushInteger(end);
    // l.call(3, 1);
    _ = l.getUserValue(-1, 1) catch unreachable;
    const text = l.toString(-1) catch unreachable;
    if (l.getUserValue(-2, 2) catch unreachable == .userdata and text.len > 0) {
        const mid_segments = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
        const segments = l.newUserdataSlice(Line.Segment, mid_segments.len, 0);
        @memcpy(segments, mid_segments);
        for (segments) |*segment| {
            inline for (colors) |mod| {
                if (std.mem.eql(u8, mod, which)) {
                    @field(segment.style, mod) = color.*;
                    break;
                }
            }
        }
        l.setUserValue(-4, 2) catch unreachable;
    }
    l.pop(2);
    // _ = l.getMetaField(-1, "__concat") catch unreachable;
    // l.insert(-3);
    // l.call(2, 1);
    // l.rotate(-2, 1); // put the concatenation at the bottom
    // _ = l.getMetaField(-1, "sub") catch unreachable;
    // l.rotate(-2, 1);
    // l.pushInteger(end + 1);
    // l.call(2, 1);
    // _ = l.getMetaField(-1, "__concat") catch unreachable;
    // l.insert(-3);
    // l.call(2, 1);
    // const line = l.toUserdata(Line, -1) catch unreachable;
    // std.debug.print("line text: {s}\n", .{middle.text});
    return 1;
}

const colors: [3][]const u8 = .{ "fg", "bg", "ul" };

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const vx = @import("vaxis");
const std = @import("std");
const lu = @import("../../lua_util.zig");
const Line = @import("line.zig").Line;
