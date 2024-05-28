pub fn configure(seamstress: *Seamstress) void {
    seamstress.modules.appendSlice(seamstress.allocator, &.{
        @import("tui.zig").module(),
        @import("osc.zig").module(),
    }) catch panic("out of memory!", .{});
}

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const panic = std.debug.panic;
