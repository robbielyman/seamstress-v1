fd: std.posix.fd_t,

/// actually used by our code
pub fn init() @This() {
    const stdin = std.io.getStdIn();
    return .{
        .fd = stdin.handle,
    };
}

/// required by the xev.stream API
pub fn initFd(fd: std.posix.fd_t) @This() {
    return .{
        .fd = fd,
    };
}

const S = xev.stream.Stream(xev, @This(), .{
    .read = .read,
    .write = .none,
    .close = false,
    .threadpool = false,
});

pub const ReadError = S.ReadError;
pub const read = S.read;

const xev = @import("xev");
const std = @import("std");
