/// IO mutex and condition
/// also exposes a variant of std.io.BufferedWriter that uses the mutex
const std = @import("std");
pub const bwm = @import("buffered_writer_mutex.zig");

const Io = @This();

mtx: std.Thread.Mutex = .{},
cond: std.Thread.Condition = .{},

pub fn bufferedWriterMutex(self: *Io, underlying_stream: anytype) bwm.BufferedWriterMutex(4096, @TypeOf(underlying_stream)) {
    return bwm.bufferedWriterMutex(underlying_stream, &self.mtx, &self.cond);
}
