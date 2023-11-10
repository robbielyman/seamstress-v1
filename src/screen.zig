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

const Queue = std.fifo.LinearFifo(ScreenEvent, .{ .Static = 5000 });
var queue: Queue = undefined;

pub fn post(event: ScreenEvent) void {
    queue.writeItem(event) catch @panic("too many screen events!\n");
    inner.add_event();
}

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
        const Alignment = enum { Left, Right, Center };
        words: [:0]const u8,
        allocator: std.mem.Allocator,
        alignment: Alignment,
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
};

pub fn process() !void {
    const ev = queue.readItem();
    if (ev) |event| try handle(event);
}

fn handle(event: ScreenEvent) !void {
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
        .NewTexture => |e| try inner.new_texture(e.width, e.height),
        .NewTextureFromFile => |e| try inner.new_texture_from_file(e.filename),
        .Pixel => |e| inner.pixel(e.x, e.y),
        .PixelRel => inner.pixel_rel(),
        .Rect => |e| {
            if (e.fill) inner.rect_fill(e.w, e.h) else inner.rect(e.w, e.h);
        },
        .Refresh => inner.refresh(),
        .RenderTexture => |e| try inner.render_texture_extended(e.texture, e.x, e.y, e.zoom, e.deg, e.flip_h, e.flip_v),
        .Set => |e| inner.set(e),
        .Show => |e| inner.show(e),
        .SetSize => |e| inner.set_size(e.w, e.h, e.z),
        .SetPosition => |e| inner.set_position(e.x, e.y),
        .Text => |e| {
            switch (e.alignment) {
                .Left => inner.text(e.words),
                .Right => inner.text_right(e.words),
                .Center => inner.text_center(e.words),
            }
        },
    }
    free(event);
}

fn free(event: ScreenEvent) void {
    switch (event) {
        .Text => |e| e.allocator.free(e.words),
        .NewTextureFromFile => |e| e.allocator.free(e.filename),
        .DefineGeometry => |e| {
            e.allocator.free(e.vertices);
            if (e.indices) |i| e.allocator.free(i);
        },
        else => {},
    }
}

pub const Size = struct {
    w: i32,
    h: i32,
};

pub fn get_text_size(str: [*:0]const u8) Size {
    return inner.get_text_size(str);
}

pub fn get_size() Size {
    return inner.get_size();
}

pub fn get_texture_size(texture: usize) !Size {
    if (texture > inner.textures.items.len) return error.Fail;
    return .{
        .w = inner.textures.items[texture].width,
        .h = inner.textures.items[texture].height,
    };
}

pub fn next_texture_idx() usize {
    return inner.textures.items.len;
}

pub fn init(width: u16, height: u16, resources: []const u8) !void {
    quit = false;
    try inner.init(width, height, resources);
}

pub fn deinit() void {
    inner.deinit();
}

pub fn loop() void {
    inner.loop();
}
