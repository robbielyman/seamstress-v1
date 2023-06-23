const std = @import("std");
const events = @import("events.zig");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
    @cInclude("SDL2/SDL_error.h");
    @cInclude("SDL2/SDL_render.h");
    @cInclude("SDL2/SDL_surface.h");
    @cInclude("SDL2/SDL_video.h");
});

var WIDTH: u16 = 256;
var HEIGHT: u16 = 128;
var ZOOM: u16 = 4;
const logger = std.log.scoped(.screen);

const Gui = struct {
    window: *c.SDL_Window = undefined,
    render: *c.SDL_Renderer = undefined,
    width: u16 = 256,
    height: u16 = 128,
    zoom: u16 = 4,
};

var windows: [2]Gui = undefined;
var current: usize = 0;

var font: *c.TTF_Font = undefined;
var thread: std.Thread = undefined;
var quit = false;

pub fn show(target: usize) void {
    c.SDL_ShowWindow(windows[target].window);
}

pub fn set(new: usize) void {
    current = new;
}

pub fn refresh() void {
    c.SDL_RenderPresent(windows[current].render);
}

pub fn clear() void {
    sdl_call(
        c.SDL_SetRenderDrawColor(windows[current].render, 0, 0, 0, 255),
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

pub fn pixel(x: i32, y: i32) void {
    sdl_call(
        c.SDL_RenderDrawPoint(windows[current].render, x, y),
        "screen.pixel()",
    );
}

pub fn line(ax: i32, ay: i32, bx: i32, by: i32) void {
    sdl_call(
        c.SDL_RenderDrawLine(windows[current].render, ax, ay, bx, by),
        "screen.line()",
    );
}

pub fn rect(x: i32, y: i32, w: i32, h: i32) void {
    var r = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
    sdl_call(
        c.SDL_RenderDrawRect(windows[current].render, &r),
        "screen.rect()",
    );
}

pub fn rect_fill(x: i32, y: i32, w: i32, h: i32) void {
    var r = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
    sdl_call(
        c.SDL_RenderFillRect(windows[current].render, &r),
        "screen.rect_fill()",
    );
}

pub fn text(x: i32, y: i32, words: [:0]const u8) void {
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    _ = c.SDL_GetRenderDrawColor(windows[current].render, &r, &g, &b, &a);
    var col = c.SDL_Color{ .r = r, .g = g, .b = b, .a = a };
    var text_surf = c.TTF_RenderText_Solid(font, words, col);
    var texture = c.SDL_CreateTextureFromSurface(windows[current].render, text_surf);
    const rectangle = c.SDL_Rect{ .x = x, .y = y, .w = text_surf.*.w, .h = text_surf.*.h };
    sdl_call(
        c.SDL_RenderCopy(windows[current].render, texture, null, &rectangle),
        "screen.text()",
    );
    c.SDL_DestroyTexture(texture);
    c.SDL_FreeSurface(text_surf);
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

pub fn init(width: u16, height: u16) !void {
    HEIGHT = height;
    WIDTH = width;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        logger.err("screen.init(): {s}\n", .{c.SDL_GetError()});
        return error.Fail;
    }

    if (c.TTF_Init() < 0) {
        logger.err("screen.init(): {s}\n", .{c.TTF_GetError()});
        return error.Fail;
    }

    var f = c.TTF_OpenFont("/usr/local/share/seamstress/resources/04b03.ttf", 8);
    font = f orelse {
        logger.err("screen.init(): {s}\n", .{c.TTF_GetError()});
        return error.Fail;
    };

    var w = c.SDL_CreateWindow(
        "seamstress",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        WIDTH * ZOOM,
        HEIGHT * ZOOM,
        c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
    );
    var window = w orelse {
        logger.err("screen.init(): {s}\n", .{c.SDL_GetError()});
        return error.Fail;
    };

    var r = c.SDL_CreateRenderer(window, 0, 0);
    var render = r orelse {
        logger.err("screen.init(): {s}\n", .{c.SDL_GetError()});
        return error.Fail;
    };

    c.SDL_SetWindowMinimumSize(window, WIDTH, HEIGHT);
    windows[0] = .{
        .window = window,
        .render = render,
        .zoom = ZOOM,
    };
    window_rect(&windows[current]);
    set(0);
    clear();
    refresh();

    w = c.SDL_CreateWindow(
        "seamstress params",
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        WIDTH * ZOOM,
        HEIGHT * ZOOM,
        c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
    );
    window = w orelse {
        logger.err("screen.init(): {s}\n", .{c.SDL_GetError()});
        return error.Fail;
    };
    r = c.SDL_CreateRenderer(window, 0, 0);
    render = r orelse {
        logger.err("screen.init(): {s}\n", .{c.SDL_GetError()});
        return error.Fail;
    };
    windows[1] = .{
        .window = window,
        .render = render,
        .zoom = ZOOM,
    };
    window_rect(&windows[current]);
    set(1);
    clear();
    refresh();
    set(0);
    thread = try std.Thread.spawn(.{}, loop, .{});
}

fn window_rect(gui: *Gui) void {
    var xsize: i32 = undefined;
    var ysize: i32 = undefined;
    var xzoom: u16 = 1;
    var yzoom: u16 = 1;
    c.SDL_GetWindowSize(gui.window, &xsize, &ysize);
    while ((1 + xzoom) * WIDTH <= xsize) : (xzoom += 1) {}
    while ((1 + yzoom) * HEIGHT <= ysize) : (yzoom += 1) {}
    gui.zoom = if (xzoom < yzoom) xzoom else yzoom;
    gui.width = @divFloor(@intCast(u16, xsize), gui.zoom);
    gui.height = @divFloor(@intCast(u16, ysize), gui.zoom);
    sdl_call(c.SDL_RenderSetScale(
        gui.render,
        @floatFromInt(f32, gui.zoom),
        @floatFromInt(f32, gui.zoom),
    ), "window_rect()");
}

pub fn check() void {
    var ev: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&ev) != 0) {
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
            c.SDL_MOUSEMOTION => {
                const zoom = @floatFromInt(f64, windows[ev.button.windowID - 1].zoom);
                const event = .{
                    .Screen_Mouse_Motion = .{
                        .x = @floatFromInt(f64, ev.button.x) / zoom,
                        .y = @floatFromInt(f64, ev.button.y) / zoom,
                        .window = ev.motion.windowID,
                    },
                };
                events.post(event);
            },
            c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => {
                const zoom = @floatFromInt(f64, windows[ev.button.windowID - 1].zoom);
                const event = .{
                    .Screen_Mouse_Click = .{
                        .state = ev.button.state == c.SDL_PRESSED,
                        .x = @floatFromInt(f64, ev.button.x) / zoom,
                        .y = @floatFromInt(f64, ev.button.y) / zoom,
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
                    c.SDL_WINDOWEVENT_EXPOSED => {
                        const old = current;
                        set(ev.window.windowID - 1);
                        refresh();
                        set(old);
                    },
                    c.SDL_WINDOWEVENT_RESIZED => {
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
    quit = true;
    thread.join();
    c.TTF_CloseFont(font);
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        c.SDL_DestroyRenderer(windows[i].render);
        c.SDL_DestroyWindow(windows[i].window);
    }
    c.TTF_Quit();
    c.SDL_Quit();
}

fn loop() void {
    while (!quit) {
        events.post(.{ .Screen_Check = {} });
        std.time.sleep(10 * std.time.ns_per_ms);
    }
}

fn sdl_call(err: c_int, name: []const u8) void {
    if (err < -1) {
        logger.err("{s}: error: {s}", .{ name, c.SDL_GetError() });
    }
}
