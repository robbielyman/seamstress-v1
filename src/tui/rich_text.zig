const std = @import("std");
const vaxis = @import("vaxis");
const GraphemeMap = @import("grapheme_map.zig");

pub const Cell = struct {
    utf8: [4]u8 = .{ 0, 0, 0, 0 },
    width: usize = 0,
    fg: vaxis.Color = .default,
    bg: vaxis.Color = .default,
    ul: vaxis.Color = .default,
    ul_style: vaxis.Style.Underline = .off,
    mods: Mods = .{},

    const Mods = packed struct {
        bold: bool = false,
        dim: bool = false,
        italic: bool = false,
        blink: bool = false,
        reverse: bool = false,
        invisible: bool = false,
        strikethrough: bool = false,
    };

    pub fn fromStyleUtf8(utf8: [4]u8, style: vaxis.Style) Cell {
        return .{
            .utf8 = utf8,
            .fg = style.fg,
            .bg = style.bg,
            .ul = style.ul,
            .ul_style = style.ul_style,
            .mods = .{
                .bold = style.bold,
                .dim = style.dim,
                .italic = style.italic,
                .blink = style.blink,
                .reverse = style.reverse,
                .invisible = style.invisible,
                .strikethrough = style.strikethrough,
            },
        };
    }

    /// NB: .grapheme is undefined!
    pub fn toVxCell(self: Cell) vaxis.Cell {
        return .{ .char = .{
            .grapheme = undefined,
            .width = self.width,
        }, .style = .{
            .bg = self.bg,
            .fg = self.fg,
            .ul = self.ul,
            .ul_style = self.ul_style,
            .bold = self.mods.bold,
            .dim = self.mods.dim,
            .italic = self.mods.italic,
            .blink = self.mods.blink,
            .reverse = self.mods.reverse,
            .invisible = self.mods.invisible,
            .strikethrough = self.mods.strikethrough,
        } };
    }
};

pub const Cells = StructOfSlices(Cell);

pub fn freeCells(cells: Cells, allocator: std.mem.Allocator) void {
    const info = @typeInfo(Cells).Struct;
    inline for (info.fields) |field| {
        allocator.free(@field(cells, field.name));
    }
}

fn StructOfSlices(T: type) type {
    const info = @typeInfo(T).Struct;
    std.debug.assert(info.layout != .@"packed");
    var fields: [info.fields.len]std.builtin.Type.StructField = undefined;
    for (&fields, info.fields) |*f, field| {
        f.* = .{
            .name = field.name,
            .type = slice_type: {
                const p: std.builtin.Type.Pointer = .{
                    .size = .Slice,
                    .is_const = false,
                    .is_volatile = false,
                    .alignment = field.alignment,
                    .address_space = .generic,
                    .child = field.type,
                    .is_allowzero = false,
                    .sentinel = null,
                };
                break :slice_type @Type(.{ .Pointer = p });
            },
            .default_value = null,
            .is_comptime = field.is_comptime,
            .alignment = field.alignment,
        };
    }
    return @Type(.{ .Struct = .{
        .backing_integer = null,
        .decls = &.{},
        .fields = &fields,
        .is_tuple = info.is_tuple,
        .layout = info.layout,
    } });
}

pub const RichText = struct {
    const Field = std.MultiArrayList(Cell).Field;

    map: *GraphemeMap,
    cells: std.MultiArrayList(Cell) = .{},
    // counts words
    lines: std.ArrayListUnmanaged(usize) = .{},
    // counts cells
    words: std.ArrayListUnmanaged(usize) = .{},
    current_style: vaxis.Style = .{},

    pub fn init(map: *GraphemeMap) RichText {
        return .{ .map = map };
    }

    /// the slices are assumed to preserve the invariants of this type
    pub fn appendSlices(self: *RichText, allocator: std.mem.Allocator, cells: Cells, lines: []const usize, words: []const usize) std.mem.Allocator.Error!void {
        try self.lines.appendSlice(allocator, lines);
        errdefer self.lines.items.len -= lines.len;
        try self.words.appendSlice(allocator, words);
        errdefer self.words.items.len -= words.len;
        const field_info = @typeInfo(Cells).Struct.fields;
        try self.cells.ensureUnusedCapacity(allocator, @field(cells, field_info[0].name).len);
        var slice = self.cells.slice();
        inline for (field_info) |field| {
            const dest = slice.items(@field(Field, field.name));
            const src = @field(cells, field.name);
            @memcpy(dest.ptr[dest.len..][0..src.len], src);
        }
        slice.len += @field(cells, field_info[0].name).len;
        self.cells = slice.toMultiArrayList();
    }

    /// caller owns allocated memory
    /// clears this RichText
    pub fn toOwnedSlices(self: *RichText, allocator: std.mem.Allocator) std.mem.Allocator.Error!struct { Cells, []usize, []usize } {
        defer self.deinit(allocator);
        var slice = self.cells.toOwnedSlice();
        defer slice.deinit(allocator);
        const lines = try self.lines.toOwnedSlice(allocator);
        errdefer allocator.free(lines);
        const words = try self.words.toOwnedSlice(allocator);
        errdefer allocator.free(words);
        var cells: Cells = undefined;
        const cells_info = @typeInfo(Cell).Struct;
        inline for (cells_info.fields) |cell_field| {
            // FIXME: leaks on out of memory...
            @field(cells, cell_field.name) = try allocator.dupe(cell_field.type, slice.items(@field(Field, cell_field.name)));
        }
        return .{ cells, lines, words };
    }

    /// frees allocated memory and reinitializes
    pub fn deinit(self: *RichText, allocator: std.mem.Allocator) void {
        self.words.deinit(allocator);
        self.cells.deinit(allocator);
        self.lines.deinit(allocator);
        self.* = .{ .map = self.map };
    }

    /// draws to the provided window, starting with the given line index
    pub fn draw(self: *const RichText, win: vaxis.Window, starting_line: usize) void {
        var cell_idx: usize = 0;
        var word_idx: usize = 0;
        for (self.lines.items[0..starting_line]) |line| {
            for (0..line) |i| {
                cell_idx += self.words.items[word_idx + i];
            }
            word_idx += line;
        }
        var row: usize = 0;
        var col: usize = 0;
        const slice = self.cells.slice();
        const widths = slice.items(.width);
        const utf8 = slice.items(.utf8);
        for (self.lines.items[starting_line..]) |line| {
            for (0..line) |i| {
                var wid: usize = 0;
                const word_len = self.words.items[word_idx + i];
                for (0..word_len) |ch| {
                    if (widths[cell_idx + ch] == 0)
                        widths[cell_idx + ch] = win.gwidth(self.map.get(&utf8[cell_idx + ch]) catch unreachable);
                    wid += widths[cell_idx + ch];
                }
                if (col + wid >= win.width) {
                    row += 1;
                    col = 0;
                }
                if (row >= win.height) return;
                for (0..word_len) |ch| {
                    var vxcell = self.cells.get(cell_idx + ch).toVxCell();
                    vxcell.char.grapheme = self.map.get(&utf8[cell_idx + ch]) catch unreachable;
                    win.writeCell(col, row, vxcell);
                    col += widths[cell_idx + ch];
                }
                cell_idx += word_len;
            }
            row += 1;
            col = 0;
            word_idx += line;
        }
    }

    /// adjusts line and word counts at the end of the list
    /// asserts that the list has at least one line
    /// does not re-chunk cells
    pub fn reflowLastLine(self: *RichText, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        std.debug.assert(self.lines.items.len > 0);
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var grapheme_lens = std.ArrayList(usize).init(a);
        var line_text = std.ArrayList(u8).init(a);
        const last_line = self.lines.pop();
        const words = self.words.items[self.words.items.len - last_line ..];
        const cells_count = cells_count: {
            var count: usize = 0;
            for (words) |w| count += w;
            break :cells_count count;
        };
        const utf8 = self.cells.items(.utf8);
        for (utf8[utf8.len - cells_count ..]) |k| {
            const txt = self.map.get(&k) catch unreachable;
            try grapheme_lens.append(txt.len);
            try line_text.appendSlice(txt);
        }
        self.words.items.len -= words.len;
        var cell_idx: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfScalarPos(u8, line_text.items, pos, '\n')) |end| {
            const line = line_text.items[pos .. end + 1];
            var word_count: usize = 0;
            var iter = vaxis.ziglyph.WordIterator.init(line) catch unreachable;
            while (iter.next()) |word| {
                var grapheme_iterator = vaxis.ziglyph.GraphemeIterator.init(word.bytes);
                var count: usize = 0;
                var num_cells: usize = 0;
                while (grapheme_iterator.next()) |grapheme| {
                    count += grapheme.len;
                    if (count >= grapheme_lens.items[cell_idx]) {
                        count -= grapheme_lens.items[cell_idx];
                        cell_idx += 1;
                        num_cells += 1;
                    }
                }
                try self.words.append(allocator, num_cells);
                word_count += 1;
            }
            try self.lines.append(allocator, word_count);
            pos = end + 1;
        } else {
            const line = line_text.items[pos..];
            var word_count: usize = 0;
            var iter = vaxis.ziglyph.WordIterator.init(line) catch unreachable;
            while (iter.next()) |word| {
                var grapheme_iterator = vaxis.ziglyph.GraphemeIterator.init(word.bytes);
                var count: usize = 0;
                var num_cells: usize = 0;
                while (grapheme_iterator.next()) |grapheme| {
                    count += grapheme.len;
                    if (count >= grapheme_lens.items[cell_idx]) {
                        count -= grapheme_lens.items[cell_idx];
                        cell_idx += 1;
                        num_cells += 1;
                    }
                }
                try self.words.append(allocator, num_cells);
                word_count += 1;
            }
            try self.lines.append(allocator, word_count);
        }
        if (self.lines.items[self.lines.items.len - 1] == 0) _ = self.lines.pop();
    }

    /// adds to the current line, creating new ones if bytes contains `'\n'`.
    /// the current style is used.
    fn write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
        const ctx: *const Writer = @ptrCast(@alignCast(context));
        const self = ctx.self;
        const allocator = ctx.allocator;
        const last_line = self.lines.popOrNull() orelse 0;
        // ... is this assuming that the appended bytes don't combine with previous cells?
        var iter = vaxis.ziglyph.GraphemeIterator.init(bytes);
        var fake_count: usize = 0;
        while (iter.next()) |grapheme| {
            const utf8 = try self.map.submit(grapheme.slice(bytes));
            const idx = try self.cells.addOne(allocator);
            self.cells.set(idx, Cell.fromStyleUtf8(utf8, self.current_style));
            fake_count += 1;
        }
        try self.lines.append(allocator, last_line + 1);
        try self.words.append(allocator, fake_count);
        try self.reflowLastLine(allocator);
        return bytes.len;
    }

    pub fn writer(self: *RichText, allocator: std.mem.Allocator) Writer {
        return .{ .self = self, .allocator = allocator };
    }

    pub const Writer = struct {
        self: *RichText,
        allocator: std.mem.Allocator,

        pub fn any(self: *const Writer) std.io.AnyWriter {
            return .{
                .context = self,
                .writeFn = write,
            };
        }
    };
};

test "write" {
    const allocator = std.testing.allocator;
    var map = GraphemeMap.init(allocator);
    var buffer: RichText = .{ .map = &map };
    defer buffer.deinit(allocator);
    const writer = buffer.writer(allocator);
    const any = writer.any();
    const seamstress = "SEAMSTRESS";
    const colors: [10]u8 = .{
        224, 223, 220, 148, 150, 152, 153, 189, 188, 186,
    };
    for (seamstress, &colors) |letter, idx| {
        buffer.current_style.fg = .{ .index = idx };
        try any.print("{c}", .{letter});
    }
    buffer.current_style.fg = .default;
    try any.print("\n", .{});
    buffer.current_style.fg = .{ .index = 45 };
    try any.print("seamstress version: ", .{});
    buffer.current_style.fg = .{ .index = 79 };
    try any.print("{}\n", .{@import("../main.zig").VERSION});
    buffer.current_style.fg = .default;
    const slice = buffer.cells.slice();
    const fg = slice.items(.fg);
    const utf8 = slice.items(.utf8);
    for (seamstress, &colors, 0..) |letter, col, idx| {
        const got = try map.get(&utf8[idx]);
        try std.testing.expectEqualStrings(&.{letter}, got);
        try std.testing.expectEqual(vaxis.Color{ .index = col }, fg[idx]);
    }
    const cells, const lines, const words = try buffer.toOwnedSlices(allocator);
    defer allocator.free(words);
    defer allocator.free(lines);
    defer freeCells(cells, allocator);
    const whole_string = try std.fmt.allocPrint(
        allocator,
        "SEAMSTRESS\nseamstress version: {}\n",
        .{@import("../main.zig").VERSION},
    );
    defer allocator.free(whole_string);
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    for (cells.utf8) |k| {
        try text.appendSlice(try map.get(&k));
    }
    try std.testing.expectEqualStrings(whole_string, text.items);
    try std.testing.expectEqual(2, lines.len);
    for (0..10) |i| {
        try std.testing.expectEqual(colors[i], cells.fg[i].index);
    }
    try buffer.appendSlices(allocator, cells, lines, words);
    const slice2 = buffer.cells.slice();
    const fg2 = slice2.items(.fg);
    const utf82 = slice2.items(.utf8);
    for (seamstress, &colors, 0..) |letter, col, idx| {
        try std.testing.expectEqualStrings(&.{letter}, try map.get(&utf82[idx]));
        try std.testing.expectEqual(vaxis.Color{ .index = col }, fg2[idx]);
    }
}
