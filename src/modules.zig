/// the master list of all seamstress modules
/// pub so that the loader function defined in seamstress.zig can access it
pub const list = std.StaticStringMap(*const fn (?*ziglua.LuaState) callconv(.C) i32).initComptime(.{
    .{ "seamstress", ziglua.wrap(@import("seamstress.zig").register) },
    .{ "seamstress.event", ziglua.wrap(openFn("event.lua")) },
    .{ "seamstress.async", ziglua.wrap(@import("async.zig").register(.@"async")) },
    .{ "seamstress.async.Promise", ziglua.wrap(@import("async.zig").register(.promise)) },
    .{ "seamstress.test", ziglua.wrap(openFn("test.lua")) },
    .{ "seamstress.Timer", ziglua.wrap(@import("timer.zig").register) },
    .{ "seamstress.osc", ziglua.wrap(@import("osc.zig").register(.osc)) },
    .{ "seamstress.osc.Client", ziglua.wrap(@import("osc.zig").register(.client)) },
    .{ "seamstress.osc.Server", ziglua.wrap(@import("osc.zig").register(.server)) },
    .{ "seamstress.osc.Message", ziglua.wrap(@import("osc.zig").register(.message)) },
    .{ "seamstress.monome", ziglua.wrap(@import("monome.zig").register(.monome)) },
    .{ "seamstress.monome.Grid", ziglua.wrap(@import("monome.zig").register(.grid)) },
    .{ "seamstress.monome.Arc", ziglua.wrap(@import("monome.zig").register(.arc)) },
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
pub const load = if (builtin.mode == .Debug) loadComptime else loadRuntime;

fn loadRuntime(l: *Lua, module_name: [:0]const u8) void {
    const func = list.get(module_name).?;
    l.requireF(module_name, func, false);
}

fn loadComptime(l: *Lua, comptime module_name: [:0]const u8) void {
    const func = comptime list.get(module_name) orelse @compileError("no such module name!");
    l.requireF(module_name, func, false);
}

const std = @import("std");
const builtin = @import("builtin");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
