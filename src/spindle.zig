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

/// unloads a Module, calling its deinit function
fn unload(l: *Lua) i32 {
    const seamstress = lu.closureGetContext(l, Seamstress);
    const str = l.toStringEx(1);
    const m = seamstress.module_list.get(str) orelse l.raiseErrorStr("module %s not found", .{str.ptr});
    m.deinit(seamstress.l, seamstress.allocator, .canceled);
    lu.getSeamstress(l);
    _ = l.pushStringZ(str);
    l.pushNil();
    l.rawSetTable(-3);
    l.pop(1);
    // if (std.mem.eql(u8, str, "tui")) {
    //     const n = seamstress.module_list.get("cli").?;
    //     n.deinit(l, seamstress.allocator, .full);
    //     n.self = null;
    //     n.init(l, seamstress.allocator) catch |err| std.debug.panic("unable to resume CLI mode! {s}", .{@errorName(err)});
    //     n.launch(l, lu.getWheel(l)) catch |err| std.debug.panic("unable to resume CLI mode! {s}", .{@errorName(err)});
    // }
    return 0;
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
    if (std.mem.eql(u8, str, "tui")) {
        const n = seamstress.module_list.get("cli").?;
        n.deinit(l, seamstress.allocator, .full);
        n.self = null;
    }
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

const logger = std.log.scoped(.lua);
fn log(l: *Lua) i32 {
    const n = l.getTop();
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        const msg = l.toStringEx(i);
        logger.warn("{s}", .{msg});
    }
    return 0;
}

/// adds to the seamstress table
fn setUpSeamstress(l: *Lua, seamstress: *Seamstress, script: ?[:0]const u8) !void {
    dofile: {
        l.newTable();
        var buf: [16 * 1024]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .{ .buffer = &buf, .end_index = 0 };
        const a = fba.allocator();
        const location = try std.fs.selfExeDirPathAlloc(a);
        defer a.free(location);
        const path = try std.fs.path.joinZ(a, &.{ location, "..", "share", "seamstress", "lua" });
        defer a.free(path);
        const prefix = std.fs.realpathAlloc(a, path) catch |err| {
            if (builtin.is_test) {
                l.pushFunction(ziglua.wrap(quit));
                l.setField(-2, "_start");
                l.newTable();
                l.setField(-2, "async");
                l.setGlobal("seamstress");
                break :dofile;
            }
            return err;
        };
        _ = l.pushString(prefix);
        l.setField(-2, "_prefix");
        const seamstress_lua = try std.fs.path.joinZ(a, &.{ prefix, "seamstress", "seamstress.lua" });
        {
            var bbuf: [8 * 1024]u8 = undefined;
            var ffba: std.heap.FixedBufferAllocator = .{ .buffer = &bbuf, .end_index = 0 };
            const allocator = ffba.allocator();
            const cwd = try std.process.getCwdAlloc(allocator);
            defer allocator.free(cwd);
            _ = l.pushString(cwd);
            l.setField(-2, "_pwd");
        }
        l.setGlobal("seamstress");
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
    l.pushLightUserdata(seamstress);
    l.pushClosure(ziglua.wrap(unload), 1);
    l.setField(-2, "_unload");
    l.pushFunction(ziglua.wrap(log));
    l.setField(-2, "log");
    // and another one
    l.newTable();
    if (script) |s| _ = l.pushStringZ(s) else l.pushNil();
    l.setField(-2, "script_name");
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
    }
    l.pop(1);
}

/// starts the lua VM and sets up the seamstress table
pub fn init(allocator: *const std.mem.Allocator, seamstress: *Seamstress, script: ?[:0]const u8) *Lua {
    const l = Lua.init(allocator) catch |err| panic("error starting lua vm: {s}", .{@errorName(err)});
    errdefer l.close();

    // open lua libraries
    l.openLibs();
    setUpSeamstress(l, seamstress, script) catch {
        const msg = l.toStringEx(-1);
        l.traceback(l, msg, 1);
        panic("error setting up seamstress: {s}", .{msg});
    };
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
const builtin = @import("builtin");
