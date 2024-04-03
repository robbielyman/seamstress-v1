const std = @import("std");

mtx: std.Thread.Mutex = .{},
stderr: std.io.BufferedWriter(4096, std.io.AnyWriter),

pub fn replaceUnderlyingStream(self: *@This(), new: std.io.AnyWriter) std.io.AnyWriter {
    self.mtx.lock();
    defer self.mtx.unlock();
    const old = self.stderr.unbuffered_writer;
    self.stderr.unbuffered_writer = new;
    return old;
}

pub fn init(unbuffered_writer: std.io.AnyWriter) @This() {
    return .{
        .stderr = std.io.bufferedWriter(unbuffered_writer),
    };
}
