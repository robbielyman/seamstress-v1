const std = @import("std");
const events = @import("events.zig");

const logger = std.log.scoped(.socket);
var allocator: std.mem.Allocator = undefined;
var listener: std.net.StreamServer = undefined;
var pid: std.Thread = undefined;
var quit = false;

pub fn init(alloc_pointer: std.mem.Allocator, port: u16) !void {
    quit = false;
    allocator = alloc_pointer;
    const addr = try std.net.Address.resolveIp("127.0.0.1", port);
    listener = std.net.StreamServer.init(.{});
    try listener.listen(addr);
    pid = try std.Thread.spawn(.{}, loop, .{});
}

pub fn deinit() void {
    listener.deinit();
    quit = true;
    pid.join();
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
    while (!quit) {
        const connection = listener.accept() catch |err| {
            logger.err("connection error: {}", .{err});
            continue;
        };
        logger.info("new connection: {}", .{connection.address.in.getPort()});
        defer connection.stream.close();
        var stream = connection.stream;
        const line = receive(&stream) catch |err| {
            logger.err("receive error: {}", .{err});
            continue;
        };
        const event = .{
            .Exec_Code_Line = .{
                .line = line,
            },
        };
        events.post(event);
    }
}
