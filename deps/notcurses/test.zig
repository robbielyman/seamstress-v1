const nc = @import("main.zig");
const std = @import("std");

fn resize(_: nc.Plane) i32 {
    std.debug.print("resized!\n", .{});
    return 0;
}

pub fn main() !void {
    var notcurses = try nc.Notcurses.coreInit(.{
        .flags = .{
            .drain_input = true,
        },
    }, nc.c.__stdoutp);
    defer notcurses.stop() catch {};

    try notcurses.enterAlternateScreen();

    const stdplane = try notcurses.stdplane();

    var palette = notcurses.newPalette();
    defer palette.free();
    palette.chans[0] = .{
        .red = 255,
        .green = 200,
        .blue = 223,
        .non_default = true,
        .palette = true,
    };
    try notcurses.usePalette(palette);

    const y, const x = stdplane.dimensions();
    
    var output = try nc.Plane.create(stdplane, .{
        .cols = x,
        .rows = y - 3,
        .flags = .{.vertical_scroll = true },
        .resize_cb = nc.wrap(resizeOutput),
        .userdata = null,
        .x = 0,
        .y = 0,
        .margin_b = 0,
        .margin_r = 0,
        .name = "output",
    });
    defer output.destroy() catch {};
    var input = try nc.Plane.create(stdplane, .{
        .cols = x,
        .rows = 3,
        .flags = .{ .fixed = true },
        .margin_b = 0,
        .margin_r = 0,
        .y = @intCast(y -| 3),
        .x = 0,
        .userdata = null,
        .resize_cb = nc.wrap(resizeInput),
        .name = "input",
    });
    defer input.destroy() catch {};
    var reader_plane = try nc.Plane.create(input, .{
        .cols = x - 2,
        .rows = 1,
        .flags = .{ .fixed = true },
        .margin_b = 0,
        .margin_r = 0,
        .y = 1,
        .x = 1,
        .userdata = null,
        .resize_cb = nc.c.ncplane_resize_realign,
        .name = "reader_plane",
    });
    defer reader_plane.destroy() catch {};

    var box = try input.loadBoxPreset(.{}, .{
        .bg = palette.chans[0],
        .fg = .{},
    }, .double);
    try input.perimeter(&box, .{});

    var cell: nc.Cell = .{};
    _ = try reader_plane.loadCell(&cell, "💖");
    try reader_plane.setBaseCell(&cell);
    
    try notcurses.render();
    stdplane.releaseBox(&box);

    std.time.sleep(std.time.ns_per_s * 2);
}

fn resizeOutput(plane: nc.Plane) !void {
    const parent = try plane.parent();
    const y, const x = parent.dimensions();
    try plane.resizeSimple(@intCast(y -| 3), x);
    try plane.moveYx(0, 0);
}

fn resizeInput(plane: nc.Plane) !void {    
    const parent = try plane.parent();
    const y, const x = parent.dimensions();
    try plane.resizeSimple(3, x);
    try plane.moveYx(@intCast(y - 3), 0);
}
