const std = @import("std");
const events = @import("events.zig");

const logger = std.log.scoped(.socket);
var buf: [16 * 1024]u8 = undefined;
var allocator: std.mem.Allocator = undefined;
var listener: std.net.Server = undefined;
var pid: std.Thread = undefined;
var quit = false;

pub fn init(port: u16) !void {
    quit = false;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    allocator = fba.allocator();
    const addr = try std.net.Address.resolveIp("127.0.0.1", port);
    listener = try addr.listen(.{});
    pid = try std.Thread.spawn(.{}, loop, .{});
}

pub fn deinit() void {
    quit = true;
    pid.join();
    listener.deinit();
}

const ReceiveError = error{
    EOF,
    BufferExceeded,
};

fn receive(stream: *std.net.Stream) ![:0]const u8 {
    var recv_buf: [8196]u8 = undefined;
    var recv_total: usize = 0;
    while (stream.read(recv_buf[recv_total..])) |recv_len| {
        if (recv_len == 0) {
            if (recv_total == 0) return ReceiveError.EOF;
            break;
        }
        recv_total += recv_len;
        if (std.mem.containsAtLeast(
            u8,
            recv_buf[0..recv_total],
            1,
            "\r\n\r\n",
        )) break;

        if (recv_total >= recv_buf.len) return ReceiveError.BufferExceeded;
    } else |err| return err;

    return allocator.dupeZ(u8, recv_buf[0..recv_total]) catch @panic("OOM!");
}

pub fn loop() !void {
    pid.setName("socket_thread") catch {};
    while (!quit) {
        var fds: [1]std.posix.pollfd = .{
            .{
                .fd = listener.stream.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };
        const ready = try std.posix.poll(&fds, 1000);
        if (ready == 0) continue;
        const connection = try listener.accept();
        logger.info("new connection: {}", .{connection.address.getPort()});
        defer connection.stream.close();
        var stream = connection.stream;
        const line = receive(&stream) catch |err| {
            logger.err("receive error: {}", .{err});
            continue;
        };
        events.post(.{ .Exec_Code_Line = .{ .line = line, .allocator = allocator } });
    }
}
