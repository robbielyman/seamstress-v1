const std = @import("std");
const clock = @import("clock.zig");
const c = @cImport({
    @cInclude("abl_link.h");
});
