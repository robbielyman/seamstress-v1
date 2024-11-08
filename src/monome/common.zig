pub fn __index(comptime which: enum { grid, arc }) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            if (which == .grid) {
                const grid = l.checkUserdata(@import("grid.zig"), 1, "seamstress.monome.Grid");
                _ = l.pushStringZ("rotation");
                if (l.compare(2, -1, .eq)) {
                    l.pushInteger(switch (grid.rotation) {
                        .zero => 0,
                        .ninety => 90,
                        .one_eighty => 180,
                        .two_seventy => 270,
                    });
                    return 1;
                }
            }
            _ = l.getUserValue(1, 1) catch unreachable;
            l.pushValue(2);
            switch (l.getTable(-2)) {
                .nil, .none => {
                    l.getMetatable(1) catch unreachable;
                    l.pushValue(2);
                    _ = l.getTable(-2);
                    return 1;
                },
                else => return 1,
            }
        }
    }.f;
}

pub fn __newindex(comptime which: enum { grid, arc }) fn (*Lua) i32 {
    return struct {
        fn __newindex(l: *Lua) i32 {
            const protected: []const [:0]const u8 = &.{
                "id",
                "type",
                "destination",
                "connected",
                "rows",
                "cols",
                "quads",
            };
            for (protected) |key| {
                _ = l.pushString(key);
                if (l.compare(2, -1, .eq)) l.raiseErrorStr("unable to modify field %s", .{key.ptr});
            }
            if (which == .grid) _ = l.pushString("rotation");
            const server_idx = Lua.upvalueIndex(1);
            if (which == .grid) if (l.compare(2, -1, .eq)) {
                const rotation = l.checkInteger(3);
                const grid = l.checkUserdata(@import("grid.zig"), 1, "seamstress.monome.Grid");
                grid.rotation = switch (rotation) {
                    0 => .zero,
                    1, 90 => .ninety,
                    2, 180 => .one_eighty,
                    3, 270 => .two_seventy,
                    else => l.raiseErrorStr("rotation must be 0, 90, 180 or 270", .{}),
                };
                _ = l.getField(server_idx, "send");
                l.pushValue(server_idx);
                _ = l.getField(1, "client");
                l.createTable(1, 2);
                _ = l.pushString("/sys/rotation");
                _ = l.pushString("i");
                l.pushInteger(switch (grid.rotation) {
                    .zero => 0,
                    .ninety => 90,
                    .one_eighty => 180,
                    .two_seventy => 270,
                });
                l.setIndex(-4, 1);
                l.setField(-3, "types");
                l.setField(-2, "path");
                l.call(3, 0);
                return 0;
            };
            _ = l.pushString("prefix");
            if (l.compare(2, -1, .eq)) {
                const prefix = l.checkString(3);
                _ = l.getUserValue(1, 1) catch unreachable;
                l.pushValue(2);
                if (prefix[0] == '/') {
                    l.pushValue(3);
                } else {
                    var buf: ziglua.Buffer = undefined;
                    buf.init(l);
                    buf.addChar('/');
                    buf.addString(prefix);
                    buf.pushResult();
                }
                l.pushValue(-1);
                l.rotate(-4, 1);
                l.setTable(-3);
                _ = l.getField(server_idx, "send");
                l.pushValue(server_idx);
                _ = l.getField(1, "client");
                l.createTable(1, 2);
                _ = l.pushString("/sys/prefix");
                _ = l.pushString("s");
                l.pushValue(-4);
                l.setIndex(-4, 1);
                l.setField(-3, "types");
                l.setField(-2, "path");
                l.call(3, 0);
                return 0;
            }
            _ = l.getUserValue(1, 1) catch unreachable;
            l.pushValue(2);
            l.pushValue(3);
            l.setTable(-3);
            return 0;
        }
    }.__newindex;
}

pub fn __gc(comptime which: enum { grid, arc }) fn (*Lua) i32 {
    return struct {
        fn __gc(l: *Lua) i32 {
            const server_idx = Lua.upvalueIndex(1);
            _ = l.getField(1, "connected");
            if (!l.toBoolean(-1)) return 0;
            const reps = if (which == .grid) 1 else 4;
            for (0..reps) |i| {
                _ = l.getField(server_idx, "send");
                l.pushValue(server_idx);
                _ = l.getField(1, "client");
                l.createTable(1, 2);
                _ = l.getField(1, "prefix");
                _ = l.pushString(switch (which) {
                    .grid => "/grid/led/all",
                    .arc => "/ring/all",
                });
                l.concat(2);
                _ = l.pushString(switch (which) {
                    .grid => "i",
                    .arc => "ii",
                });
                l.pushInteger(0);
                l.setIndex(-4, if (which == .grid) 1 else 2);
                if (which == .arc) {
                    l.pushInteger(@intCast(i + 1));
                    l.setIndex(-4, 1);
                }
                l.setField(-3, "types");
                l.setField(-2, "path");
                lu.doCall(l, 3, 0) catch lu.reportError(l);
            }
            return 0;
        }
    }.__gc;
}

pub fn checkIntegerAcceptingNumber(l: *Lua, idx: i32) ziglua.Integer {
    if (l.isInteger(idx)) return l.toInteger(idx) catch unreachable;
    return @intFromFloat(l.checkNumber(idx));
}

/// sends a /sys/info message to the serialosc server
/// captures an address and a server upvalue
pub fn @"/sys/info"(l: *Lua) i32 {
    const func_idx = Lua.upvalueIndex(1);
    const server_idx = Lua.upvalueIndex(2);
    const address_idx = Lua.upvalueIndex(3);
    const server = l.toUserdata(osc.Server, server_idx) catch l.raiseError();
    l.pushValue(func_idx); // send
    l.pushValue(server_idx); // server
    l.pushValue(address_idx); // address
    osc.pushAddress(l, .array, server.addr); // t = {host, port}
    _ = l.pushString("/sys/info");
    _ = l.pushString("si");
    l.setField(-3, "types"); // t.types = "si"
    l.setField(-2, "path"); // t.path = "/sys/info"
    l.call(3, 0); // server:send(address, t)
    return 0;
}

pub fn @"/sys/port"(l: *Lua, msg: *osc.z.Parse.MessageIterator, _: std.net.Address) osc.z.Continue {
    const dev_idx = Lua.upvalueIndex(1);
    const server_idx = Lua.upvalueIndex(2);
    if (!std.mem.eql(u8, msg.types, "i")) l.raiseErrorStr("bad OSC types for %s: %s", .{
        @as([*:0]const u8, @ptrCast(msg.path.ptr)),
        @as([*:0]const u8, @ptrCast(msg.types.ptr)),
    });
    const port = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    const server = l.toUserdata(osc.Server, server_idx) catch unreachable;
    _ = l.getField(dev_idx, "destination");
    _ = l.pushInteger(port);
    l.setIndex(-2, 2);
    const addr = osc.parseAddress(l, -1) catch l.raiseErrorStr("bad OSC data!", .{});
    _ = l.getUserValue(dev_idx, 1) catch unreachable;
    l.pushBoolean(server.addr.eql(addr));
    l.setField(-2, "connected");
    return .no;
}

pub fn @"/sys/host"(l: *Lua, msg: *osc.z.Parse.MessageIterator, _: std.net.Address) osc.z.Continue {
    const dev_idx = Lua.upvalueIndex(1);
    const server_idx = Lua.upvalueIndex(2);
    if (!std.mem.eql(u8, msg.types, "s")) l.raiseErrorStr("bad OSC types for %s: %s", .{
        @as([*:0]const u8, @ptrCast(msg.path.ptr)),
        @as([*:0]const u8, @ptrCast(msg.types.ptr)),
    });
    const host = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.s;
    const server = l.toUserdata(osc.Server, server_idx) catch unreachable;
    _ = l.getField(dev_idx, "destination");
    _ = l.pushString(host);
    l.setIndex(-2, 1);
    const addr = osc.parseAddress(l, -1) catch l.raiseErrorStr("bad OSC data!", .{});
    _ = l.getUserValue(dev_idx, 1) catch unreachable;
    l.pushBoolean(server.addr.eql(addr));
    l.setField(-2, "connected");
    return .no;
}

pub fn @"/sys/prefix"(l: *Lua, msg: *osc.z.Parse.MessageIterator, _: std.net.Address) osc.z.Continue {
    const dev_idx = Lua.upvalueIndex(1);
    if (!std.mem.eql(u8, msg.types, "s")) l.raiseErrorStr("bad OSC types for %s: %s", .{
        @as([*:0]const u8, @ptrCast(msg.path.ptr)),
        @as([*:0]const u8, @ptrCast(msg.types.ptr)),
    });
    const prefix = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.s;
    _ = l.getUserValue(dev_idx, 1) catch unreachable;
    _ = l.pushString(prefix);
    l.setField(-2, "prefix");
    return .no;
}

pub fn connect(l: *Lua) i32 {
    const server = l.toUserdata(osc.Server, Lua.upvalueIndex(1)) catch unreachable;
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    osc.pushAddress(l, .array, server.addr);
    _ = l.getIndex(-1, 1);
    const host = l.toString(-1) catch unreachable;
    _ = l.getIndex(-2, 2);
    const port = l.toInteger(-1) catch unreachable;
    {
        const msg = osc.z.Message.fromTuple(l.allocator(), "/sys/host", .{host}) catch l.raiseErrorStr("out of memory!", .{});
        defer msg.unref();
        server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
            msg.unref();
            l.raiseErrorStr("error sending /sys/host: %s", .{@errorName(err).ptr});
        };
    }
    {
        const msg = osc.z.Message.fromTuple(l.allocator(), "/sys/port", .{@as(i32, @intCast(port))}) catch
            l.raiseErrorStr("out of memory!", .{});
        defer msg.unref();
        server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
            msg.unref();
            l.raiseErrorStr("error sending /sys/port: %s", .{@errorName(err).ptr});
        };
    }
    _ = l.getField(1, "info");
    l.call(0, 0);
    return 0;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const std = @import("std");
const lu = @import("../lua_util.zig");
