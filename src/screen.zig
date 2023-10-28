const std = @import("std");
const events = @import("events.zig");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
    @cInclude("SDL2/SDL_image.h");
});

pub var SDL_USER_EVENT: u32 = undefined;
var lock: std.Thread.Mutex = .{};
const logger = std.log.scoped(.screen);

const ScreenSize = struct {
    w: i32,
    h: i32,
    z: i32,
};

const Bitmask = struct {
    r: u32,
    g: u32,
    b: u32,
    a: u32,
};

const BITMASK = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN)
blk: {
    break :blk .{
        .r2 = 0xff000000,
        .g = 0x00ff0000,
        .b = 0x0000ff00,
        .a = 0x000000ff,
    };
} else blk: {
    break :blk .{
        .r = 0x000000ff,
        .g = 0x0000ff00,
        .b = 0x00ff0000,
        .a = 0xff000000,
    };
};

const Gui = struct {
    window: *c.SDL_Window = undefined,
    render: *c.SDL_Renderer = undefined,
    width: u16 = 256,
    height: u16 = 128,
    zoom: u16 = 4,
    WIDTH: u16 = 256,
    HEIGHT: u16 = 128,
    ZOOM: u16 = 4,
    x: c_int = 0,
    y: c_int = 0,
};

pub const Texture = struct {
    surface: *c.SDL_Surface,
    width: u16,
    height: u16,
    zoom: u16 = 1,
};

pub const Vertex = struct {
    pub const Position = struct {
        x: f32 = 0,
        y: f32 = 0,
    };
    pub const Color = struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 0,
    };
    position: Position = .{},
    color: Color = .{},
    tex_coord: Position = .{},
};

var textures: std.ArrayList(Texture) = undefined;

var windows: [2]Gui = undefined;
var current: usize = 0;

var font: *c.TTF_Font = undefined;
pub var quit = false;

pub fn define_geometry(texture: ?*const Texture, vertices: []const Vertex, indices: ?[]const usize) void {
    var sfba = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    var verts = allocator.alloc(c.SDL_Vertex, vertices.len) catch @panic("OOM!");
    defer allocator.free(verts);
    for (vertices, verts) |v, *w| {
        w.* = .{
            .position = .{
                .x = v.position.x,
                .y = v.position.y,
            },
            .color = .{
                .r = v.color.r,
                .g = v.color.g,
                .b = v.color.b,
                .a = v.color.a,
            },
            .tex_coord = .{
                .x = v.tex_coord.x,
                .y = v.tex_coord.y,
            },
        };
    }
    const txt = if (texture) |t| big: {
        break :big c.SDL_CreateTextureFromSurface(
            windows[current].render,
            t.surface,
        ) orelse blk: {
            logger.err("{s}: error: {s}", .{ "screen.define_geometry()", c.SDL_GetError() });
            break :blk null;
        };
    } else null;
    const ind = if (indices) |i| blk: {
        var list = allocator.alloc(c_int, i.len) catch @panic("OOM!");
        for (list, 0..) |*l, j| {
            l.* = @intCast(i[j]);
        }
        break :blk list;
    } else null;
    defer if (ind) |i| allocator.free(i);
    const len = if (indices) |i| i.len else 0;
    sdl_call(c.SDL_RenderGeometry(
        windows[current].render,
        txt,
        verts.ptr,
        @intCast(verts.len),
        if (ind) |i| i.ptr else null,
        @intCast(len),
    ), "screen.define_geometry()");
    if (txt) |t| c.SDL_DestroyTexture(t);
}

pub fn triangle(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) void {
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    const gui = windows[current];
    _ = c.SDL_GetRenderDrawColor(gui.render, &r, &g, &b, &a);
    const col = .{ .r = r, .g = g, .b = b, .a = a };
    const vertices = [3]Vertex{
        .{ .position = .{
            .x = ax,
            .y = ay,
        }, .color = col, .tex_coord = .{} },
        .{ .position = .{
            .x = bx,
            .y = by,
        }, .color = col, .tex_coord = .{} },
        .{ .position = .{
            .x = cx,
            .y = cy,
        }, .color = col, .tex_coord = .{} },
    };
    define_geometry(null, &vertices, null);
}

pub fn quad(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32, dx: f32, dy: f32) void {
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    const gui = windows[current];
    _ = c.SDL_GetRenderDrawColor(gui.render, &r, &g, &b, &a);
    const col = .{ .r = r, .g = g, .b = b, .a = a };
    const vertices = [4]Vertex{
        .{ .position = .{
            .x = ax,
            .y = ay,
        }, .color = col, .tex_coord = .{} },
        .{ .position = .{
            .x = bx,
            .y = by,
        }, .color = col, .tex_coord = .{} },
        .{ .position = .{
            .x = cx,
            .y = cy,
        }, .color = col, .tex_coord = .{} },
        .{ .position = .{
            .x = dx,
            .y = dy,
        }, .color = col, .tex_coord = .{} },
    };
    define_geometry(null, &vertices, &.{ 0, 2, 1, 0, 2, 3 });
}

pub fn new_texture(width: u16, height: u16) !*Texture {
    var sfba = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    const n: usize = @as(usize, width * windows[current].zoom) * @as(usize, height * windows[current].zoom) * 4;
    var pixels = allocator.alloc(u8, n) catch @panic("OOM!");
    defer allocator.free(pixels);
    sdl_call(c.SDL_RenderReadPixels(
        windows[current].render,
        &c.SDL_Rect{
            .x = windows[current].x,
            .y = windows[current].y,
            .w = width * windows[current].zoom,
            .h = height * windows[current].zoom,
        },
        0,
        pixels.ptr,
        width * windows[current].zoom * 4,
    ), "screen.new_texture()");
    const surf = c.SDL_CreateRGBSurface(
        0,
        width * windows[current].zoom,
        height * windows[current].zoom,
        32,
        BITMASK.r,
        BITMASK.g,
        BITMASK.b,
        BITMASK.a,
    ) orelse {
        logger.err("{s}: error: {s}", .{ "screen.new_texture()", c.SDL_GetError() });
        return error.Fail;
    };
    _ = c.SDL_memcpy(surf.*.pixels, pixels.ptr, @intCast(surf.*.h * surf.*.pitch));
    var texture = textures.addOne() catch @panic("OOM!");
    texture.* = .{
        .surface = surf,
        .width = width,
        .height = height,
        .zoom = windows[current].zoom,
    };
    return texture;
}

pub fn new_texture_from_file(filename: [:0]const u8) !*Texture {
    const surf = c.IMG_Load(filename.ptr) orelse {
        logger.err("{s}: error: {s}", .{ "screen.new_texture_from_file()", c.IMG_GetError() });
        return error.Fail;
    };
    var width: i32 = surf.*.w;
    var height: i32 = surf.*.h;
    var texture = textures.addOne() catch @panic("OOM!");
    texture.* = .{
        .surface = surf,
        .width = @intCast(width),
        .height = @intCast(height),
        .zoom = 1,
    };
    return texture;
}

pub fn render_texture(texture: *const Texture, x: i32, y: i32, zoom: f64) !void {
    const w: i32 = @intFromFloat(@as(f64, @floatFromInt(texture.width)) * zoom);
    const h: i32 = @intFromFloat(@as(f64, @floatFromInt(texture.height)) * zoom);
    const txt = c.SDL_CreateTextureFromSurface(
        windows[current].render,
        texture.surface,
    ) orelse {
        logger.err("{s}: error: {s}", .{ "screen.render_texture()", c.SDL_GetError() });
        return error.Fail;
    };
    sdl_call(c.SDL_SetTextureBlendMode(
        txt,
        c.SDL_BLENDMODE_BLEND,
    ), "screen.render_texture()");
    sdl_call(c.SDL_RenderCopy(
        windows[current].render,
        txt,
        null,
        &c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h },
    ), "screen.render_texture()");
    c.SDL_DestroyTexture(txt);
}

pub fn render_texture_extended(
    texture: *const Texture,
    x: i32,
    y: i32,
    zoom: f64,
    deg: f64,
    flip_h: bool,
    flip_v: bool,
) !void {
    const w: i32 = @intFromFloat(@as(f64, @floatFromInt(texture.width)) * zoom);
    const h: i32 = @intFromFloat(@as(f64, @floatFromInt(texture.height)) * zoom);
    var flip = if (flip_h) c.SDL_FLIP_HORIZONTAL else 0;
    flip = flip | if (flip_v) c.SDL_FLIP_VERTICAL else 0;
    const txt = c.SDL_CreateTextureFromSurface(
        windows[current].render,
        texture.surface,
    ) orelse {
        logger.err("{s}: error: {s}", .{ "screen.render_texture_extended()", c.SDL_GetError() });
        return error.Fail;
    };
    sdl_call(c.SDL_SetTextureBlendMode(
        txt,
        c.SDL_BLENDMODE_BLEND,
    ), "screen.render_texture_extended()");
    sdl_call(c.SDL_RenderCopyEx(
        windows[current].render,
        txt,
        null,
        &c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h },
        @floatCast(deg),
        null,
        @intCast(flip),
    ), "screen.render_texture_extended()");
}

pub fn show(target: usize) void {
    c.SDL_ShowWindow(windows[target].window);
}

pub fn set(new: usize) void {
    current = new;
}

pub fn move(x: c_int, y: c_int) void {
    windows[current].x = x;
    windows[current].y = y;
}

pub fn move_rel(x: c_int, y: c_int) void {
    var gui = &windows[current];
    gui.x += x;
    gui.y += y;
}

pub fn refresh() void {
    c.SDL_RenderPresent(windows[current].render);
}

pub fn clear() void {
    sdl_call(
        c.SDL_SetRenderDrawColor(windows[current].render, 0, 0, 0, 0),
        "screen.clear()",
    );
    sdl_call(
        c.SDL_RenderClear(windows[current].render),
        "screen.clear()",
    );
}

pub fn color(r: u8, g: u8, b: u8, a: u8) void {
    sdl_call(
        c.SDL_SetRenderDrawColor(windows[current].render, r, g, b, a),
        "screen.color()",
    );
}

pub fn pixel(x: c_int, y: c_int) void {
    sdl_call(
        c.SDL_RenderDrawPoint(windows[current].render, x, y),
        "screen.pixel()",
    );
}

pub fn pixel_rel() void {
    const gui = windows[current];
    sdl_call(
        c.SDL_RenderDrawPoint(gui.render, gui.x, gui.y),
        "screen.pixel_rel()",
    );
}

pub fn line(bx: c_int, by: c_int) void {
    const gui = windows[current];
    sdl_call(
        c.SDL_RenderDrawLine(gui.render, gui.x, gui.y, bx, by),
        "screen.line()",
    );
}

pub fn line_rel(bx: c_int, by: c_int) void {
    const gui = windows[current];
    sdl_call(
        c.SDL_RenderDrawLine(gui.render, gui.x, gui.y, gui.x + bx, gui.y + by),
        "screen.line()",
    );
}

pub fn curve(x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) void {
    const gui = windows[current];
    var points_buf: [1000]c.SDL_Point = undefined;
    var points: []c.SDL_Point = &points_buf;
    const x0: f64 = @floatFromInt(gui.x);
    const y0: f64 = @floatFromInt(gui.y);

    const step: f64 = 1.0 / 1000.0;

    for (0..1000) |i| {
        const u: f64 = step * @as(f64, @floatFromInt(i));
        const x: i32 = @intFromFloat((1 - u) * (1 - u) * (1 - u) * x0 + 3 * u * (1 - u) * (1 - u) * x1 + 3 * u * u * (1 - u) * x2 + u * u * u * x3);
        const y: i32 = @intFromFloat((1 - u) * (1 - u) * (1 - u) * y0 + 3 * u * (1 - u) * (1 - u) * y1 + 3 * u * u * (1 - u) * y2 + u * u * u * y3);

        points[i] = .{ .x = x, .y = y };
    }

    sdl_call(
        c.SDL_RenderDrawLines(gui.render, points.ptr, @intCast(points.len)),
        "screen.curve()",
    );
}

pub fn rect(w: i32, h: i32) void {
    const gui = windows[current];
    var r = c.SDL_Rect{ .x = gui.x, .y = gui.y, .w = w, .h = h };
    sdl_call(
        c.SDL_RenderDrawRect(gui.render, &r),
        "screen.rect()",
    );
}

pub fn rect_fill(w: i32, h: i32) void {
    const gui = windows[current];
    var r = c.SDL_Rect{ .x = gui.x, .y = gui.y, .w = w, .h = h };
    sdl_call(
        c.SDL_RenderFillRect(gui.render, &r),
        "screen.rect_fill()",
    );
}

pub fn text(words: [:0]const u8) void {
    if (words.len == 0) return;
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    const gui = windows[current];
    _ = c.SDL_GetRenderDrawColor(gui.render, &r, &g, &b, &a);
    var col = c.SDL_Color{ .r = r, .g = g, .b = b, .a = a };
    var text_surf = c.TTF_RenderText_Solid(font, words, col);
    var texture = c.SDL_CreateTextureFromSurface(gui.render, text_surf);
    const rectangle = c.SDL_Rect{ .x = gui.x, .y = gui.y, .w = text_surf.*.w, .h = text_surf.*.h };
    sdl_call(
        c.SDL_RenderCopy(gui.render, texture, null, &rectangle),
        "screen.text()",
    );
    c.SDL_DestroyTexture(texture);
    c.SDL_FreeSurface(text_surf);
}

pub fn text_center(words: [:0]const u8) void {
    if (words.len == 0) return;
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    const gui = windows[current];
    _ = c.SDL_GetRenderDrawColor(gui.render, &r, &g, &b, &a);
    var col = c.SDL_Color{ .r = r, .g = g, .b = b, .a = a };
    var text_surf = c.TTF_RenderText_Solid(font, words, col);
    var texture = c.SDL_CreateTextureFromSurface(gui.render, text_surf);
    const radius = @divTrunc(text_surf.*.w, 2);
    const rectangle = c.SDL_Rect{ .x = gui.x - radius, .y = gui.y, .w = text_surf.*.w, .h = text_surf.*.h };
    sdl_call(
        c.SDL_RenderCopy(gui.render, texture, null, &rectangle),
        "screen.text()",
    );
    c.SDL_DestroyTexture(texture);
    c.SDL_FreeSurface(text_surf);
}

pub fn text_right(words: [:0]const u8) void {
    if (words.len == 0) return;
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    const gui = windows[current];
    _ = c.SDL_GetRenderDrawColor(gui.render, &r, &g, &b, &a);
    var col = c.SDL_Color{ .r = r, .g = g, .b = b, .a = a };
    var text_surf = c.TTF_RenderText_Solid(font, words, col);
    var texture = c.SDL_CreateTextureFromSurface(gui.render, text_surf);
    const width = text_surf.*.w;
    const rectangle = c.SDL_Rect{ .x = gui.x - width, .y = gui.y, .w = width, .h = text_surf.*.h };
    sdl_call(
        c.SDL_RenderCopy(gui.render, texture, null, &rectangle),
        "screen.text()",
    );
    c.SDL_DestroyTexture(texture);
    c.SDL_FreeSurface(text_surf);
}

pub fn arc(radius: i32, theta_1: f64, theta_2: f64) void {
    var sfba = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    std.debug.assert(0 <= theta_1);
    std.debug.assert(theta_1 <= theta_2);
    std.debug.assert(theta_2 <= std.math.tau);
    const angle_length = (theta_2 - theta_1) * @as(f64, @floatFromInt(radius));
    const perimeter_estimate: usize = 2 * @as(usize, @intFromFloat(angle_length)) + 9;
    const gui = windows[current];
    var points = std.ArrayList(c.SDL_Point).initCapacity(allocator, perimeter_estimate) catch @panic("OOM!");
    defer points.deinit();
    var offset_x: i32 = 0;
    var offset_y: i32 = radius;
    var d = radius - 1;
    while (offset_y >= offset_x) {
        const pts = [8]c.SDL_Point{ .{
            .x = gui.x + offset_x,
            .y = gui.y + offset_y,
        }, .{
            .x = gui.x + offset_y,
            .y = gui.y + offset_x,
        }, .{
            .x = gui.x - offset_x,
            .y = gui.y + offset_y,
        }, .{
            .x = gui.x - offset_y,
            .y = gui.y + offset_x,
        }, .{
            .x = gui.x + offset_x,
            .y = gui.y - offset_y,
        }, .{
            .x = gui.x + offset_y,
            .y = gui.y - offset_x,
        }, .{
            .x = gui.x - offset_x,
            .y = gui.y - offset_y,
        }, .{
            .x = gui.x - offset_y,
            .y = gui.y - offset_x,
        } };
        for (pts) |pt| {
            const num: f64 = @floatFromInt(pt.x);
            const denom: f64 = @floatFromInt(pt.y);
            const theta = std.math.atan(num / denom);
            if (theta_1 <= theta and theta <= theta_2) {
                points.appendAssumeCapacity(pt);
            }
        }
        if (d >= 2 * offset_x) {
            d -= 2 * offset_x + 1;
            offset_x += 1;
        } else if (d < 2 * (radius - offset_y)) {
            d += 2 * offset_y - 1;
            offset_y -= 1;
        } else {
            d += 2 * (offset_y - offset_x - 1);
            offset_y -= 1;
            offset_x += 1;
        }
    }
    const slice = points.items;
    sdl_call(
        c.SDL_RenderDrawPoints(gui.render, slice.ptr, @intCast(slice.len)),
        "screen.arc()",
    );
}

pub fn circle(radius: i32) void {
    var sfba = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    const perimeter_estimate: usize = @intFromFloat(2 * std.math.tau * @as(f64, @floatFromInt(radius)) + 8);
    const gui = windows[current];
    var points = std.ArrayList(c.SDL_Point).initCapacity(allocator, perimeter_estimate) catch @panic("OOM!");
    defer points.deinit();
    var offset_x: i32 = 0;
    var offset_y: i32 = radius;
    var d = radius - 1;
    while (offset_y >= offset_x) {
        const pts = [8]c.SDL_Point{ .{
            .x = gui.x + offset_x,
            .y = gui.y + offset_y,
        }, .{
            .x = gui.x + offset_y,
            .y = gui.y + offset_x,
        }, .{
            .x = gui.x - offset_x,
            .y = gui.y + offset_y,
        }, .{
            .x = gui.x - offset_y,
            .y = gui.y + offset_x,
        }, .{
            .x = gui.x + offset_x,
            .y = gui.y - offset_y,
        }, .{
            .x = gui.x + offset_y,
            .y = gui.y - offset_x,
        }, .{
            .x = gui.x - offset_x,
            .y = gui.y - offset_y,
        }, .{
            .x = gui.x - offset_y,
            .y = gui.y - offset_x,
        } };
        points.appendSliceAssumeCapacity(&pts);
        if (d >= 2 * offset_x) {
            d -= 2 * offset_x + 1;
            offset_x += 1;
        } else if (d < 2 * (radius - offset_y)) {
            d += 2 * offset_y - 1;
            offset_y -= 1;
        } else {
            d += 2 * (offset_y - offset_x - 1);
            offset_y -= 1;
            offset_x += 1;
        }
    }
    const slice = points.items;
    sdl_call(
        c.SDL_RenderDrawPoints(gui.render, slice.ptr, @intCast(slice.len)),
        "screen.circle()",
    );
}

pub fn circle_fill(radius: i32) void {
    var sfba = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    const r = if (radius < 0) -radius else radius;
    const rsquared = radius * radius;
    const gui = windows[current];
    var points = std.ArrayList(c.SDL_Point).initCapacity(allocator, @intCast(4 * rsquared + 2)) catch @panic("OOM!");
    defer points.deinit();
    var i = -r;
    while (i <= r) : (i += 1) {
        var j = -r;
        while (j <= r) : (j += 1) {
            if (i * i + j * j < rsquared) points.appendAssumeCapacity(.{
                .x = gui.x + i,
                .y = gui.y + j,
            });
        }
    }
    const slice = points.items;
    sdl_call(
        c.SDL_RenderDrawPoints(gui.render, slice.ptr, @intCast(slice.len)),
        "screen.circle_fill()",
    );
}

const Size = struct {
    w: i32,
    h: i32,
};

pub fn get_text_size(str: [*:0]const u8) Size {
    var w: i32 = undefined;
    var h: i32 = undefined;
    sdl_call(c.TTF_SizeText(font, str, &w, &h), "screen.get_text_size()");
    return .{ .w = w, .h = h };
}

pub fn get_size() Size {
    return .{
        .w = windows[current].width,
        .h = windows[current].height,
    };
}

pub fn set_size(width: i32, height: i32, zoom: i32) void {
    var size = std.heap.raw_c_allocator.create(ScreenSize) catch @panic("OOM!");
    size.* = .{
        .w = width,
        .h = height,
        .z = zoom,
    };
    var event: c.SDL_Event = undefined;
    event = std.mem.zeroes(c.SDL_Event);
    event.type = SDL_USER_EVENT;
    event.user.code = 0;
    event.user.data1 = size;
    sdl_call(c.SDL_PushEvent(&event), "screen.set_size");
}

fn set_size_inner(width: i32, height: i32, zoom: i32) void {
    const gui = &windows[current];
    gui.WIDTH = @intCast(width);
    gui.HEIGHT = @intCast(height);
    gui.ZOOM = @intCast(zoom);
    c.SDL_SetWindowSize(gui.window, width * zoom, height * zoom);
    c.SDL_SetWindowMinimumSize(gui.window, width, height);
    window_rect(gui);
}

pub fn set_fullscreen(is_fullscreen: bool) void {
    var fullscreen = allocator.create(bool) catch @panic("OOM!");
    fullscreen.* = is_fullscreen;
    var event: c.SDL_Event = undefined;
    event = std.mem.zeroes(c.SDL_Event);
    event.type = SDL_USER_EVENT;
    event.user.code = 1;
    event.user.data1 = fullscreen;
    sdl_call(c.SDL_PushEvent(&event), "screen.set_fullscreen");
}

pub fn set_fullscreen_inner(is_fullscreen: bool) void {
    const gui = windows[current];
    if (is_fullscreen) {
        sdl_call(
            c.SDL_SetWindowFullscreen(gui.window, c.SDL_WINDOW_FULLSCREEN_DESKTOP),
            "screen.set_fullscreen()",
        );
        window_rect(&windows[current]);
    } else {
        sdl_call(
            c.SDL_SetWindowFullscreen(gui.window, 0),
            "screen.set_fullscreen()",
        );
        set_size(gui.WIDTH, gui.HEIGHT, gui.ZOOM);
    }
    const event = .{
        .Screen_Resized = .{
            .w = gui.width,
            .h = gui.height,
            .window = current,
        },
    };
    events.post(event);
}

pub fn init(width: u16, height: u16, resources: []const u8) !void {
    quit = false;
    var sfba = std.heap.stackFallback(1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        logger.err("screen.init(): {s}", .{c.SDL_GetError()});
        return error.Fail;
    }

    if (c.TTF_Init() < 0) {
        logger.err("screen.init(): {s}", .{c.TTF_GetError()});
        return error.Fail;
    }

    if (c.IMG_Init(c.IMG_INIT_JPG | c.IMG_INIT_PNG) == 0) {
        logger.err("screen.init(): {s}", .{c.IMG_GetError()});
        return error.Fail;
    }

    const filename = try std.fmt.allocPrintZ(allocator, "{s}/04b03.ttf", .{resources});
    defer allocator.free(filename);
    var f = c.TTF_OpenFont(filename, 8);
    font = f orelse {
        logger.err("screen.init(): {s}", .{c.TTF_GetError()});
        return error.Fail;
    };

    for (0..2) |i| {
        var w = c.SDL_CreateWindow(
            if (i == 0) "seamstress" else "seamstress_params",
            @intCast(i * width * 4),
            @intCast(i * height * 4),
            width * 4,
            height * 4,
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        );
        var window = w orelse {
            logger.err("screen.init(): {s}", .{c.SDL_GetError()});
            return error.Fail;
        };
        var r = c.SDL_CreateRenderer(window, 0, 0);
        var render = r orelse {
            logger.err("screen.init(): {s}", .{c.SDL_GetError()});
            return error.Fail;
        };
        c.SDL_SetWindowMinimumSize(window, width, height);
        windows[i] = .{
            .window = window,
            .render = render,
            .zoom = 4,
            .WIDTH = width,
            .HEIGHT = height,
            .ZOOM = 4,
        };
        set(i);
        window_rect(&windows[current]);
        clear();
        refresh();
        sdl_call(
            c.SDL_SetRenderDrawBlendMode(windows[current].render, c.SDL_BLENDMODE_BLEND),
            "screen.init()",
        );
    }
    set(0);
    textures = std.ArrayList(Texture).init(std.heap.raw_c_allocator);
    SDL_USER_EVENT = c.SDL_RegisterEvents(1);
    if (SDL_USER_EVENT == std.math.maxInt(u32)) {
        return error.Fail;
    }
    c.SDL_RaiseWindow(windows[0].window);
}

fn window_rect(gui: *Gui) void {
    lock.lock();
    defer lock.unlock();
    var xsize: i32 = undefined;
    var ysize: i32 = undefined;
    var xzoom: u16 = 1;
    var yzoom: u16 = 1;
    const oldzoom = gui.zoom;
    c.SDL_GetWindowSize(gui.window, &xsize, &ysize);
    while ((1 + xzoom) * gui.WIDTH <= xsize) : (xzoom += 1) {}
    while ((1 + yzoom) * gui.HEIGHT <= ysize) : (yzoom += 1) {}
    gui.zoom = if (xzoom < yzoom) xzoom else yzoom;
    const uxsize: u16 = @intCast(xsize);
    const uysize: u16 = @intCast(ysize);
    gui.width = @divFloor(uxsize, gui.zoom);
    gui.height = @divFloor(uysize, gui.zoom);
    gui.x = @divFloor(gui.x * oldzoom, gui.zoom);
    gui.y = @divFloor(gui.y * oldzoom, gui.zoom);
    sdl_call(c.SDL_RenderSetScale(
        gui.render,
        @floatFromInt(gui.zoom),
        @floatFromInt(gui.zoom),
    ), "window_rect()");
}

pub fn check() void {
    var ev: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&ev) != 0) {
        if (ev.type == SDL_USER_EVENT) {
            switch (ev.user.code) {
                0 => {
                    const size: *ScreenSize = @ptrCast(@alignCast(ev.user.data1));
                    set_size_inner(size.w, size.h, size.z);
                    std.heap.raw_c_allocator.destroy(size);
                },
                1 => {
                    const fullscreen: *bool = @ptrCast(@alignCast(ev.user.data1));
                    set_fullscreen_inner(fullscreen.*);
                    std.heap.raw_c_allocator.destroy(fullscreen);
                },
                else => {},
            }
            continue;
        }
        switch (ev.type) {
            c.SDL_KEYUP, c.SDL_KEYDOWN => {
                const event = .{
                    .Screen_Key = .{
                        .sym = ev.key.keysym.sym,
                        .mod = ev.key.keysym.mod,
                        .repeat = ev.key.repeat > 0,
                        .state = ev.key.state == c.SDL_PRESSED,
                        .window = ev.key.windowID,
                    },
                };
                events.post(event);
            },
            c.SDL_QUIT => {
                events.post(.{ .Quit = {} });
                quit = true;
            },
            c.SDL_MOUSEWHEEL => {
                const flipped = ev.wheel.direction == c.SDL_MOUSEWHEEL_FLIPPED;
                const x: f64 = if (flipped) -ev.wheel.preciseX else ev.wheel.preciseX;
                const y: f64 = if (flipped) -ev.wheel.preciseY else ev.wheel.preciseY;
                events.post(.{
                    .Screen_Mouse_Wheel = .{
                        .x = x,
                        .y = y,
                        .window = ev.wheel.windowID,
                    },
                });
            },
            c.SDL_MOUSEMOTION => {
                const zoom: f64 = @floatFromInt(windows[ev.button.windowID - 1].zoom);
                const x: f64 = @floatFromInt(ev.button.x);
                const y: f64 = @floatFromInt(ev.button.y);
                const event = .{
                    .Screen_Mouse_Motion = .{
                        .x = x / zoom,
                        .y = y / zoom,
                        .window = ev.motion.windowID,
                    },
                };
                events.post(event);
            },
            c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => {
                const zoom: f64 = @floatFromInt(windows[ev.button.windowID - 1].zoom);
                const x: f64 = @floatFromInt(ev.button.x);
                const y: f64 = @floatFromInt(ev.button.y);
                const event = .{
                    .Screen_Mouse_Click = .{
                        .state = ev.button.state == c.SDL_PRESSED,
                        .x = x / zoom,
                        .y = y / zoom,
                        .button = ev.button.button,
                        .window = ev.button.windowID,
                    },
                };
                events.post(event);
            },
            c.SDL_WINDOWEVENT => {
                switch (ev.window.event) {
                    c.SDL_WINDOWEVENT_CLOSE => {
                        if (ev.window.windowID == 1) {
                            events.post(.{ .Quit = {} });
                            quit = true;
                        } else {
                            c.SDL_HideWindow(windows[ev.window.windowID - 1].window);
                        }
                    },
                    c.SDL_WINDOW_SHOWN, c.SDL_WINDOWEVENT_DISPLAY_CHANGED, c.SDL_WINDOWEVENT_EXPOSED => {
                        events.post(.{
                            .Redraw = {},
                        });
                    },
                    c.SDL_WINDOWEVENT_RESIZED, c.SDL_WINDOWEVENT_MAXIMIZED, c.SDL_WINDOWEVENT_RESTORED => {
                        const old = current;
                        const id = ev.window.windowID - 1;
                        set(id);
                        window_rect(&windows[current]);
                        refresh();
                        set(old);
                        const event = .{
                            .Screen_Resized = .{
                                .w = windows[id].width,
                                .h = windows[id].height,
                                .window = id + 1,
                            },
                        };
                        events.post(event);
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
}

pub fn deinit() void {
    for (textures.items) |texture| {
        c.SDL_FreeSurface(texture.surface);
    }
    textures.deinit();
    c.TTF_CloseFont(font);
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        c.SDL_DestroyRenderer(windows[i].render);
        c.SDL_DestroyWindow(windows[i].window);
    }
    c.IMG_Quit();
    c.TTF_Quit();
    c.SDL_Quit();
}

pub fn loop() void {
    while (!quit) {
        check();
        std.time.sleep(std.time.ns_per_ms);
    }
}

fn sdl_call(err: c_int, name: []const u8) void {
    if (err < 0) {
        logger.err("{s}: error: {s}", .{ name, c.SDL_GetError() });
    }
}
