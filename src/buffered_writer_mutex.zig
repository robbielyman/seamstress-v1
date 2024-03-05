/// compare std.io.BufferedWriter
const std = @import("std");

const io = std.io;
const mem = std.mem;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

pub fn BufferedWriterMutex(comptime buf_size: usize, WriterType: type) type {
    return struct {
        unbuffered_writer: WriterType,
        buf: [buf_size]u8 = undefined,
        end: usize = 0,
        mutex: *Mutex,
        condition: *Condition,

        pub const Error = WriterType.Error || error{Overflow};
        pub const Writer = io.GenericWriter(*Self, Error, write);

        const Self = @This();

        pub fn flush(self: *Self) !void {
            // TODO: should this be tryLock? probably not, right?
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.unbuffered_writer.writeAll(self.buf[0..self.end]);
            self.end = 0;
            self.condition.broadcast();
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (self.end + bytes.len > self.buf.len) {
                try self.flush();
                // we'll just refuse messages that are too long
                if (bytes.len > self.buf.len) return error.Overflow;
            }
            const new_end = self.end + bytes.len;
            @memcpy(self.buf[self.end..new_end], bytes);
            self.end = new_end;
            return bytes.len;
        }
    };
}

pub fn bufferedWriterMutex(underlying_stream: anytype, mutex: *Mutex, condition: *Condition) BufferedWriterMutex(4096, @TypeOf(underlying_stream)) {
    return .{
        .unbuffered_writer = underlying_stream,
        .mutex = mutex,
        .condition = condition,
    };
}
