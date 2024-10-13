/// the master list of all seamstress modules
/// pub so that the loader function defined in seamstress.zig can access it
pub const list = std.StaticStringMap(*const fn (?*ziglua.LuaState) callconv(.C) i32).initComptime(.{
    .{ "seamstress", ziglua.wrap(@import("seamstress.zig").register) },
    .{ "seamstress.event", ziglua.wrap(openFn("event.lua")) },
    .{ "seamstress.async", ziglua.wrap(@import("async.zig").register(.@"async")) },
    .{ "seamstress.async.Promise", ziglua.wrap(@import("async.zig").register(.promise)) },
    .{ "seamstress.test", ziglua.wrap(openFn("test.lua")) },
    .{ "seamstress.Timer", ziglua.wrap(@import("timer.zig").register) },
});

fn openFn(comptime filename: []const u8) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            const prefix = std.process.getEnvVarOwned(l.allocator(), "SEAMSTRESS_LUA_PATH") catch return 0;
            defer l.allocator().free(prefix);
            var buf: ziglua.Buffer = undefined;
            buf.init(l); // local buf = ""
            buf.addString(prefix); // buf = buf .. os.getenv("SEAMSTRESS_LUA_PATH")
            buf.addString(if (builtin.os.tag == .windows) "\\core\\" else "/core/"); // buf = buf .. "/core/"
            buf.addString(filename); // buf = buf .. filename
            buf.pushResult();
            l.doFile(l.toString(-1) catch unreachable) catch l.raiseError(); // local res = dofile(buf) -- (not pcalled!)
            return 1; // return res
        }
    }.f;
}

/// loads the seamstress module `module_name`; e.g. "seamstress" or "seamstress.event".
/// returns error.NoSuchSeamstressModule if `module_name` is not present in the list
pub fn load(l: *Lua, module_name: [:0]const u8) !void {
    const func = list.get(module_name) orelse return error.NoSuchSeamstressModule;
    l.requireF(module_name, func, false);
}

const std = @import("std");
const builtin = @import("builtin");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
