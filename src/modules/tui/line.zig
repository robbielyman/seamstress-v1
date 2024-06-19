/// @module seamstress.tui
pub fn registerSeamstress(l: *Lua, tui: *Tui) void {
    const n = l.getTop();
    blk: {
        l.newMetatable("seamstress.tui.Line") catch {
            break :blk;
        };

        _ = l.pushStringZ("__index");
        _ = l.pushValue(1); // push the metatable
        l.setTable(-3); // metatable.__index = metatable

        _ = l.pushStringZ("__tostring");
        l.pushFunction(ziglua.wrap(toString));
        l.setTable(-3); // metatable.__tostring = toString

        _ = l.pushStringZ("__concat");
        l.pushFunction(ziglua.wrap(concat));
        l.setTable(-3); // metatable.__concat = concat

        _ = l.pushStringZ("__len");
        l.pushFunction(ziglua.wrap(lenFn));
        l.setTable(-3); // metatable.len = len

        _ = l.pushStringZ("width");
        l.pushFunction(ziglua.wrap(widthFn));
        l.setTable(-3); // metatable.width = width

        _ = l.pushStringZ("sub");
        l.pushLightUserdata(tui);
        l.pushClosure(ziglua.wrap(sub), 1);
        l.setTable(-3); // metatable.sub = sub

        _ = l.pushStringZ("find");
        l.pushFunction(ziglua.wrap(find));
        l.setTable(-3); // metatable.find = find

        _ = l.pushString("__eq");
        l.pushFunction(ziglua.wrap(eql));
        l.setTable(-3); // metatable.eq = eq
    }
    l.pop(1);
    lu.getSeamstress(l);
    _ = l.getField(-1, "tui");
    l.remove(-2);
    _ = l.pushStringZ("Line");
    l.pushLightUserdata(tui);
    l.pushClosure(ziglua.wrap(newFromStringAndStyle), 1);
    l.setTable(-3);
    l.pop(1);
    std.debug.assert(n == l.getTop());
}

/// @type seamstress.tui.Line
pub const Line = struct {
    // a Segment is a contiguous run of text containing no newlines
    // together with a Style
    // Segments are immutable
    pub const Segment = struct {
        byte_len: usize,
        grapheme_len: usize,
        width: usize,
        style: vx.Style,
    };
    grapheme_len: usize,
    width: usize,
    pub fn toSegments(line: []const u8, segments: []const Line.Segment, ret: []vx.Segment) void {
        var byte_idx: usize = 0;
        for (ret, segments) |*segment, src| {
            const text = line[byte_idx..][0..src.byte_len];
            segment.* = .{
                .text = text,
                .style = src.style,
            };
            byte_idx += src.byte_len;
        }
    }
};

/// Operates like `string:find` but for `Line` objects.
/// @function Line:find
/// @tparam Line|string needle sub-line or string to be found
/// @treturn integer start
/// @treturn integer end
fn find(l: *Lua) i32 {
    _ = l.checkUserdata(Line, 1, "seamstress.tui.Line");
    const t = l.typeOf(2);
    const start_idx: ziglua.Integer = @intFromFloat(l.optNumber(3) orelse 1);
    _ = l.getMetaField(1, "sub") catch unreachable;
    l.pushValue(1);
    l.pushInteger(start_idx);
    l.call(2, 1);

    switch (t) {
        .userdata => {
            _ = l.checkUserdata(Line, 2, "seamstress.tui.Line");
            _ = l.getUserValue(1, 1) catch unreachable;
            const haystack = l.toString(-1) catch unreachable;
            _ = l.getUserValue(2, 1) catch unreachable;
            const needle = l.toString(-1) catch unreachable;
            if (std.mem.indexOf(u8, haystack, needle)) |idx| {
                lu.getMethod(l, "tui", "Line");
                _ = l.pushString(haystack[0..idx]);
                l.call(1, 1);
                l.len(-1);
                const offset = l.toInteger(-1) catch unreachable;
                l.pop(4);
                _ = l.getMetaField(1, "sub") catch unreachable;
                l.pushValue(1);
                l.pushInteger(start_idx + offset);
                l.len(2);
                const len = l.toInteger(-1) catch unreachable;
                l.pop(1);
                l.pushInteger(start_idx + offset + len - 1);
                l.call(3, 1);
                l.pushValue(2);
                _ = l.getMetaField(-1, "__eq") catch unreachable;
                l.call(2, 1);
                if (l.toBoolean(-1)) {
                    l.len(1);
                    const length = l.toInteger(-1) catch unreachable;
                    l.pop(2);
                    l.pushInteger((std.math.mod(ziglua.Integer, start_idx + offset - 1, length) catch unreachable) + 1);
                    l.pushInteger((std.math.mod(ziglua.Integer, start_idx + offset + len - 2, length) catch unreachable) + 1);
                    return 2;
                }
            }
            l.pop(2);
            return 0;
        },
        else => {
            const needle = l.toString(2) catch unreachable;
            _ = l.getUserValue(1, 1) catch unreachable;
            const haystack = l.toString(-1) catch unreachable;
            if (std.mem.indexOf(u8, haystack, needle)) |idx| {
                lu.getMethod(l, "tui", "Line");
                _ = l.pushString(haystack[0..idx]);
                l.call(1, 1);
                l.len(-1);
                const offset = l.toInteger(-1) catch unreachable;
                l.pop(2);
                lu.getMethod(l, "tui", "Line");
                l.pushValue(2);
                l.call(1, 1);
                l.len(-1);
                const len = l.toInteger(-1) catch unreachable;
                l.pop(2);
                l.pushValue(1);
                l.len(-1);
                const length = l.toInteger(-1) catch unreachable;
                l.pop(2);
                l.pushInteger((std.math.mod(ziglua.Integer, start_idx + offset - 1, length) catch unreachable) + 1);
                l.pushInteger((std.math.mod(ziglua.Integer, start_idx + offset + len - 2, length) catch unreachable) + 1);
                return 2;
            }
            l.pop(1);
            return 0;
        },
    }
}

/// Tests two `Line` objects for equality
/// @function Line.__eq
fn eql(l: *Lua) i32 {
    const line = l.checkUserdata(Line, 1, "seamstress.tui.Line");
    const other = l.checkUserdata(Line, 2, "seamstress.tui.Line");
    if (line.grapheme_len != other.grapheme_len or line.width != other.width) {
        l.pushBoolean(false);
        return 1;
    }
    _ = l.getUserValue(1, 1) catch unreachable;
    _ = l.getUserValue(2, 1) catch unreachable;
    if (!l.rawEqual(-1, -2)) {
        l.pop(2);
        l.pushBoolean(false);
        return 1;
    }
    l.pop(2);
    const t1 = l.getUserValue(1, 2) catch unreachable;
    const t2 = l.getUserValue(2, 2) catch unreachable;
    if (t1 != t2) {
        l.pop(2);
        l.pushBoolean(false);
        return 1;
    }
    if (t1 == .userdata) {
        const a = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
        const b = l.toUserdataSlice(Line.Segment, -2) catch unreachable;
        for (a, b) |x, y| {
            if (!x.style.eql(y.style) or x.byte_len != y.byte_len or x.grapheme_len != y.grapheme_len or x.width != y.width) {
                l.pop(2);
                l.pushBoolean(false);
                return 1;
            }
        }
    }
    l.pop(2);
    l.pushBoolean(true);
    return 1;
}

/// Returns the length of the line in graphemes.
/// @function Line.__len
fn lenFn(l: *Lua) i32 {
    const line = l.checkUserdata(Line, 1, "seamstress.tui.Line");
    l.pushInteger(@intCast(line.grapheme_len));
    return 1;
}

/// Returns the width of the line in cells
/// @function Line:width
fn widthFn(l: *Lua) i32 {
    const line = l.checkUserdata(Line, 1, "seamstress.tui.Line");
    l.pushInteger(@intCast(line.width));
    return 1;
}

fn toString(l: *Lua) i32 {
    _ = l.checkUserdata(Line, 1, "seamstress.tui.Line");
    _ = l.getUserValue(1, 1) catch unreachable;
    return 1;
}

/// Constructs `Line` objects from strings.
/// Since `Line` objects should not have newlines, an array split by newline is returned.
/// @function seamstress.tui.Line
/// @tparam string|{string,...} text
/// @tparam[opt] Style style
/// @treturn {Line,...}
fn newFromStringAndStyle(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const t1 = l.typeOf(1);
    switch (t1) {
        .userdata => {
            l.getMetatable(1) catch unreachable; // is the argument a Line?
            _ = l.getMetatableRegistry("seamstress.tui.Line");
            if (l.rawEqual(-1, -2)) {
                l.pop(2); // yep!
                l.pushValue(1); // let's return it
                return 1;
            }
            l.pop(2); // nope!
            _ = l.toStringEx(1); // let's push its string value
            l.pushValue(1);
        },
        else => {
            _ = l.toStringEx(1); // let's push its string value
            l.pushValue(1);
        },
    }
    const str = l.toStringEx(-1);
    if (str.len == 0) {
        l.pop(1);
        const line = l.newUserdata(Line, 2);
        _ = l.getMetatableRegistry("seamstress.tui.Line");
        l.setMetatable(-2);
        _ = l.pushString("");
        l.setUserValue(-2, 1) catch unreachable;
        l.pushNil();
        l.setUserValue(-2, 2) catch unreachable;
        line.* = .{
            .grapheme_len = 0,
            .width = 0,
        };
        return 1;
    }
    const t = l.typeOf(2);
    switch (t) {
        .userdata => {
            _ = l.checkUserdata(vx.Style, 2, "tui.Style"); // is the second argument a Style?
            l.pushValue(2); // push it
        },
        else => {
            lu.getMethod(l, "tui", "Style"); // can we make it one?
            l.pushValue(2);
            l.call(1, 1);
        },
    }
    const style: *vx.Style = l.toUserdata(vx.Style, -1) catch {
        std.debug.panic("{s}", .{@tagName(l.typeOf(-1))});
    };
    var tokenizer = std.mem.splitScalar(u8, str, '\n');
    var count: i32 = 0;
    l.newTable();
    while (tokenizer.next()) |token| {
        count += 1;
        const line = l.newUserdata(Line, 2);
        _ = l.getMetatableRegistry("seamstress.tui.Line");
        l.setMetatable(-2);
        _ = l.pushString(token);
        l.setUserValue(-2, 1) catch unreachable;
        const segments = l.newUserdataSlice(Line.Segment, 1, 0);
        var iterator = grapheme.Iterator.init(token, &tui.vaxis.unicode.grapheme_data);
        var width: usize = 0;
        var len: usize = 0;
        while (iterator.next()) |g| {
            width += vx.gwidth.gwidth(g.bytes(token), tui.vaxis.caps.unicode, &tui.vaxis.unicode.width_data) catch unreachable;
            len += 1;
        }
        segments[0] = .{
            .byte_len = token.len,
            .grapheme_len = len,
            .width = width,
            .style = style.*,
        };
        l.setUserValue(-2, 2) catch unreachable;
        line.grapheme_len = len;
        line.width = width;
        l.setIndex(-2, count);
    }
    l.remove(-2);
    l.remove(-2);
    return 1;
}

/// concatenates two Lines or a line and a string
/// @function Line.__concat
/// @treturn Line|{Line,...}
fn concat(l: *Lua) i32 {
    const t1 = l.typeOf(1);
    const t2 = l.typeOf(2);
    var theres_a_table: i2 = 0;
    switch (t1) {
        .number, .string => {
            _ = l.toString(1) catch unreachable;
            lu.getMethod(l, "tui", "Line");
            l.pushValue(1);
            l.call(1, 1);
            theres_a_table = -1;
            _ = l.rawGetIndex(-1, @intCast(l.rawLen(-1)));
            _ = l.checkUserdata(Line, 2, "seamstress.tui.Line");
            l.pushValue(2);
        },
        .userdata => {
            _ = l.checkUserdata(Line, 1, "seamstress.tui.Line");
            switch (t2) {
                .number, .string => {
                    _ = l.toString(2) catch unreachable;
                    lu.getMethod(l, "tui", "Line");
                    _ = l.pushValue(2);
                    l.call(1, 1);
                    theres_a_table = 1;
                    l.pushValue(1);
                    _ = l.rawGetIndex(-2, 1);
                },
                .userdata => {
                    _ = l.checkUserdata(Line, 2, "seamstress.tui.Line");
                    l.pushValue(1);
                    l.pushValue(2);
                },
                else => l.typeError(2, "line or string"),
            }
        },
        else => l.typeError(1, "line or string"),
    }
    const first = l.toUserdata(Line, -2) catch unreachable;
    const second = l.toUserdata(Line, -1) catch unreachable;
    const line = l.newUserdata(Line, 2);
    _ = l.getMetatableRegistry("seamstress.tui.Line");
    l.setMetatable(-2);
    _ = l.getUserValue(-3, 1) catch unreachable;
    const str_a = l.toString(-1) catch unreachable;
    _ = l.getUserValue(-3, 1) catch unreachable;
    const str_b = l.toString(-1) catch unreachable;
    const len = str_a.len + str_b.len;
    var buf: ziglua.Buffer = undefined;
    const slice = buf.initSize(l, len);
    @memcpy(slice[0..str_a.len], str_a);
    @memcpy(slice[str_a.len..], str_b);
    l.pop(2);
    buf.pushResultSize(len);
    l.setUserValue(-2, 1) catch unreachable;
    const t3 = l.getUserValue(-3, 2) catch unreachable;
    const t4 = l.getUserValue(-3, 2) catch unreachable;
    switch (t3) {
        .userdata => {
            switch (t4) {
                .userdata => {
                    const a = l.toUserdataSlice(Line.Segment, -2) catch unreachable;
                    const b = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
                    if (a[a.len - 1].style.eql(b[0].style)) {
                        const new_len = a.len + b.len - 1;
                        const c = l.newUserdataSlice(Line.Segment, new_len, 0);
                        @memcpy(c[0..a.len], a);
                        @memcpy(c[a.len..], b[1..]);
                        c[a.len - 1].byte_len = a[a.len - 1].byte_len + b[0].byte_len;
                        c[a.len - 1].grapheme_len = a[a.len - 1].grapheme_len + b[0].grapheme_len;
                        c[a.len - 1].width = a[a.len - 1].width + b[0].width;
                    } else {
                        const c = l.newUserdataSlice(Line.Segment, a.len + b.len, 0);
                        @memcpy(c[0..a.len], a);
                        @memcpy(c[a.len..], b);
                    }
                    l.setUserValue(-4, 2) catch unreachable;
                },
                else => {
                    const a = l.toUserdataSlice(Line.Segment, -2) catch unreachable;
                    const c = l.newUserdataSlice(Line.Segment, a.len, 0);
                    @memcpy(c, a);
                    l.setUserValue(-4, 2) catch unreachable;
                },
            }
        },
        else => {
            switch (t4) {
                .userdata => {
                    const b = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
                    const c = l.newUserdataSlice(Line.Segment, b.len, 0);
                    @memcpy(c, b);
                    l.setUserValue(-4, 2) catch unreachable;
                },
                else => {
                    if (len == 0) {
                        l.pushNil();
                        l.setUserValue(-4, 2) catch unreachable;
                    } else {
                        const c = l.newUserdataSlice(Line.Segment, 1, 0);
                        c[0] = .{
                            .byte_len = len,
                            .grapheme_len = first.grapheme_len + second.grapheme_len,
                            .width = first.width + second.width,
                            .style = .{},
                        };
                    }
                },
            }
        },
    }
    line.* = .{
        .grapheme_len = first.grapheme_len + second.grapheme_len,
        .width = first.width + second.width,
    };
    l.pop(2);
    l.remove(-2);
    l.remove(-2);
    switch (theres_a_table) {
        0 => {},
        1 => l.setIndex(-2, 1),
        -1 => l.setIndex(-2, @intCast(l.rawLen(-2))),
        else => unreachable,
    }
    return 1;
}

/// Behaves like `string:sub` but operates on `Line` objects
/// @function Line:sub
/// @tparam integer start
/// @tparam[opt=-1] integer end
fn sub(l: *Lua) i32 {
    const tui = lu.closureGetContext(l, Tui);
    const line = l.checkUserdata(Line, 1, "seamstress.tui.Line");
    if (line.grapheme_len == 0) {
        const ret = l.newUserdata(Line, 2);
        _ = l.getMetatableRegistry("seamstress.tui.Line");
        l.setMetatable(-2);
        _ = l.pushString("");
        l.setUserValue(-2, 1) catch unreachable;
        l.pushNil();
        l.setUserValue(-2, 2) catch unreachable;
        ret.* = .{
            .grapheme_len = 0,
            .width = 0,
        };
        return 1;
    }
    const start: ziglua.Integer = @intFromFloat(l.checkNumber(2));
    const end: ziglua.Integer = @intFromFloat(l.optNumber(3) orelse -1);
    const num: ziglua.Integer = @intCast(line.grapheme_len);
    const offset: usize = switch (start) {
        0 => 0,
        1...std.math.maxInt(ziglua.Integer) => @intCast(start - 1),
        else => @intCast(@max(0, start + num)),
    };
    if (offset >= line.grapheme_len) {
        const ret = l.newUserdata(Line, 2);
        _ = l.getMetatableRegistry("seamstress.tui.Line");
        l.setMetatable(-2);
        _ = l.pushString("");
        l.setUserValue(-2, 1) catch unreachable;
        l.pushNil();
        l.setUserValue(-2, 2) catch unreachable;
        ret.* = .{
            .grapheme_len = 0,
            .width = 0,
        };
        return 1;
    }
    const len: usize = switch (end) {
        1...std.math.maxInt(ziglua.Integer) => @as(usize, @intCast(end)) -| offset,
        0 => 0,
        else => @as(usize, @intCast(@max(0, end + num + 1))) -| offset,
    };
    if (len == 0) {
        const ret = l.newUserdata(Line, 2);
        _ = l.getMetatableRegistry("seamstress.tui.Line");
        l.setMetatable(-2);
        _ = l.pushString("");
        l.setUserValue(-2, 1) catch unreachable;
        l.pushNil();
        l.setUserValue(-2, 2) catch unreachable;
        ret.* = .{
            .grapheme_len = 0,
            .width = 0,
        };
        return 1;
    }

    const ret = l.newUserdata(Line, 2);
    _ = l.getMetatableRegistry("seamstress.tui.Line");
    l.setMetatable(-2);
    _ = l.getUserValue(1, 2) catch unreachable;
    const segments = l.toUserdataSlice(Line.Segment, -1) catch unreachable;
    _ = l.getUserValue(1, 1) catch unreachable;
    const text = l.toString(-1) catch unreachable;
    var segment_offset: usize = 0;
    var gr_idx: usize = 0;
    var byte_idx: usize = 0;
    var w: usize = 0;
    while (gr_idx < offset) {
        const n = segments[segment_offset].grapheme_len;
        if (gr_idx + n > offset) break;
        byte_idx += segments[segment_offset].byte_len;
        w += segments[segment_offset].width;
        gr_idx += n;
        segment_offset += 1;
    }
    const new_segs = l.newUserdataSlice(Line.Segment, segments.len - segment_offset, 0);
    @memcpy(new_segs, segments[segment_offset..]);
    const src = text[byte_idx..];
    var iterator = grapheme.Iterator.init(src, &tui.vaxis.unicode.grapheme_data);
    var gr_in_seg: usize = 0;
    var byte_in_seg: usize = 0;
    var width: usize = 0;
    while (iterator.next()) |g| {
        if (gr_idx < offset) {
            gr_idx += 1;
            byte_idx += g.len;
            gr_in_seg += 1;
            byte_in_seg += g.len;
            const gw = vx.gwidth.gwidth(g.bytes(src), tui.vaxis.caps.unicode, &tui.vaxis.unicode.width_data) catch unreachable;
            w += gw;
            width += gw;
        } else break;
    }
    new_segs[0].byte_len -= byte_in_seg;
    new_segs[0].grapheme_len -= gr_in_seg;
    new_segs[0].width -= width;
    // common special case
    if (len >= line.grapheme_len - offset) {
        l.remove(-2);
        l.remove(-2);
        _ = l.pushString(text[byte_idx..]);
        ret.* = .{
            .grapheme_len = line.grapheme_len - offset,
            .width = line.width - w,
        };
        l.setUserValue(-3, 1) catch unreachable;
        l.setUserValue(-2, 2) catch unreachable;
        return 1;
    }

    // this is slightly wasteful of memory...
    segment_offset = 0;
    gr_idx = 0;
    byte_idx -= byte_in_seg;
    w = 0;
    while (gr_idx < len) {
        const n = new_segs[segment_offset].grapheme_len;
        if (gr_idx + n > len) break;
        byte_idx += new_segs[segment_offset].byte_len;
        w += new_segs[segment_offset].width;
        gr_idx += n;
        segment_offset += 1;
    }
    const real_segments = l.newUserdataSlice(Line.Segment, new_segs.len - segment_offset, 0);
    @memcpy(real_segments, new_segs[0..real_segments.len]);
    const src_2 = text[byte_idx..];
    iterator = grapheme.Iterator.init(src_2, &tui.vaxis.unicode.grapheme_data);
    gr_in_seg = 0;
    byte_in_seg = 0;
    width = 0;
    while (iterator.next()) |g| {
        if (gr_idx < len) {
            gr_idx += 1;
            byte_idx += g.len;
            gr_in_seg += 1;
            byte_in_seg += g.len;
            const gw = vx.gwidth.gwidth(g.bytes(src_2), tui.vaxis.caps.unicode, &tui.vaxis.unicode.width_data) catch unreachable;
            w += gw;
            width += gw;
        } else break;
    }
    real_segments[real_segments.len - 1].byte_len = byte_in_seg;
    real_segments[real_segments.len - 1].grapheme_len = gr_in_seg;
    real_segments[real_segments.len - 1].width = width;
    l.remove(-2);
    l.remove(-2);
    l.remove(-2);

    _ = l.pushString(src[0..byte_idx]);
    ret.* = .{
        .grapheme_len = len,
        .width = w,
    };
    l.setUserValue(-3, 1) catch unreachable;
    l.setUserValue(-2, 2) catch unreachable;
    return 1;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const vx = @import("vaxis");
const grapheme = @import("grapheme");
const lu = @import("../../lua_util.zig");
const Tui = @import("../tui.zig");
const std = @import("std");
