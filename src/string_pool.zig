/// stores optionally sentinel-terminated strings
pub fn StringPool(comptime s: ?u8) type {
    return struct {
        const Self = @This();
        const Slice = if (s) |sentinel| [:sentinel]const u8 else []const u8;
        const SliceMut = if (s) |sentinel| [:sentinel]u8;

        const Context = struct {
            pub fn hash(_: Context, a: Slice) u32 {
                return std.array_hash_map.hashString(a);
            }

            pub fn eql(_: Context, a: Slice, b: Slice, _: usize) bool {
                return std.array_hash_map.eqlString(a, b);
            }
        };

        allocator: std.mem.Allocator,
        map: std.ArrayHashMapUnmanaged(Slice, void, Context, true) = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            for (self.map.keys()) |k| self.allocator.free(k);
            self.map.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn intern(self: *Self, string: Slice) !Slice {
            const val = try self.map.getOrPut(self.allocator, string);
            if (val.found_existing) return val.key_ptr.*;
            const canonical_key: SliceMut = if (s) |sentinel| try self.allocator.allocSentinel(u8, string.len, sentinel) else self.allocator.alloc(u8, string.len);
            @memcpy(canonical_key, string);
            val.key_ptr.* = canonical_key;
            return canonical_key;
        }
    };
}

test "basic operation" {
    var pool = StringPool(0).init(std.testing.allocator);
    defer pool.deinit();
    const a = "this is a test string";
    const b = "this is a test string";
    try std.testing.expect(@intFromPtr((try pool.intern(a)).ptr) == @intFromPtr((try pool.intern(b)).ptr));
    try std.testing.expectEqualStrings(b, try pool.intern(a));
}

const std = @import("std");
