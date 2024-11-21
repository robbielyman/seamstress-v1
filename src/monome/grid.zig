pub fn register(l: *Lua) i32 {
    blk: {
        l.newMetatable("seamstress.monome.Grid") catch break :blk;
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(common.__index(.grid)) },
            .{ .name = "__newindex", .func = ziglua.wrap(common.__newindex(.grid)) },
            .{ .name = "__gc", .func = ziglua.wrap(common.__gc(.grid)) },
            .{ .name = "refresh", .func = ziglua.wrap(refresh) },
            .{ .name = "tiltEnable", .func = ziglua.wrap(tiltEnable) },
            .{ .name = "led", .func = ziglua.wrap(led) },
            .{ .name = "all", .func = ziglua.wrap(all) },
            .{ .name = "intensity", .func = ziglua.wrap(intensity) },
            .{ .name = "connect", .func = ziglua.wrap(common.connect(.grid)) },
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

const Grid = @This();

dirty: [4]bool = .{ true, true, true, true },
quads: enum { one, two, four } = .two,
rotation: enum { zero, ninety, one_eighty, two_seventy } = .zero,
connected: bool = false,

fn connect(l: *Lua) i32 {
    const idx = l.optInteger(1) orelse 1;
    lu.load(l, "seamstress.monome.Grid");
    switch (l.getIndex(-1, idx)) { // local g = seamstress.monome.Grid[idx]
        .userdata => {}, // g ~= nil
        else => { // g = seamstress.monome.Grid()
            l.pop(1);
            const grid = l.newUserdata(Grid, 2);
            grid.* = .{};
            _ = l.getMetatableRegistry("seamstress.monome.Grid");
            l.setMetatable(-2);
            l.pushValue(-1);
            l.setIndex(-3, idx); // seamstress.monome.Grid[idx] = g
        },
    }
    // g:connect()
    _ = l.getMetaField(-1, "connect") catch unreachable;
    l.pushValue(-2);
    l.call(1, 0);
    return 1; // return g
}

fn getServer(l: *Lua, grid: i32) ?*osc.Server {
    defer l.pop(1);
    if ((l.getUserValue(grid, 1) catch return null) != .table) return null;
    _ = l.getField(-1, "server");
    defer l.pop(1);
    return l.toUserdata(osc.Server, -1) catch null;
}

fn __call(l: *Lua) i32 {
    l.len(1);
    const len = l.toInteger(-1) catch unreachable;
    const grid = l.newUserdata(Grid, 2);
    grid.* = .{};
    _ = l.getMetatableRegistry("seamstress.monome.Grid");
    l.setMetatable(-2);
    l.pushValue(-1);
    l.setIndex(1, len + 1);
    return 1;
}

fn refresh(l: *Lua) i32 {
    const server = getServer(l, 1) orelse return 0;
    const grid = l.checkUserdata(Grid, 1, "seamstress.monome.Grid");
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    if (l.getField(1, "prefix") == .nil) {
        l.pop(1);
        _ = l.pushStringZ("/grid/led/level/map");
    } else {
        _ = l.pushStringZ("/grid/led/level/map");
        l.concat(2);
    }
    const path = l.toString(-1) catch unreachable;
    if ((l.getUserValue(1, 2) catch unreachable) == .nil) return 0;
    const x_off: [4]i32 = .{ 0, 8, 0, 8 };
    const y_off: [4]i32 = .{ 0, 0, 8, 8 };
    switch (grid.quads) {
        .one => {
            if (!grid.dirty[0]) return 0;
            _ = l.getIndex(-1, 1);
            const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
            builder.data.items[0] = .{ .i = 0 };
            builder.data.items[1] = .{ .i = 0 };
            const msg = builder.commit(l.allocator(), path) catch l.raiseErrorStr("out of memory!", .{});
            defer msg.unref();
            grid.dirty[0] = false;
            server.sendOSCBytes(client.addr, msg.toBytes()) catch |err|
                l.raiseErrorStr("error sending %s: %s", .{ path.ptr, @errorName(err).ptr });
        },
        .two => {
            const quad: [2]u2 = switch (grid.rotation) {
                .zero => .{ 0, 1 },
                .ninety => .{ 0, 2 },
                .one_eighty => .{ 1, 0 },
                .two_seventy => .{ 2, 0 },
            };
            for (&quad, 0..) |i, j| {
                if (!grid.dirty[j]) continue;
                _ = l.getIndex(-1, @intCast(j + 1));
                const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
                builder.data.items[0] = .{ .i = x_off[i] };
                builder.data.items[1] = .{ .i = y_off[i] };
                const msg = builder.commit(l.allocator(), path) catch l.raiseErrorStr("out of memory!", .{});
                defer msg.unref();
                grid.dirty[@intCast(j)] = false;
                server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
                    msg.unref();
                    l.raiseErrorStr("error sending %s: %s", .{ path.ptr, @errorName(err).ptr });
                };
                l.pop(1);
            }
        },
        .four => {
            for (0..4) |i| {
                if (!grid.dirty[i]) continue;
                _ = l.getIndex(-1, @intCast(i + 1));
                const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
                builder.data.items[0] = .{ .i = x_off[i] };
                builder.data.items[1] = .{ .i = y_off[i] };
                const msg = builder.commit(l.allocator(), path) catch l.raiseErrorStr("out of memory!", .{});
                defer msg.unref();
                grid.dirty[@intCast(i)] = false;
                server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
                    msg.unref();
                    l.raiseErrorStr("error sending %s: %s", .{ path.ptr, @errorName(err).ptr });
                };
                l.pop(1);
            }
        },
    }
    return 0;
}

fn tiltEnable(l: *Lua) i32 {
    const server = getServer(l, 1) orelse return 0;
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    const sensor = std.math.cast(i32, l.checkInteger(2)) orelse l.argError(2, "bad integer value");
    const enable = l.toBoolean(3);
    _ = l.getField(1, "prefix");
    _ = l.pushString("/tilt/set");
    l.concat(2);
    const path = l.toString(-1) catch unreachable;
    const msg = osc.z.Message.fromTuple(l.allocator(), path, .{ sensor, @as(i32, if (enable) 1 else 0) }) catch
        l.raiseErrorStr("out of memory!", .{});
    defer msg.unref();
    server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
        msg.unref();
        l.raiseErrorStr("error sending %s: %s", .{ path.ptr, @errorName(err).ptr });
    };
    return 0;
}

fn unrotate(grid: *const Grid, x: ziglua.Integer, y: ziglua.Integer) struct { ziglua.Integer, ziglua.Integer } {
    const rows: ziglua.Integer, const cols: ziglua.Integer = switch (grid.quads) {
        .one => .{ 8, 8 },
        .two => .{ 8, 16 },
        .four => .{ 16, 16 },
    };
    return switch (grid.rotation) {
        .zero => .{ x, y },
        .ninety => .{ y, rows + 1 - x },
        .one_eighty => .{ cols + 1 - x, rows + 1 - y },
        .two_seventy => .{ cols + 1 - y, x },
    };
}

test unrotate {
    const grids: []const Grid = &.{
        .{ .quads = .one, .rotation = .zero },
        .{ .quads = .one, .rotation = .ninety },
        .{ .quads = .one, .rotation = .one_eighty },
        .{ .quads = .one, .rotation = .two_seventy },
        .{ .quads = .two, .rotation = .zero },
        .{ .quads = .two, .rotation = .ninety },
        .{ .quads = .two, .rotation = .one_eighty },
        .{ .quads = .two, .rotation = .two_seventy },
        .{ .quads = .four, .rotation = .zero },
        .{ .quads = .four, .rotation = .ninety },
        .{ .quads = .four, .rotation = .one_eighty },
        .{ .quads = .four, .rotation = .two_seventy },
    };
    const x_s: []const ziglua.Integer = &.{
        1, 1, 8,  8,
        1, 1, 16, 16,
        1, 1, 16, 16,
    };
    const y_s: []const ziglua.Integer = &.{
        1, 8,  8,  1,
        1, 8,  8,  1,
        1, 16, 16, 1,
    };
    for (grids, x_s, y_s) |grid, exp_x, exp_y| {
        const x, const y = unrotate(grid, 1, 1);
        try std.testing.expectEqual(exp_x, x);
        try std.testing.expectEqual(exp_y, y);
    }
    const x_s2: []const ziglua.Integer = &.{
        5, 2, 4,  7,
        5, 2, 12, 15,
        5, 2, 12, 15,
    };
    const y_s2: []const ziglua.Integer = &.{
        2, 4,  7,  5,
        2, 4,  7,  5,
        2, 12, 15, 5,
    };
    for (grids, x_s2, y_s2) |grid, exp_x, exp_y| {
        const x, const y = unrotate(grid, 5, 2);
        try std.testing.expectEqual(exp_x, x);
        try std.testing.expectEqual(exp_y, y);
    }
}

fn whichQuad(grid: *const Grid, x: ziglua.Integer, y: ziglua.Integer) ziglua.Integer {
    return switch (grid.quads) {
        .one => 1,
        .two => if (x > 8) 2 else 1,
        .four => @as(ziglua.Integer, if (y > 8) 2 else 0) + @as(ziglua.Integer, if (x > 8) 2 else 1),
    };
}

fn quadIdx(x: ziglua.Integer, y: ziglua.Integer) usize {
    const m_y: usize = @intCast(@mod(y - 1, 8));
    const m_x: usize = @intCast(@mod(x - 1, 8));
    return (m_y * 8) + m_x + 2;
}

fn led(l: *Lua) i32 {
    const grid = l.checkUserdata(Grid, 1, "seamstress.monome.Grid");
    const i_x = common.checkIntegerAcceptingNumber(l, 2);
    const i_y = common.checkIntegerAcceptingNumber(l, 3);
    const x, const y = grid.unrotate(i_x, i_y);
    const rows: ziglua.Integer, const cols: ziglua.Integer = switch (grid.quads) {
        .one => .{ 8, 8 },
        .two => .{ 8, 16 },
        .four => .{ 16, 16 },
    };
    if (x < 1 or x > cols) return 0;
    if (y < 1 or y > rows) return 0;
    const z = @min(@max(0, common.checkIntegerAcceptingNumber(l, 4)), 15);
    const quad = grid.whichQuad(x, y);
    if ((l.getUserValue(1, 2) catch unreachable) == .nil) return 0;
    _ = l.getIndex(-1, quad);
    const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
    builder.data.items[quadIdx(x, y)] = .{ .i = @intCast(z) };
    grid.dirty[@intCast(quad - 1)] = true;
    return 0;
}

fn all(l: *Lua) i32 {
    const grid = l.checkUserdata(Grid, 1, "seamstress.monome.Grid");
    const level = common.checkIntegerAcceptingNumber(l, 2);
    l.argCheck(0 <= level and level <= 15, 2, "level must be between 0 and 15!");
    const quads: ziglua.Integer = switch (grid.quads) {
        .one => 1,
        .two => 2,
        .four => 4,
    };
    var i: ziglua.Integer = 1;
    blk: {
        if ((l.getUserValue(1, 2) catch unreachable) == .nil) break :blk;
        while (i <= quads) : (i += 1) {
            _ = l.getIndex(-1, i);
            const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
            @memset(builder.data.items[2..], .{ .i = @intCast(level) });
            l.pop(1);
        }
    }
    @memset(&grid.dirty, true);
    return 0;
}

fn intensity(l: *Lua) i32 {
    const level = common.checkIntegerAcceptingNumber(l, 2);
    l.argCheck(0 <= level and level <= 15, 2, "intensity must be between 0 and 15!");
    const server = getServer(l, 1) orelse return 0;
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    _ = l.getField(1, "prefix");
    _ = l.pushStringZ("/grid/led/intensity");
    l.concat(2);
    const path = l.toString(-1) catch unreachable;
    const msg = osc.z.Message.fromTuple(l.allocator(), path, .{@as(i32, @intCast(level))}) catch
        l.raiseErrorStr("out of memory!", .{});
    defer msg.unref();
    server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
        msg.unref();
        l.raiseErrorStr("error sending %s: %s", .{ path.ptr, @errorName(err).ptr });
    };
    return 0;
}

pub const DeclsTypes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "/sys/prefix", "s" },
    .{ "/sys/host", "s" },
    .{ "/sys/port", "i" },
    .{ "/sys/rotation", "i" },
    .{ "/sys/size", "ii" },
    .{ "//grid/key", "iii" },
    .{ "//tilt", "iiii" },
});

pub const Decls = struct {
    pub const @"/sys/prefix" = common.@"/sys/prefix";
    pub const @"/sys/host" = common.@"/sys/host";
    pub const @"/sys/port" = common.@"/sys/port";

    pub fn @"/sys/rotation"(l: *Lua, _: std.net.Address, _: []const u8, rotation: i32) osc.z.Continue {
        const grid_idx = Lua.upvalueIndex(1);
        _ = l.getUserValue(grid_idx, 1) catch unreachable;
        l.pushInteger(rotation);
        l.setField(-2, "rotation"); // set grid.rotation
        const grid = l.toUserdata(Grid, grid_idx) catch unreachable;
        grid.rotation = switch (rotation) {
            0 => .zero,
            1, 90 => .ninety,
            2, 180 => .one_eighty,
            3, 270 => .two_seventy,
            else => l.raiseErrorStr("bad OSC data!", .{}),
        };
        return .no;
    }

    pub fn @"/sys/size"(l: *Lua, _: std.net.Address, _: []const u8, rows: i32, cols: i32) osc.z.Continue {
        const grid_idx = Lua.upvalueIndex(1);
        _ = l.getUserValue(grid_idx, 1) catch unreachable;
        const grid_tbl_idx = l.getTop();
        l.pushInteger(rows);
        l.setField(grid_tbl_idx, "rows"); // set grid.rows
        l.pushInteger(cols);
        l.setField(grid_tbl_idx, "cols"); // set grid.cols
        const quads = std.math.divExact(i32, rows * cols, 64) catch l.raiseErrorStr("bad OSC data!", .{});
        const grid = l.toUserdata(Grid, grid_idx) catch unreachable;
        grid.quads = switch (quads) {
            1 => .one,
            2 => .two,
            4 => .four,
            else => l.raiseErrorStr("bad OSC data!", .{}),
        };
        l.pushInteger(quads);
        l.setField(grid_tbl_idx, "quads"); // set grid.quads
        l.createTable(quads, 0); // create grid quad data
        lu.load(l, "seamstress.osc.Message"); // each datum is a seamstress.osc.Message
        var i: i32 = 1;
        while (i <= quads) : (i += 1) {
            l.pushValue(-1); // push the function
            l.call(0, 1); // call it
            const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable; // the result is a Builder
            const arr = builder.data.addManyAsArray(builder.allocator, 66) catch l.raiseErrorStr("out of memory!", .{}); // add 64 elements
            @memset(arr, .{ .i = 0 }); // all of which are 0-valued integers
            l.setIndex(-3, i); // assign it to the new table
        }
        l.pop(1); // pop the seamstress.osc.Message function
        l.setUserValue(grid_idx, 2) catch unreachable; // assign the new table
        return .no;
    }

    pub fn @"//grid/key"(l: *Lua, _: std.net.Address, _: []const u8, x: i32, y: i32, z: i32) osc.z.Continue {
        const grid_idx = Lua.upvalueIndex(1);
        _ = l.getField(grid_idx, "key");
        if (!lu.isCallable(l, -1)) return .yes;
        l.pushInteger(x + 1);
        l.pushInteger(y + 1);
        l.pushInteger(z);
        l.call(3, 0);
        return .no;
    }

    pub fn @"//tilt"(l: *Lua, _: std.net.Address, _: []const u8, n: i32, x: i32, y: i32, z: i32) osc.z.Continue {
        const grid_idx = Lua.upvalueIndex(1);
        _ = l.getField(grid_idx, "tilt");
        if (!lu.isCallable(l, -1)) return .yes;
        l.pushInteger(n + 1);
        l.pushInteger(x);
        l.pushInteger(y);
        l.pushInteger(z);
        l.call(4, 0);
        return .no;
    }
};

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const std = @import("std");
const lu = @import("../lua_util.zig");
const common = @import("common.zig");
