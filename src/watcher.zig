const std = @import("std");
const events = @import("events.zig");
const logger = std.log.scoped(.watcher);

const File = struct {
    name: []const u8,
    time: i128,
};

var files: std.ArrayList(File) = undefined;
var allocator: std.mem.Allocator = undefined;
var thread: std.Thread = undefined;
var quit = false;

pub fn deinit() void {
    quit = true;
    defer files.deinit();
    thread.join();
}

pub fn init(alloc_pointer: std.mem.Allocator, path: [*:0]const u8) !void {
    quit = false;
    allocator = alloc_pointer;
    files = std.ArrayList(File).init(allocator);
    try files.ensureTotalCapacity(100);
    thread = try std.Thread.spawn(.{}, loop, .{path});
}

fn loop(path: [*:0]const u8) !void {
    const dir = try std.fs.openIterableDirAbsoluteZ(path, .{});
    _ = try build_files(dir);
    while (!quit) {
        std.time.sleep(std.time.ns_per_s);
        if (try build_files(dir)) {
            const event = .{
                .Reset = {},
            };
            events.post(event);
        }
    }
}

fn build_files(dir: std.fs.IterableDir) !bool {
    var ret = false;
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const file = try dir.dir.openFile(entry.name, .{});
                defer file.close();
                const metadata = try file.metadata();
                const time = metadata.modified();
                if (find(entry.name)) |f| {
                    if (time == f.time) continue;
                    f.* = .{
                        .name = entry.name,
                        .time = time,
                    };
                    logger.info("file changed: {s}", .{entry.name});
                    ret = true;
                } else {
                    ret = true;
                    try files.append(.{
                        .name = entry.name,
                        .time = time,
                    });
                    logger.info("new file: {s}", .{entry.name});
                }
            },
            .directory => {
                const directory = try dir.dir.openIterableDir(entry.name, .{});
                ret = try build_files(directory);
            },
            else => continue,
        }
    }
    return ret;
}

fn find(name: []const u8) ?*File {
    for (files.items) |*f| {
        if (std.mem.eql(u8, name, f.name)) return f;
    }
    return null;
}
