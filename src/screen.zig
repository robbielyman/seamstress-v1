const std = @import("std");
const inner = @import("screen_inner_SDL.zig");

pub const Vertex = extern struct {
    pub const Position = extern struct {
        x: f32 = 0,
        y: f32 = 0,
    };
    pub const Color = extern struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 0,
    };
    position: Position = .{},
    color: Color = .{},
    tex_coord: Position = .{},
};
pub var quit = false;

const Queue = std.fifo.LinearFifo(ScreenEvent, .{ .Dynamic = {} });
var queue: Queue = undefined;
var arena: std.heap.ArenaAllocator = undefined;

pub var response: ?ScreenResponse = null;
const logger = std.log.scoped(.screen);

pub var lock: std.Thread.Mutex = .{};
pub var cond: std.Thread.Condition = .{};

pub fn post(event: ScreenEvent) void {
    lock.lock();
    defer lock.unlock();
    queue.writeItem(event) catch @panic("OOM!");
}

pub const Alignment = enum { Left, Right, Center };

pub const ScreenResponse = union(enum) {
    TextSize: Size,
    TextureSize: Size,
    Texture: usize,
};

pub const ScreenEvent = union(enum) {
    DefineGeometry: struct {
        texture: ?usize,
        vertices: []const Vertex,
        indices: ?[]const usize,
        allocator: std.mem.Allocator,
    },
    NewTexture: struct {
        width: u16,
        height: u16,
    },
    NewTextureFromFile: struct {
        filename: [:0]const u8,
        allocator: std.mem.Allocator,
    },
    RenderTexture: struct {
        texture: usize,
        x: i32,
        y: i32,
        zoom: f64,
        deg: f64 = 0,
        flip_h: bool = false,
        flip_v: bool = false,
    },
    Show: usize,
    Set: usize,
    Move: struct {
        x: c_int,
        y: c_int,
        rel: bool,
    },
    Refresh: void,
    Clear: void,
    Color: Vertex.Color,
    Pixel: struct {
        x: c_int,
        y: c_int,
    },
    PixelRel: void,
    Line: struct {
        x: c_int,
        y: c_int,
        rel: bool,
    },
    Curve: struct {
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
        x3: f64,
        y3: f64,
    },
    Rect: struct {
        w: i32,
        h: i32,
        fill: bool,
    },
    Text: struct {
        words: [:0]const u8,
        alignment: Alignment,
        allocator: std.mem.Allocator,
    },
    text_size: struct {
        words: [:0]const u8,
        allocator: std.mem.Allocator,
    },
    TextureSize: struct {
        texture: usize,
    },
    Arc: struct {
        radius: i32,
        theta_1: f64,
        theta_2: f64,
    },
    Circle: struct {
        radius: i32,
        fill: bool,
    },
    SetSize: struct {
        w: i32,
        h: i32,
        z: i32,
    },
    Fullscreen: bool,
    SetPosition: struct {
        x: i32,
        y: i32,
    },
    nuttin: void,
};

pub fn process() void {
    var done = false;
    while (!done and !quit) {
        const ev = blk: {
            lock.lock();
            defer lock.unlock();
            break :blk queue.readItem();
        };
        if (ev) |event| handle(event) else done = true;
    }
    if (quit) cond.signal();
}

fn handle(event: ScreenEvent) void {
    switch (event) {
        .Arc => |e| inner.arc(e.radius, e.theta_1, e.theta_2),
        .Circle => |e| {
            if (e.fill) inner.circle_fill(e.radius) else inner.circle(e.radius);
        },
        .Clear => inner.clear(),
        .Color => |e| inner.color(e.r, e.g, e.b, e.a),
        .Curve => |e| inner.curve(e.x1, e.y1, e.x2, e.y2, e.x3, e.y3),
        .DefineGeometry => |e| inner.define_geometry(e.texture, e.vertices, e.indices),
        .Fullscreen => |e| inner.set_fullscreen(e),
        .Line => |e| {
            if (e.rel) inner.line_rel(e.x, e.y) else inner.line(e.x, e.y);
        },
        .Move => |e| {
            if (e.rel) inner.move_rel(e.x, e.y) else inner.move(e.x, e.y);
        },
        .NewTexture => |e| {
            if (response) |r|
                logger.err("clobbering screen response of type {s}!", .{@tagName(r)});
            const texture: ?usize = inner.new_texture(e.width, e.height) catch null;
            if (texture) |t| {
                const resp: ScreenResponse = .{ .Texture = t };
                response = resp;
            } else response = null;
            cond.signal();
        },
        .NewTextureFromFile => |e| {
            if (response) |r|
                logger.err("clobbering screen response of type {s}!", .{@tagName(r)});
            const texture: ?usize = inner.new_texture_from_file(e.filename) catch null;
            if (texture) |t| {
                const resp: ScreenResponse = .{ .Texture = t };
                response = resp;
            } else response = null;
            cond.signal();
        },
        .Pixel => |e| inner.pixel(e.x, e.y),
        .PixelRel => inner.pixel_rel(),
        .Rect => |e| {
            if (e.fill) inner.rect_fill(e.w, e.h) else inner.rect(e.w, e.h);
        },
        .Refresh => inner.refresh(),
        .RenderTexture => |e| inner.render_texture_extended(e.texture, e.x, e.y, e.zoom, e.deg, e.flip_h, e.flip_v),
        .Set => |e| inner.set(e),
        .Show => |e| inner.show(e),
        .SetSize => |e| inner.set_size(e.w, e.h, e.z),
        .SetPosition => |e| inner.set_position(e.x, e.y),
        .Text => |e| inner.text(e.words, e.alignment, e.allocator),
        .text_size => |e| {
            if (response) |r| {
                logger.err("clobbering screen response of type {s}!", .{@tagName(r)});
            }
            const res: ScreenResponse = .{
                .TextSize = inner.getTextSize(e.words),
            };
            response = res;
            cond.signal();
        },
        .TextureSize => |e| {
            if (response) |r|
                logger.err("clobbering screen response of type {s}!", .{@tagName(r)});
            const size: ?Size = if (e.texture < inner.textures.items.len) blk: {
                break :blk .{
                    .w = inner.textures.items[e.texture].width,
                    .h = inner.textures.items[e.texture].height,
                };
            } else null;
            if (size) |s| {
                const resp: ScreenResponse = .{ .TextureSize = s };
                response = resp;
            } else response = null;
            cond.signal();
        },
        else => {},
    }
    free(event);
}

fn free(event: ScreenEvent) void {
    switch (event) {
        .NewTextureFromFile => |e| e.allocator.free(e.filename),
        .DefineGeometry => |e| {
            e.allocator.free(e.vertices);
            if (e.indices) |i| e.allocator.free(i);
        },
        .text_size => |e| e.allocator.free(e.words),
        else => {},
    }
}

pub const Size = struct {
    w: i32,
    h: i32,
};

pub fn init(width: u16, height: u16, resources: []const u8) !void {
    arena = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    quit = false;
    try inner.init(width, height, resources);
    queue = Queue.init(arena.allocator());
}

pub fn deinit() void {
    inner.deinit();
    queue.deinit();
    response = null;
    arena.deinit();
}

pub fn loop() void {
    inner.loop();
}
