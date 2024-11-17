pub fn register(l: *Lua) i32 {
    blk: {
        l.newMetatable("seamstress.monome.Arc") catch break :blk;
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(common.__index(.arc)) },
            .{ .name = "__newindex", .func = ziglua.wrap(common.__newindex(.arc)) },
            .{ .name = "__gc", .func = ziglua.wrap(common.__gc(.arc)) },
            .{ .name = "refresh", .func = ziglua.wrap(refresh) },
            .{ .name = "led", .func = ziglua.wrap(led) },
            .{ .name = "all", .func = ziglua.wrap(all) },
            .{ .name = "connect", .func = ziglua.wrap(common.connect(.arc)) },
            .{ .name = "info", .func = ziglua.wrap(common.@"/sys/info") },
        };
        l.setFuncs(funcs, 0);
    }
    l.pop(1);
    l.newTable();
    l.newTable();
    const funcs: []const ziglua.FnReg = &.{
        .{ .name = "__call", .func = ziglua.wrap(__call) },
        .{ .name = "connect", .func = ziglua.wrap(connect) },
    };
    l.setFuncs(funcs, 0);
    _ = l.pushStringZ("__index");
    l.pushValue(-2);
    l.setTable(-3);
    l.setMetatable(-2);
    return 1;
}

fn getServer(l: *Lua, arc: i32) ?*osc.Server {
    defer l.pop(1);
    if ((l.getUserValue(arc, 1) catch return null) != .table) return null;
    _ = l.getField(-1, "server");
    defer l.pop(1);
    return l.toUserdata(osc.Server, -1) catch null;
}

fn __call(l: *Lua) i32 {
    l.len(1);
    const len = l.toInteger(-1) catch unreachable;
    const arc = l.newUserdata(Arc, 2);
    arc.* = .{};
    _ = l.getMetatableRegistry("seamstress.monome.Arc");
    l.setMetatable(-2);
    l.pushValue(-1);
    l.setIndex(1, len + 1);
    return 1;
}

fn connect(l: *Lua) i32 {
    const idx = l.optInteger(1) orelse 1;
    lu.load(l, "seamstress.monome.Arc");
    switch (l.getIndex(-1, idx)) { // local g = seamstress.monome.Arc[idx]
        .userdata => {}, // g ~= nil
        else => { // g = seamstress.monome.Arc()
            l.pop(1);
            const arc = l.newUserdata(Arc, 2);
            arc.* = .{};
            _ = l.getMetatableRegistry("seamstress.monome.Arc");
            l.setMetatable(-2);
            l.pushValue(-1);
            l.setIndex(-3, idx); // seamstress.monome.Arc[idx] = g
        },
    }
    // g:connect()
    _ = l.getMetaField(-1, "connect") catch unreachable;
    l.pushValue(-2);
    l.call(1, 0);
    return 1; // return g
}

fn refresh(l: *Lua) i32 {
    const arc = l.checkUserdata(Arc, 1, "seamstress.monome.Arc");
    const server = getServer(l, 1) orelse return 0;
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    if (l.getField(1, "prefix") == .nil) {
        l.pop(1);
        _ = l.pushStringZ("/ring/map");
    } else {
        _ = l.pushStringZ("/ring/map");
        l.concat(2);
    }
    const path = l.toString(-1) catch unreachable;
    if ((l.getUserValue(1, 2) catch unreachable) == .nil) return 0;
    for (0..4) |i| {
        if (!arc.dirty[i]) continue;
        _ = l.getIndex(-1, @intCast(i + 1));
        const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
        builder.data.items[0] = .{ .i = @intCast(i) };
        const msg = builder.commit(l.allocator(), path) catch l.raiseErrorStr("out of memory!", .{});
        defer msg.unref();
        arc.dirty[i] = false;
        server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
            msg.unref();
            l.raiseErrorStr("error sending %s: %s", .{ path.ptr, @errorName(err).ptr });
        };
        l.pop(1);
    }
    return 0;
}

fn led(l: *Lua) i32 {
    const arc = l.checkUserdata(Arc, 1, "seamstress.monome.Arc");
    const n = common.checkIntegerAcceptingNumber(l, 2);
    const x = common.checkIntegerAcceptingNumber(l, 3);
    const level = common.checkIntegerAcceptingNumber(l, 4);
    l.argCheck(1 <= n and n <= 4, 2, "n must be between 1 and 4!");
    l.argCheck(0 <= level and level <= 15, 4, "level must be between 0 and 15!");
    if ((l.getUserValue(1, 2) catch unreachable) == .nil) return 0;
    _ = l.getIndex(-1, n);
    const index: usize = @intCast(@mod(x - 1, 64));
    const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
    builder.data.items[index + 1] = .{ .i = @intCast(level) };
    arc.dirty[@intCast(n - 1)] = true;
    return 0;
}

fn all(l: *Lua) i32 {
    const arc = l.checkUserdata(Arc, 1, "seamstress.monome.Arc");
    const level = common.checkIntegerAcceptingNumber(l, 2);
    l.argCheck(0 <= level and level <= 15, 2, "level must be between 0 and 15!");
    var i: ziglua.Integer = 1;
    blk: {
        if ((l.getUserValue(1, 2) catch unreachable) == .nil) break :blk;
        while (i <= 4) : (i += 1) {
            _ = l.getIndex(-1, i);
            const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
            @memset(builder.data.items[1..], .{ .i = @intCast(level) });
            l.pop(1);
        }
    }
    @memset(&arc.dirty, true);
    return 0;
}

const Arc = @This();
dirty: [4]bool = .{ true, true, true, true },
connected: bool = false,

pub const Decls = struct {
    pub const @"/sys/prefix" = common.@"/sys/prefix";
    pub const @"/sys/host" = common.@"/sys/host";
    pub const @"/sys/port" = common.@"/sys/port";

    pub fn @"//enc/delta"(l: *Lua, _: std.net.Address, _: []const u8, n: i32, d: i32) osc.z.Continue {
        const arc_idx = Lua.upvalueIndex(1);
        _ = l.getField(arc_idx, "delta");
        if (!lu.isCallable(l, -1)) return .yes;
        l.pushInteger(n + 1);
        l.pushInteger(d);
        l.call(2, 0);
        return .no;
    }

    pub fn @"//enc/key"(l: *Lua, _: std.net.Address, _: []const u8, n: i32, z: i32) osc.z.Continue {
        const arc_idx = Lua.upvalueIndex(1);
        _ = l.getField(arc_idx, "delta");
        if (!lu.isCallable(l, -1)) return .yes;
        l.pushInteger(n + 1);
        l.pushInteger(z);
        l.call(2, 0);
        return .no;
    }
};

pub const DeclsTypes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "/sys/prefix", "s" },
    .{ "/sys/host", "s" },
    .{ "/sys/port", "i" },
    .{ "//enc/delta", "ii" },
    .{ "//enc/key", "ii" },
});

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const lu = @import("../lua_util.zig");
const common = @import("common.zig");
const std = @import("std");
