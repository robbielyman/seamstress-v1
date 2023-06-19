const std = @import("std");
const events = @import("events.zig");
const c = @import("c_includes.zig").imported;

var quit = false;
var pid: std.Thread = undefined;
var allocator: std.mem.Allocator = undefined;
var buf: std.ArrayList(u8) = undefined;
var history: std.ArrayList(u8) = undefined;
var linebreaks: std.ArrayList(usize) = undefined;
var pos: usize = 0;

pub fn init(allocator_pointer: std.mem.Allocator) !void {
    allocator = allocator_pointer;
    pid = try std.Thread.spawn(.{}, input_run, .{});
}

pub fn deinit() void {
    quit = true;
    pid.join();
    _ = c.endwin();
}

fn input_run() !void {
    buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    history = std.ArrayList(u8).init(allocator);
    defer history.deinit();
    linebreaks = std.ArrayList(usize).init(allocator);
    defer linebreaks.deinit();
    _ = c.initscr();
    _ = c.clear();
    _ = c.noecho();
    _ = c.raw();
    _ = c.keypad(c.stdscr, true);
    while (!quit) {
        try next_char();
    }
    events.post(.{ .Quit = {} });
}

fn next_char() !void {
    const char = c.getch();
    switch (char) {
        0...255 => {
            try buf.insert(pos, @intCast(u8, char));
            pos += 1;
            _ = c.addch(@intCast(c_uint, char));
            _ = c.refresh();
            if (char == 10) {
                var line = try allocator.allocSentinel(u8, buf.items.len, 0);
                std.mem.copyForwards(u8, line, buf.items);
                try history.appendSlice(line);
                const lastbreak = linebreaks.getLast();
                try linebreaks.append(lastbreak + pos);
                const event = .{
                    .Exec_Code_Line = .{
                        .line = line,
                    },
                };
                events.post(event);
                buf.clearAndFree();
                pos = 0;
            }
        },
        else => {},
    }
}
