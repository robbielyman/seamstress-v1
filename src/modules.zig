pub const list = std.StaticStringMap(*const fn (?*ziglua.LuaState) callconv(.C) i32).initComptime(.{
    .{ "seamstress", ziglua.wrap(@import("seamstress.zig").register) },
});

const std = @import("std");
const ziglua = @import("ziglua");
