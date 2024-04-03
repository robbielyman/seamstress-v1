const std = @import("std");

/// single producer, single consumer, mutex-protected fifo
/// dynamic memory management
pub fn ThreadSafeBuffer(comptime T: type) type {
    return struct {
        unprotected_fifo: std.fifo.LinearFifo(T, .Dynamic),
        mtx: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .unprotected_fifo = std.fifo.LinearFifo(T, .Dynamic).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            {
                self.mtx.lock();
                defer self.mtx.unlock();
                self.unprotected_fifo.deinit();
            }
            self.* = undefined;
        }

        /// called by the producer
        pub fn appendSlice(self: *Self, slice: []const T) !void {
            self.mtx.lock();
            defer self.mtx.unlock();
            try self.unprotected_fifo.write(slice);
        }

        /// called by the producer
        pub fn append(self: *Self, item: T) !void {
            self.mtx.lock();
            defer self.mtx.unlock();
            try self.unprotected_fifo.writeItem(item);
        }

        /// callable by either the producer or consumer
        pub fn readableLength(self: *Self) usize {
            self.mtx.lock();
            defer self.mtx.unlock();
            return self.unprotected_fifo.readableLength();
        }

        /// called by the consumer
        /// caller owns returned slice
        pub fn dupeReadableSlice(self: *Self, allocator: std.mem.Allocator) ![]T {
            self.mtx.lock();
            defer self.mtx.unlock();
            const slice = self.unprotected_fifo.readableSlice(0);
            return allocator.dupe(T, slice);
        }

        /// called by the consumer
        pub fn discard(self: *Self, count: usize) void {
            self.mtx.lock();
            defer self.mtx.unlock();
            self.unprotected_fifo.discard(count);
        }

        /// called by the consumer
        pub fn readItem(self: *Self) ?T {
            self.mtx.lock();
            defer self.mtx.unlock();
            return self.unprotected_fifo.readItem();
        }

        /// called by the consumer
        pub fn read(self: *Self, buf: []T) usize {
            self.mtx.lock();
            defer self.mtx.unlock();
            return self.unprotected_fifo.read(buf);
        }

        /// called by the consumer
        /// like `read` but does not discard
        pub fn peekContents(self: *Self, buf: []T, offset: usize) usize {
            self.mtx.lock();
            defer self.mtx.unlock();
            const slice = self.unprotected_fifo.readableSlice(offset);
            const len = @min(slice.len, buf.len);
            @memcpy(buf[0..len], slice[0..len]);
            return len;
        }
    };
}
