export fn luaopen_seamstress(l: ?*ziglua.LuaState) c_int {
    const lua: *Lua = @ptrCast(l.?);
    return @call(.always_inline, Seamstress.register, .{lua});
}

const Seamstress = @import("seamstress.zig");
const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
