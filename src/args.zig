const std = @import("std");

pub var script_file: []const u8 = "script";
pub var local_port: [:0]const u8 = "7777";
pub var remote_port: [:0]const u8 = "6666";
pub var socket_port: [:0]const u8 = "8888";
pub var width: [:0]const u8 = "256";
pub var height: [:0]const u8 = "128";
pub var watch = false;

pub const CreateOptions = enum { script, project, norns_project };

pub fn parse() !?CreateOptions {
    var double_dip = false;
    var args = std.process.args();
    defer args.deinit();
    var i: u8 = 0;
    while (args.next()) |arg| : (i += 1) {
        if (i == 0) {
            continue;
        }
        if (i == 1) {
            if (std.mem.eql(u8, arg, "create-script")) {
                return .script;
            } else if (std.mem.eql(u8, arg, "create-project")) {
                return .project;
            } else if (std.mem.eql(u8, arg, "create-norns-project")) {
                return .norns_project;
            }
        }
        if ((arg.len != 2) or (arg[0] != '-')) {
            if (!double_dip) {
                script_file = arg;
                double_dip = true;
                continue;
            } else break;
        }
        switch (arg[1]) {
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
            'p' => {
                if (args.next()) |next| {
                    socket_port = next;
                    continue;
                }
            },
            's' => {
                if (args.next()) |next| {
                    script_file = next;
                    continue;
                }
            },
            'w' => {
                watch = true;
                continue;
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
        const suffix = ".lua";
        if (script_file.len >= suffix.len and
            std.mem.eql(
            u8,
            suffix,
            script_file[(script_file.len - suffix.len)..script_file.len],
        )) script_file = script_file[0..(script_file.len - suffix.len)];
        return null;
    }
    try print_usage();
    std.process.exit(1);
}

fn print_usage() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("USAGE: seamstress [script] [args]\n\n", .{});
    try stdout.print("[script] (optional) should be the name of a lua file in CWD or ~/seamstress\n", .{});
    try stdout.print("[args]   (optional) should be one or more of the following\n", .{});
    try stdout.print("-s       override user script [current {s}]\n", .{script_file});
    try stdout.print("-l       override OSC listen port [current {s}]\n", .{local_port});
    try stdout.print("-b       override OSC broadcast port [current {s}]\n", .{remote_port});
    try stdout.print("-p       override socket listen port [current {s}]\n", .{socket_port});
    try stdout.print("-w       watch the directory containing the script file for changes\n", .{});
    try stdout.print("-x       override window width [current {s}]\n", .{width});
    try stdout.print("-y       override window height [current {s}]\n", .{height});
    try bw.flush();
}
