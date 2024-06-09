//! Lua VM lifetime functions (init, deinit, etc)
//! in this file to make seamstress.zig cleaner to read.

/// user-defined: cleans up resources the Lua layer has used
pub fn cleanup(l: *Lua) void {
    if ((l.getGlobal("seamstress") catch return) != .table) {
        l.pop(1);
        return;
    }
    _ = l.getField(-1, "cleanup");
    l.remove(-2);
    lu.doCall(l, 0, 0);
}

/// loads a Module, calling its init function
fn load(l: *Lua) i32 {
    const seamstress = lu.closureGetContext(l, Seamstress);
    const str = l.toStringEx(1);
    const m = seamstress.module_list.get(str) orelse l.raiseErrorStr("module %s not found", .{str.ptr});
    m.init(seamstress.l, seamstress.allocator) catch |err| l.raiseErrorStr("error while loading module %s: %s", .{ str.ptr, @errorName(err).ptr });
    return 0;
}

/// launches a Module, calling its launch function
fn launch(l: *Lua) i32 {
    const seamstress = lu.closureGetContext(l, Seamstress);
    const str = l.toStringEx(1);
    const m = seamstress.module_list.get(str) orelse l.raiseErrorStr("module %s not found", .{str.ptr});
    m.launch(seamstress.l, &seamstress.loop) catch |err| l.raiseErrorStr("error while launching module %s: %s", .{ str.ptr, @errorName(err).ptr });
    return 0;
}

/// quits seamstress
fn quit(l: *Lua) i32 {
    const wheel = lu.getWheel(l);
    wheel.quit();
    return 0;
}

/// restarts seamstress
fn restart(l: *Lua) i32 {
    const wheel = lu.getWheel(l);
    wheel.kind = .full;
    const seamstress: *Seamstress = @fieldParentPtr("loop", wheel);
    wheel.quit();
    seamstress.go_again = true;
    return 0;
}

/// adds to the seamstress table
fn setUpSeamstress(l: *Lua, seamstress: *Seamstress) !void {
    {
        var buf: [16 * 1024]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .{ .buffer = &buf, .end_index = 0 };
        const a = fba.allocator();
        const location = try std.fs.selfExeDirPathAlloc(a);
        defer a.free(location);
        const path = try std.fs.path.joinZ(a, &.{ location, "..", "share", "seamstress", "lua" });
        defer a.free(path);
        const prefix = try std.fs.realpathAlloc(a, path);
        _ = try l.getGlobal("package");
        _ = l.pushString(prefix);
        _ = l.pushStringZ("/?.lua;");
        _ = l.getField(-3, "path");
        l.concat(3);
        l.setField(-2, "path");
        l.pop(1);
        const seamstress_lua = try std.fs.path.joinZ(a, &.{ prefix, "seamstress", "seamstress.lua" });
        defer a.free(seamstress_lua);
        try l.doFile(seamstress_lua);
    }
    lu.getSeamstress(l);
    // push the event loop
    l.pushLightUserdata(&seamstress.loop);
    l.setField(-2, "_loop");
    // register the quit function
    l.pushFunction(ziglua.wrap(quit));
    l.setField(-2, "quit");
    l.pushFunction(ziglua.wrap(restart));
    l.setField(-2, "restart");
    l.pushLightUserdata(seamstress);
    l.pushClosure(ziglua.wrap(load), 1);
    l.setField(-2, "_load");
    l.pushLightUserdata(seamstress);
    l.pushClosure(ziglua.wrap(launch), 1);
    l.setField(-2, "_launch");
    // and another one
    l.newTable();
    // assign to the previous one
    l.setField(-2, "config");
    {
        // push seamstress version information
        const version = Seamstress.version;
        l.createTable(3, 1);
        l.pushInteger(@intCast(version.major));
        l.setIndex(-2, 1);
        l.pushInteger(@intCast(version.minor));
        l.setIndex(-2, 2);
        l.pushInteger(@intCast(version.patch));
        l.setIndex(-2, 3);
        if (version.pre) |pre| _ = l.pushString(pre) else l.pushNil();
        l.setField(-2, "pre");
        l.setField(-2, "version");
        {
            var buf: [8 * 1024]u8 = undefined;
            var fba: std.heap.FixedBufferAllocator = .{ .buffer = &buf, .end_index = 0 };
            const allocator = fba.allocator();
            const cwd = try std.process.getCwdAlloc(allocator);
            defer allocator.free(cwd);
            _ = l.pushString(cwd);
            l.setField(-2, "_pwd");
        }
    }
    l.pop(1);
}

/// starts the lua VM and sets up the seamstress table
pub fn init(allocator: *const std.mem.Allocator, seamstress: *Seamstress) *Lua {
    const l = Lua.init(allocator) catch |err| panic("error starting lua vm: {s}", .{@errorName(err)});
    errdefer l.close();

    // open lua libraries
    l.openLibs();
    setUpSeamstress(l, seamstress) catch |err| panic("error setting up seamstress: {s}", .{@errorName(err)});
    _ = l.atPanic(ziglua.wrap(luaPanic));
    return l;
}

/// have lua crash via our panic rather than its own way
fn luaPanic(l: *Lua) i32 {
    const str = l.toStringEx(-1);
    l.pop(1);
    l.traceback(l, str, 1);
    const msg = l.toString(-1) catch unreachable;
    l.pop(1);
    std.debug.panic("lua crashed: {s}", .{msg});
    return 0;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Seamstress = @import("seamstress.zig");
const std = @import("std");
const panic = std.debug.panic;
const lu = @import("lua_util.zig");
