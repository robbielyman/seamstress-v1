const std = @import("std");

pub var script_file: [:0]const u8 = "script";
pub var local_port: [:0]const u8 = "7777";
pub var remote_port: [:0]const u8 = "6666";
pub var width: [:0]const u8 = "256";
pub var height: [:0]const u8 = "128";

pub fn parse() !void {
    var args = std.process.args();
    var i: u8 = 0;
    while (args.next()) |*arg| : (i += 1) {
        if (i == 0) {
            continue;
        }
        if ((arg.len != 2) or (arg.*[0] != '-')) {
            break;
        }
        switch (arg.*[1]) {
            'b' => {
                if (args.next()) |next| {
                    remote_port = next;
                    continue;
                }
            },
            'l' => {
                if (args.next()) |next| {
                    local_port = next;
                    continue;
                }
            },
            's' => {
                if (args.next()) |next| {
                    script_file = next;
                    continue;
                }
            },
            'x' => {
                if (args.next()) |next| {
                    width = next;
                    continue;
                }
            },
            'y' => {
                if (args.next()) |next| {
                    height = next;
                    continue;
                }
            },
            else => {
                break;
            },
        }
        break;
    } else {
        args.deinit();
        return;
    }
    args.deinit();
    try print_usage();
    std.process.exit(1);
}

fn print_usage() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("Start seamstress with optional overrides:\n", .{});
    try stdout.print("-s    override user script [current {s}]\n", .{script_file});
    try stdout.print("-l    override OSC listen port [current {s}]\n", .{local_port});
    try stdout.print("-b    override OSC broadcast port [current {s}]\n", .{remote_port});
    try stdout.print("-x    override window width [current {s}]\n", .{width});
    try stdout.print("-y    override window height [current {s}]\n", .{height});
    try bw.flush();
}
