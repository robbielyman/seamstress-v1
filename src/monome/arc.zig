pub fn register(l: *Lua) i32 {
    l.pushFunction(ziglua.wrap(new));
    return 1;
}

fn refresh(l: *Lua) i32 {
    const server = l.toUserdata(osc.Server, Lua.upvalueIndex(1)) catch unreachable;
    const arc = l.checkUserdata(Arc, 1, "seamstress.monome.Arc");
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    _ = l.getField(1, "prefix");
    _ = l.pushString("/ring/map");
    l.concat(2);
    const path = l.toString(-1) catch unreachable;
    _ = l.getUserValue(1, 2) catch unreachable;
    for (0..4) |i| {
        if (!arc.dirty[i]) continue;
        _ = l.getIndex(-1, @intCast(i + 1));
        const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
        builder.data.items[0] = .{ .i = @intCast(i + 1) };
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
    _ = l.getUserValue(1, 2) catch unreachable;
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
    _ = l.getUserValue(1, 2) catch unreachable;
    while (i <= 4) : (i += 1) {
        _ = l.getIndex(-1, i);
        const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable;
        @memset(builder.data.items[1..], .{ .i = @intCast(level) });
        l.pop(1);
    }
    @memset(&arc.dirty, true);
    return 0;
}

const Arc = @This();
dirty: [4]bool = .{ true, true, true, true },

fn new(l: *Lua) i32 {
    const inner = struct {
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "//enc/delta", .func = ziglua.wrap(osc.wrap(@"//enc/delta")) },
            .{ .name = "//enc/key", .func = ziglua.wrap(osc.wrap(@"//enc/key")) },
            .{ .name = "/sys/prefix", .func = ziglua.wrap(osc.wrap(common.@"/sys/prefix")) },
        };
        const funcs2: []const ziglua.FnReg = &.{
            .{ .name = "/sys/host", .func = ziglua.wrap(osc.wrap(common.@"/sys/host")) },
            .{ .name = "/sys/port", .func = ziglua.wrap(osc.wrap(common.@"/sys/port")) },
        };
        const funcs3: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(common.__index(.arc)) },
            .{ .name = "__newindex", .func = ziglua.wrap(common.__newindex(.arc)) },
            .{ .name = "__gc", .func = ziglua.wrap(common.__gc(.arc)) },
            .{ .name = "refresh", .func = ziglua.wrap(refresh) },
            .{ .name = "led", .func = ziglua.wrap(led) },
            .{ .name = "all", .func = ziglua.wrap(all) },
            .{ .name = "connect", .func = ziglua.wrap(common.connect) },
        };
    };
    const arc = l.newUserdata(Arc, 2);
    const arc_idx = l.getTop();
    arc.* = .{};
    l.newTable(); // t
    l.pushValue(2); // id
    l.setField(-2, "id"); // t.id = id
    l.pushValue(3); // type
    l.setField(-2, "type"); // t.type = type
    lu.load(l, "seamstress.osc.Client") catch unreachable;
    l.createTable(0, @intCast(inner.funcs.len + inner.funcs2.len + 1)); // s
    l.pushValue(arc_idx); // arc
    l.setFuncs(inner.funcs, 1);
    l.pushValue(arc_idx); // arc
    l.pushValue(1); // server
    l.setFuncs(inner.funcs2, 2);
    l.pushValue(4); // address
    l.setField(-2, "address");
    l.call(1, 1); // client = seamstress.osc.Client(s)
    l.setField(-2, "client"); //  t.client = client
    l.setUserValue(arc_idx, 1) catch unreachable; // assign t to arc
    l.newTable();
    l.pushValue(1); // server
    l.setFuncs(inner.funcs3, 1);
    _ = l.pushString("seamstress.monome.Arc");
    l.setField(-2, "__name");
    l.setMetatable(-2); // assign metatable to arc

    // send a /sys/info message to the arc
    _ = l.getField(1, "send"); // send
    l.pushValue(1); // server
    l.pushValue(4); // address
    l.pushClosure(ziglua.wrap(common.@"/sys/info"), 3); // set the /sys/info closure
    l.pushValue(-1); // copy it
    l.setField(-3, "info"); // assign to arc.info
    l.call(0, 0); // also call it
    return 1; // return arc
}

fn @"//enc/delta"(l: *Lua, msg: *osc.z.Parse.MessageIterator, _: std.net.Address) osc.z.Continue {
    const arc_idx = Lua.upvalueIndex(1);
    if (!std.mem.eql(u8, msg.types, "ii")) l.raiseErrorStr("bad OSC types for %s: %s", .{
        @as([*:0]const u8, @ptrCast(msg.path.ptr)),
        @as([*:0]const u8, @ptrCast(msg.types.ptr)),
    });
    const n = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    const d = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    _ = l.getField(arc_idx, "delta");
    if (!lu.isCallable(l, -1)) return .yes;
    l.pushInteger(n);
    l.pushInteger(d);
    l.call(2, 0);
    return .no;
}

fn @"//enc/key"(l: *Lua, msg: *osc.z.Parse.MessageIterator, _: std.net.Address) osc.z.Continue {
    const arc_idx = Lua.upvalueIndex(1);
    if (!std.mem.eql(u8, msg.types, "ii")) l.raiseErrorStr("bad OSC types for %s: %s", .{
        @as([*:0]const u8, @ptrCast(msg.path.ptr)),
        @as([*:0]const u8, @ptrCast(msg.types.ptr)),
    });
    const n = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    const z = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    _ = l.getField(arc_idx, "delta");
    if (!lu.isCallable(l, -1)) return .yes;
    l.pushInteger(n);
    l.pushInteger(z);
    l.call(2, 0);
    return .no;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const lu = @import("../lua_util.zig");
const common = @import("common.zig");
const std = @import("std");
