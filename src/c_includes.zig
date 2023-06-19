const builtin = @import("builtin");
pub const imported = @cImport({
    @cInclude("lo/lo.h");
    // @cInclude("dns_sd.h");
    @cInclude("ncurses.h");
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
    @cInclude("SDL2/SDL_error.h");
    @cInclude("SDL2/SDL_render.h");
    @cInclude("SDL2/SDL_surface.h");
    @cInclude("SDL2/SDL_video.h");
    @cInclude("rtmidi/rtmidi_c.h");
});
