/// thin wrapper around the Lua vm
const Spindle = @This();

l: *Lua,
stderr: *BufferedWriter,
hello: ?struct {
    ctx: *anyopaque,
    hello_fn: *const fn (*anyopaque) void,
} = null,

pub fn cleanup(self: *Spindle) void {
    _ = self; // autofix
}

pub fn close(self: *Spindle) void {
    self.l.close();
}

fn setUpSeamstress(self: *Spindle) !void {
    const l = self.l;
    const seamstress: *Seamstress = @fieldParentPtr("vm", self);
    // create a new table
    l.newTable();
    // push the event loop
    l.pushLightUserdata(&seamstress.loop);
    l.setField(-2, "_loop");
    // and another one
    l.newTable();
    // assign to the previous one
    l.setField(-2, "config");
    {
        var buf: [16 * 1024]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .{ .buffer = &buf, .end_index = 0 };
        const a = fba.allocator();
        const location = try std.fs.selfExeDirPathAlloc(a);
        defer a.free(location);
        const path = try std.fs.path.joinZ(a, &.{ location, "..", "share", "seamstress", "lua" });
        defer a.free(path);
        const prefix = try std.fs.realpathAlloc(a, path);
        _ = l.pushString(prefix);
        l.setField(-2, "prefix");
    }
    {
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
    l.setGlobal("_seamstress");
}

pub fn init(self: *Spindle, allocator: *const std.mem.Allocator, stderr: *BufferedWriter) void {
    self.* = .{
        .l = Lua.init(allocator) catch |err| panic("error starting lua vm: {s}", .{@errorName(err)}),
        .stderr = stderr,
    };
    errdefer self.l.close();

    // open lua libraries
    self.l.openLibs();
    self.setUpSeamstress() catch |err| panic("error setting up seamstress: {s}", .{@errorName(err)});
    _ = self.l.atPanic(ziglua.wrap(luaPanic));
}

pub fn sayHello(self: *Spindle) void {
    if (self.hello) |h| h.hello_fn(h.ctx);
}

pub fn callInit(self: *Spindle) void {
    lu.getSeamstress(self.l);
    _ = self.l.getField(-1, "prefix");
    _ = self.l.pushString("/start.lua");
    self.l.concat(2);
    const file_name = self.l.toStringEx(-1);
    self.l.doFile(file_name) catch panic("unable to read start.lua!", .{});
    self.l.setTop(0);

    lu.getSeamstress(self.l);
    _ = self.l.getField(-1, "_startup");
    self.l.remove(-2);
    lu.doCall(self.l, 0, 0);
}

/// have lua crash via our panic rather than its own way
fn luaPanic(l: *Lua) i32 {
    const msg = l.toString(-1) catch "";
    std.debug.panic("lua crashed: {s}", .{msg});
    return 0;
}

const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Seamstress = @import("seamstress.zig");
const std = @import("std");
const panic = std.debug.panic;
const lu = @import("lua_util.zig");
