/// uses the Unicode Private-Use Area to store long graphemes in a pair of hash maps.
const GraphemeMap = @This();
const std = @import("std");
const first_key: u21 = 0xf0000;

allocator: std.mem.Allocator,
grapheme_to_key: std.StringHashMapUnmanaged(u21) = .{},
key_to_grapheme: std.ArrayListUnmanaged([]const u8) = .{},
next_key: u21 = first_key,
idx: usize = 0,
grapheme_buffer: [16 * 1024]u8 = undefined,

pub fn init(allocator: std.mem.Allocator) GraphemeMap {
    return .{ .allocator = allocator };
}

/// splits the given text into graphemes and submits them
pub fn submitSlice(self: *GraphemeMap, allocator: std.mem.Allocator, utf8text: []const u8) error{ OutOfSpace, OutOfMemory }![][4]u8 {
    var iter = @import("vaxis").ziglyph.GraphemeIterator.init(utf8text);
    var list = std.ArrayList([4]u8).init(allocator);
    errdefer list.deinit();
    while (iter.next()) |grapheme| {
        try list.append(try self.submit(grapheme.slice(utf8text)));
    }
    return list.toOwnedSlice();
}

/// returns a UTF-8 encoded buffer
/// which, if submitted to `get` will return `grapheme`.
/// If `grapheme` has length at most 4 in bytes, it is padded with zeroes and returned
/// returns error.OutOfSpace if the entire section of the private-use area (0xf0000 to 0xffffd) is used
/// or if the grapheme_buffer is full
pub fn submit(self: *GraphemeMap, grapheme: []const u8) error{ OutOfSpace, OutOfMemory }![4]u8 {
    if (grapheme.len <= 4) {
        var key: [4]u8 = .{ 0, 0, 0, 0 };
        @memcpy(key[0..grapheme.len], grapheme);
        return key;
    }
    const res = self.grapheme_to_key.get(grapheme);
    if (res) |val| {
        var key: [4]u8 = .{ 0, 0, 0, 0 };
        _ = std.unicode.utf8Encode(val, &key) catch unreachable;
        return key;
    } else {
        if (self.idx + grapheme.len > self.grapheme_buffer.len) return error.OutOfSpace;
        if (self.next_key > 0xffffd) return error.OutOfSpace;
        @memcpy(self.grapheme_buffer[self.idx..][0..grapheme.len], grapheme);
        try self.key_to_grapheme.append(self.allocator, self.grapheme_buffer[self.idx..][0..grapheme.len]);
        try self.grapheme_to_key.put(self.allocator, grapheme, self.next_key);
        self.idx += grapheme.len;
        var key: [4]u8 = .{ 0, 0, 0, 0 };
        _ = std.unicode.utf8Encode(self.next_key, &key) catch unreachable;
        self.next_key += 1;
        return key;
    }
}

/// given a key previously reserved with `submit`, returns the corresponding grapheme
/// if `key` is valid utf-8 but is outside 0xf0000-0xffffd, returns a slice of key.
/// returns `error.BadKey` if `key` is invalid unicode or represents a key in the private area
/// but outside the range from 0xf0000 to the current next key.
pub fn get(self: GraphemeMap, key: *const [4]u8) error{BadKey}![]const u8 {
    const len: usize = std.unicode.utf8ByteSequenceLength(key[0]) catch return error.BadKey;
    const k = std.unicode.utf8Decode(key[0..len]) catch return error.BadKey;
    if (k < first_key or k > 0xffffd) {
        return key[0..len];
    }
    if (k >= self.next_key) return error.BadKey;
    const idx: usize = k - first_key;
    return self.key_to_grapheme.items[idx];
}

pub fn deinit(self: *GraphemeMap) void {
    self.grapheme_to_key.deinit(self.allocator);
    self.key_to_grapheme.deinit(self.allocator);
    self.* = undefined;
}

test {
    const allocator = std.testing.allocator;
    var map = GraphemeMap.init(allocator);
    defer map.deinit();
    const astronaut = "🧑🏽‍🚀";
    const key = try map.submit(astronaut);
    try std.testing.expectEqual("\u{f0000}".*, key);
    try std.testing.expectEqual(first_key + 1, map.next_key);
    try std.testing.expectEqual(astronaut.len, map.idx);
    const str = try map.get(&key);
    try std.testing.expectEqualStrings(astronaut, str);

    const key_again = try map.submit(astronaut);
    try std.testing.expectEqual(key, key_again);
    try std.testing.expectEqual(first_key + 1, map.next_key);

    const padded = try map.submit("a");
    try std.testing.expectEqual(astronaut.len, map.idx);
    try std.testing.expectEqualSlices(u8, &.{ 'a', 0, 0, 0 }, &padded);
    try std.testing.expectEqualStrings("a", try map.get(&padded));
}
