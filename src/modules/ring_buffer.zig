pub fn RingBuffer(comptime T: type, comptime n: usize) type {
    return struct {
        buf: [n]T = undefined,
        head: atomic.Value(usize) = atomic.Value(usize).init(0),
        tail: atomic.Value(usize) = atomic.Value(usize).init(0),

        const Self = @This();

        pub fn push(self: *Self, val: T) bool {
            const head = self.head.load(.unordered);
            const next = (head + 1) % n;
            if (next == self.tail.load(.acquire)) return false;
            self.buf[head] = val;
            self.head.store(next, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            const tail = self.tail.load(.unordered);
            if (tail == self.head.load(.acquire)) return null;
            const val = self.buf[tail];
            self.tail.store((tail + 1) % n, .release);
            return val;
        }

        pub fn read(self: *Self, buf: []T) usize {
            const tail = self.tail.load(.unordered);
            const head = self.head.load(.acquire);
            const length = @min(if (head >= tail) head - tail else (head + n) - tail, buf.len);
            if (tail + length > n) {
                const second_len = (tail + length) - n;
                @memcpy(buf[0 .. length - second_len], self.buf[tail..]);
                @memcpy(buf[length - second_len ..][0..second_len], self.buf[0..second_len]);
                self.tail.store(second_len, .release);
                return length;
            }
            @memcpy(buf[0..length], self.buf[tail..][0..length]);
            self.tail.store((tail + length) % n, .release);
            return length;
        }

        pub fn write(self: *Self, buf: []const T) usize {
            const head = self.head.load(.unordered);
            const tail = self.tail.load(.acquire);
            const length = @min(if (head >= tail) head - tail else (head + n) - tail, buf.len);
            if (head + length > n) {
                const second_len = (head + length) - n;
                @memcpy(self.buf[head..], buf[0 .. length - second_len]);
                @memcpy(self.buf[0..second_len], buf[length - second_len ..][0..second_len]);
                self.head.store(second_len, .release);
                return length;
            }
            @memcpy(self.buf[head..][0..length], buf[0..length]);
            self.head.store((head + length) % n, .release);
            return length;
        }

        pub fn len(self: Self) usize {
            const head = self.head.load(.unordered);
            const tail = self.tail.load(.unordered);
            return if (head >= tail) head - tail else (head + n) - tail;
        }
    };
}

const std = @import("std");
const atomic = std.atomic;
