pub fn register(comptime which: enum { monome, grid, arc }) fn (*Lua) i32 {
    return switch (which) {
        .monome => struct {
            fn f(l: *Lua) i32 {
                lu.load(l, "seamstress.osc.Server");
                l.pushNil();
                const realLoader = struct {
                    fn f(lua: *Lua) i32 {
                        const id = Lua.upvalueIndex(1);
                        const monome = Lua.upvalueIndex(2);
                        if (lua.typeOf(monome) != .nil) {
                            lua.pushValue(monome);
                            return 1;
                        }
                        lua.createTable(0, 3);
                        lua.pushValue(id);
                        lua.pushValue(1);
                        lu.doCall(lua, 1, 1) catch lua.raiseErrorStr("unable to create serialosc server!", .{});
                        populateSerialoscServer(lua) catch lua.raiseErrorStr("error populating serialosc client!", .{});
                        lua.setField(-2, "serialosc");
                        lu.load(lua, "seamstress.monome.Grid");
                        lua.setField(-2, "Grid");
                        lu.load(lua, "seamstress.monome.Arc");
                        lua.setField(-2, "Arc");
                        lua.pushValue(-1);
                        lua.replace(monome);
                        return 1;
                    }
                }.f;
                l.pushClosure(ziglua.wrap(realLoader), 2);
                return 1;
            }
        }.f,
        .grid => @import("monome/grid.zig").register,
        .arc => @import("monome/arc.zig").register,
    };
}

fn populateSerialoscServer(l: *Lua) !void {
    const builtin = @import("builtin");
    const top = if (builtin.mode == .Debug) l.getTop();
    const server_idx = l.getTop();
    const server = try l.toUserdata(osc.Server, -1);
    osc.pushAddress(l, .array, server.addr);
    var builder = osc.z.Message.Builder.init(l.allocator());
    defer builder.deinit();
    _ = l.getIndex(-1, 1);
    _ = l.getIndex(-2, 2);
    const host = try l.toString(-2);
    const portnum = try l.toInteger(-1);
    try builder.append(.{ .s = host });
    try builder.append(.{ .i = std.math.cast(i32, portnum) orelse return error.BadPort });
    const m = try builder.commit(l.allocator(), "/serialosc/notify");
    defer m.unref();
    l.pop(3);
    l.newTable(); // t
    _ = l.pushString(m.toBytes()); // bytes; upvalue for the functions to add
    const funcs: [3][]const u8 = .{ "/serialosc/add", "/serialosc/device", "/serialosc/remove" };
    inline for (funcs) |name| {
        _ = l.pushString(name);
        l.pushValue(-2);
        l.pushValue(server_idx);
        osc.wrap(l, "ssi", @field(@This(), name), 2);
        l.setTable(-4);
    }
    l.pop(1);
    const serialosc_addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 12002);
    osc.pushAddress(l, .array, serialosc_addr);
    l.setField(-2, "address");
    lu.load(l, "seamstress.osc.Client");
    l.rotate(-2, 1);
    try lu.doCall(l, 1, 1); // c =  seamstress.osc.Client(t)
    osc.pushAddress(l, .string, serialosc_addr);
    l.rotate(-2, 1);
    l.setTable(server_idx); // serialosc[addr] = c

    const m2 = try builder.commit(l.allocator(), "/serialosc/list");
    defer m2.unref();
    try server.sendOSCBytes(serialosc_addr, m2.toBytes()); // send /serialosc/list
    try server.sendOSCBytes(serialosc_addr, m.toBytes()); // send /serialosc/notify
    if (builtin.mode == .Debug) std.debug.assert(l.getTop() == top);
}

const @"/serialosc/add" = @"/serialosc/device";

fn @"/serialosc/device"(l: *Lua, from: std.net.Address, path: []const u8, id: []const u8, @"type": []const u8, port: i32) z.Continue {
    if (std.mem.eql(u8, path, "/serialosc/add")) @"/serialosc/notify"(l, from);
    const is_arc = std.mem.indexOf(u8, @"type", "arc") != null; // an arc is something that calls itself an arc
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, std.math.cast(u16, port) orelse
        l.raiseErrorStr("bad port number %d", .{port}));
    osc.pushAddress(l, .string, addr); // this will be the key to the server table
    l.pushValue(-1); // duplicate the key
    const add = add: {
        if (l.getTable(Lua.upvalueIndex(2)) != .userdata) {
            l.pop(1);
            // create a new object!
            break :add true;
        } else {
            // check that the provided client matches our expectation
            if (is_arc) lu.load(l, "seamstress.monome.Arc") else lu.load(l, "seamstress.monome.Grid");
            l.pushValue(-3); // key
            if (l.getTable(-2) != .userdata) { // should be unlikely
                l.pop(3); // dev, dev_table, obj
                break :add true;
            }
            _ = l.getField(-1, "id"); // check the device's id
            _ = l.pushString(id);
            if (l.compare(-1, -2, .eq)) {
                l.pop(2);
                break :add false; // it's a match!
            }
            // it's not a match, so let's prepare to call addNew
            l.pop(5); // dev, device table, device, its id, id
            break :add true;
        }
    };
    // top of stack should be the new device
    const common = @import("monome/common.zig");
    if (add) {
        if (is_arc)
            common.addNewDevice(l, Lua.upvalueIndex(2), id, @"type", port, .arc)
        else
            common.addNewDevice(l, Lua.upvalueIndex(2), id, @"type", port, .grid);
    }
    lu.preparePublish(l, if (is_arc) &.{ "monome", "arc", "add" } else &.{ "monome", "grid", "add" });
    l.rotate(-3, -1); // publish, namespace, device
    l.call(2, 0); // publish(namespace, device)
    return .no;
}

fn @"/serialosc/remove"(l: *Lua, from: std.net.Address, _: []const u8, id: []const u8, @"type": []const u8, port: i32) z.Continue {
    @"/serialosc/notify"(l, from);
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, std.math.cast(u16, port) orelse
        l.raiseErrorStr("bad port number %d", .{port}));
    const is_arc = std.mem.indexOf(u8, @"type", "arc") != null; // an arc is something that calls itself an arc
    blk: {
        if (is_arc) lu.load(l, "seamstress.monome.Arc") else lu.load(l, "seamstress.monome.Grid");
        osc.pushAddress(l, .string, addr);
        if (l.getTable(-2) != .userdata) break :blk;
        _ = l.getField(-1, "id");
        _ = l.pushString(id);
        if (!l.compare(-1, -2, .eq)) break :blk;
        l.pop(2);
        if (is_arc) {
            const arc = l.toUserdata(@import("monome/arc.zig"), -1) catch unreachable;
            arc.connected = false;
        } else {
            const grid = l.toUserdata(@import("monome/grid.zig"), -1) catch unreachable;
            grid.connected = false;
        }
    }
    lu.preparePublish(l, if (is_arc) &.{ "monome", "arc", "remove" } else &.{ "monome", "grid", "remove" });
    _ = l.pushString(id);
    l.pushInteger(port);
    l.call(3, 0);
    return .no;
}

/// raises an error on failure
/// relies on the first upvalue being a preprepared /serialosc/notify message
/// and the serialosc server being stack index 1
/// stack effect: nothing (unless we error)
fn @"/serialosc/notify"(l: *Lua, to: std.net.Address) void {
    const idx = Lua.upvalueIndex(1); // preprepared /serialosc/notify message
    const server_idx = Lua.upvalueIndex(2);
    const server = l.toUserdata(osc.Server, server_idx) catch unreachable;
    server.sendOSCBytes(to, l.toString(idx) catch unreachable) catch |err| {
        l.raiseErrorStr("error sending /serialosc/notify message! %s", .{@errorName(err).ptr});
    };
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("osc.zig");
const lu = @import("lua_util.zig");
const z = osc.z;
const std = @import("std");
