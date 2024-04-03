const Self = @This();

const Field = gb.MultiGapBuffer(rt.Cell).Field;
pub const Cursor = struct {
    // a logical index into `lines`
    line: usize = 0,
    // a logical index into `cells`
    cell: usize = 0,
    // an offset within a line
    // must be kept within `0..self.lines.getAt(self.cursor.line)`
    // unless at the very end of the buffer
    cell_offset: usize = 0,
};

map: *GraphemeMap,
cells: gb.MultiGapBuffer(rt.Cell) = .{},
lines: gb.GapBufferUnmanaged(usize) = .{},
cursor: Cursor = .{},

pub fn isEmpty(self: Self) bool {
    return self.cells.realLength() == 0 and self.lines.realLength() == 0;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.cells.deinit(allocator);
    self.lines.deinit(allocator);
    self.* = undefined;
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.cells.gap_start = 0;
    self.cells.gap_end = self.cells.capacity;
    self.lines.clearRetainingCapacity();
    self.cursor = .{};
}

pub const CursorRelative = enum { before, after };

/// adds the given text to the buffer with the given style, breaking lines at '\n'
pub fn addText(self: *Self, allocator: std.mem.Allocator, txt: []const u8, style: vaxis.Style, location: CursorRelative) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cell_keys = try self.map.submitSlice(a, txt);
    defer a.free(cell_keys);
    const cells = try a.alloc(rt.Cell, cell_keys.len);
    defer a.free(cells);
    for (cell_keys, 0..) |key, i| {
        cells[i] = rt.Cell.fromStyleUtf8(key, style);
    }
    try self.addCells(allocator, cells, location);
}

/// adds the given slice of cells to the buffer, breaking lines at '\n'
pub fn addCells(self: *Self, allocator: std.mem.Allocator, cells: []rt.Cell, location: CursorRelative) !void {
    if (cells.len == 0) return;
    const was_empty = self.isEmpty();
    var line = if (!was_empty) self.lines.getAtPtr(self.cursor.line) else blk: {
        const line = try self.lines.addOneBefore(allocator);
        line.* = 0;
        break :blk line;
    };
    if (!was_empty) self.lines.moveGap(self.cursor.line + 1);
    if (!was_empty) self.cells.moveGap(@min(self.cursor.cell + 1, self.cells.realLength()));
    try self.cells.ensureUnusedCapacity(allocator, cells.len);
    for (cells) |cell| {
        self.cells.appendBeforeAssumeCapacity(cell);
        line.* += 1;
        if (cell.utf8[0] == '\n') {
            line = try self.lines.addOneBefore(allocator);
            line.* = 0;
        }
    }
    if (self.lines.items[self.lines.items.len - 1] == 0) _ = self.lines.popBefore();
    if (location == .before) self.moveForwardN(cells.len);
}

/// deletes from `self.cursor` to `position`
/// returns the cells deleted; caller owns the memory.
/// asserts that `position` is within bounds
pub fn cutToPosition(self: *Self, allocator: std.mem.Allocator, position: Cursor) ![]rt.Cell {
    if (position.cell == self.cursor.cell) return &.{};
    self.assertInBounds(position);
    const beginning = if (self.cursor.cell < position.cell) self.cursor else position;
    const ending = if (self.cursor.cell < position.cell) position else self.cursor;
    const cells = try allocator.alloc(rt.Cell, ending.cell - beginning.cell);
    self.cells.moveGap(beginning.cell);
    for (cells) |*c| {
        c.* = self.cells.popAfter();
    }
    self.cursor = self.breakLines(beginning, ending);
    return cells;
}

/// deletes from `self.cursor` to `position`
/// asserts that `position` is within bounds
pub fn deleteToPosition(self: *Self, position: Cursor) void {
    if (position.cell == self.cursor.cell) return;
    self.assertInBounds(position);
    const beginning = if (self.cursor.cell < position.cell) self.cursor else position;
    const ending = if (self.cursor.cell < position.cell) position else self.cursor;
    self.cells.moveGap(beginning.cell);
    self.cells.gap_end += ending.cell - beginning.cell;
    self.cursor = self.breakLines(beginning, ending);
}

fn breakLines(self: *Self, beginning: Cursor, ending: Cursor) Cursor {
    var ret = beginning;
    self.lines.moveGap(beginning.line);
    const last_line = self.lines.getAt(ending.line);
    self.lines.second_start += ending.line - beginning.line;
    const new_last = (last_line - ending.cell_offset) + beginning.cell_offset;
    if (new_last > 0)
        self.lines.items.ptr[self.lines.second_start] = new_last
    else {
        _ = self.lines.popAfter();
        if (self.lines.realLength() != 0) {
            ret.line -= 1;
            ret.cell_offset = self.lines.items[self.lines.items.len - 1];
        } else {
            ret = .{};
        }
    }
    return ret;
}

const Prompt = struct {
    first: []const u8,
    after: ?[]const u8 = null,
    style: vaxis.Style,
};

pub fn draw(self: *const Self, win: vaxis.Window, prompt: ?Prompt) void {
    var col: usize = 0;
    var row: usize = 0;
    if (prompt) |p| {
        var iter = vaxis.ziglyph.GraphemeIterator.init(p.first);
        while (iter.next()) |g| {
            const w = win.gwidth(g.slice(p.first));
            const cell: vaxis.Cell = .{
                .char = .{ .grapheme = g.slice(p.first), .width = w },
                .style = p.style,
            };
            win.writeCell(col, row, cell);
            col += w;
        }
    }
    var cells: usize = 0;
    const slice = self.cells.slice();
    const utf8_ptr = slice.getPtr(.utf8);
    const width_ptr = slice.getPtr(.width);
    for (0..self.lines.realLength()) |idx| {
        if (idx > 0)
            if (prompt) |p| {
                const txt = p.after orelse p.first;
                var iter = vaxis.ziglyph.GraphemeIterator.init(txt);
                while (iter.next()) |g| {
                    const w = win.gwidth(g.slice(txt));
                    const cell: vaxis.Cell = .{
                        .char = .{ .grapheme = g.slice(txt), .width = w },
                        .style = p.style,
                    };
                    win.writeCell(col, row, cell);
                    col += w;
                }
            };
        const line = self.lines.getAt(idx);
        for (0..line) |i| {
            var vxcell: vaxis.Cell = self.cells.get(cells + i).toVxCell();
            const j = self.cells.realIndex(cells + i);
            vxcell.char.grapheme = self.map.get(&utf8_ptr[j]) catch unreachable;
            if (width_ptr[j] == 0) {
                width_ptr[j] = win.gwidth(self.map.get(&utf8_ptr[j]) catch unreachable);
                vxcell.char.width = width_ptr[j];
            }
            win.writeCell(col, row, vxcell);
            if (cells + i == self.cursor.cell) win.showCursor(col, row);
            col += width_ptr[j];
        }
        cells += line;
        if (cells == self.cursor.cell and idx + 1 == self.lines.realLength()) win.showCursor(col, row);
        row += 1;
        col = 0;
    }
}

inline fn assertInBounds(self: Self, cursor: Cursor) void {
    std.debug.assert(cursor.cell <= self.cells.realLength() and cursor.line < self.lines.realLength());
    if (cursor.cell == self.cells.realLength())
        std.debug.assert(cursor.cell_offset == self.lines.getAt(cursor.line))
    else
        std.debug.assert(cursor.cell_offset < self.lines.getAt(cursor.line));
}

pub fn moveBack(self: *Self) void {
    self.moveBackN(1);
}

pub fn moveBackN(self: *Self, count: usize) void {
    var left = count;
    while (left > 0) {
        if (self.cursor.cell_offset == 0) {
            if (self.cursor.line == 0) return;
            self.cursor.line -= 1;
            self.cursor.cell_offset = self.lines.getAt(self.cursor.line);
        }
        const to_move = @min(left, self.cursor.cell_offset);
        self.cursor.cell -= to_move;
        self.cursor.cell_offset -= to_move;
        left -= to_move;
    }
}

pub fn deleteBack(self: *Self) void {
    self.deleteBackN(1);
}

pub fn deleteBackN(self: *Self, count: usize) void {
    const cursor = self.cursor;
    self.moveBackN(count);
    self.deleteToPosition(cursor);
}

pub fn moveForward(self: *Self) void {
    self.moveForwardN(1);
}

pub fn moveForwardN(self: *Self, count: usize) void {
    if (self.isEmpty()) {
        self.cursor = .{};
        return;
    }
    var left = count;
    while (left > 0) {
        const line = self.lines.getAt(self.cursor.line);
        const to_move = @min(left, line - self.cursor.cell_offset);
        self.cursor.cell += to_move;
        self.cursor.cell_offset += to_move;
        if (self.cursor.cell_offset == line) {
            if (self.cursor.line + 1 < self.lines.realLength()) {
                self.cursor.line += 1;
                self.cursor.cell_offset = 0;
            } else return;
        }
        left -= to_move;
    }
}

pub fn deleteForward(self: *Self) void {
    self.deleteForwardN(1);
}

pub fn deleteForwardN(self: *Self, count: usize) void {
    const cursor = self.cursor;
    self.moveForwardN(count);
    self.deleteToPosition(cursor);
}

pub fn moveToStart(self: *Self) void {
    self.cursor = .{};
}

pub fn moveToEnd(self: *Self) void {
    const to_move = self.cells.realLength() - self.cursor.cell;
    self.moveForwardN(to_move);
}

test "basic usage" {
    const allocator = std.testing.allocator;
    var map = GraphemeMap.init(allocator);
    defer map.deinit();
    var rtb: Self = .{ .map = &map };
    defer rtb.deinit(allocator);
    rtb.moveBack();
    rtb.moveForward();
    for (0..6) |_| try rtb.addText(allocator, "aaa", .{}, .after);
    rtb.moveForwardN(25);
    rtb.moveBackN(30);
    rtb.deleteForwardN(12);
    rtb.moveForwardN(6);
    rtb.deleteBackN(9);
    try std.testing.expect(rtb.isEmpty());
    try rtb.addText(allocator, "abc\ndef\n", .{}, .before);
    try std.testing.expectEqual(2, rtb.lines.realLength());
    try std.testing.expectEqual(1, rtb.cursor.line);
    try std.testing.expectEqual(8, rtb.cursor.cell);
    try std.testing.expectEqual(4, rtb.cursor.cell_offset);
    rtb.clearRetainingCapacity();
}

const gb = @import("gap_buffer");
const std = @import("std");
const rt = @import("rich_text.zig");
const GraphemeMap = @import("grapheme_map.zig");
const vaxis = @import("vaxis");
