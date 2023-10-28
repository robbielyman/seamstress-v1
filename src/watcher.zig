const std = @import("std");
const events = @import("events.zig");
const logger = std.log.scoped(.watcher);

var thread: std.Thread = undefined;
var quit = false;

pub fn deinit() void {
    quit = true;
    thread.join();
}

pub fn init(path: [*:0]const u8) !void {
    quit = false;
    thread = try std.Thread.spawn(.{}, loop, .{path});
}

fn loop(path: [*:0]const u8) !void {
    thread.setName("watcher_thread") catch {};
    var last_changed: ?i128 = null;
    while (!quit) {
        std.time.sleep(std.time.ns_per_s);
        const file = try std.fs.openFileAbsoluteZ(path, .{});
        defer file.close();
        const m = try file.metadata();
        const time = m.modified();
        if (last_changed) |*l| {
            if (time != l.*) {
                const event = .{
                    .Reset = {},
                };
                events.post(event);
            }
        }
        last_changed = time;
    }
}
