pub fn register(comptime which: enum { monome, grid, arc }) fn (*Lua) i32 {
    return switch (which) {
        .monome => struct {
            fn f(l: *Lua) i32 {
                lu.load(l, "seamstress.osc.Server") catch unreachable;
                const realLoader = struct {
                    fn f(lua: *Lua) i32 {
                        const id = Lua.upvalueIndex(1);
                        lua.createTable(0, 3);
                        lua.pushValue(id);
                        lua.pushValue(1);
                        lu.doCall(lua, 1, 1) catch lua.raiseErrorStr("unable to create serialosc server!", .{});
                        populateSerialoscServer(lua) catch lua.raiseError();
                        lua.setField(-2, "serialosc");
                        lu.load(lua, "seamstress.monome.Grid") catch unreachable;
                        lua.setField(-2, "Grid");
                        lu.load(lua, "seamstress.monome.Arc") catch unreachable;
                        lua.setField(-2, "Arc");
                        return 1;
                    }
                }.f;
                l.pushClosure(ziglua.wrap(realLoader), 1);
                return 1;
            }
        }.f,
        .grid => @import("monome/grid.zig").register,
        .arc => @import("monome/arc.zig").register,
    };
}

fn populateSerialoscServer(l: *Lua) !void {
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
    const funcs: []const ziglua.FnReg = &.{
        .{ .name = "/serialosc/add", .func = ziglua.wrap(osc.wrap(@"/serialosc/add")) },
        .{ .name = "/serialosc/device", .func = ziglua.wrap(osc.wrap(@"/serialosc/device")) },
        .{ .name = "/serialosc/remove", .func = ziglua.wrap(osc.wrap(@"/serialosc/remove")) },
    };
    l.setFuncs(funcs, 1);
    const serialosc_addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 12002);
    osc.pushAddress(l, .array, serialosc_addr);
    l.setField(-2, "address");
    try lu.doCall(l, 1, 1); // seamstress.osc.Client(t)
    const m2 = try builder.commit(l.allocator(), "/serialosc/list");
    defer m2.unref();
    _ = l.pushString(m2.toBytes());
    l.pushClosure(ziglua.wrap(@"/serialosc/list"), 1);
    l.pushValue(server_idx);
    osc.pushAddress(l, .string, serialosc_addr);
    try lu.doCall(l, 2, 0);
}

const @"/serialosc/add" = @"/serialosc/device";

fn @"/serialosc/device"(l: *Lua, msg: *z.Parse.MessageIterator, from: std.net.Address) z.Continue {
    // FIXME: this never runs if we raise a Lua error... is that ok?
    defer if (std.mem.eql(u8, msg.path, "/serialosc/add")) @"/serialosc/notify"(l, from);
    if (!std.mem.eql(u8, "ssi", msg.types)) // check the types: must be 'ssi'
        l.raiseErrorStr("bad argument types for %s: %s", .{
            @as([*:0]const u8, @ptrCast(msg.path.ptr)),
            @as([*:0]const u8, @ptrCast(msg.types.ptr)), // should this be part of zOSC?
        });
    const id = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.s;
    const @"type" = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.s;
    const port = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, std.math.cast(u16, port) orelse
        l.raiseErrorStr("bad port number %d", .{port}));
    osc.pushAddress(l, .string, addr); // this will be the key to the server table
    l.pushValue(-1); // duplicate the key
    if (l.getTable(1) != .userdata) {
        l.pop(1);
        // create a new object!
        return addNewDevice(l, id, @"type", port);
    } else {
        // check that the provided client matches our expectation
        if (std.mem.indexOf(u8, @"type", "arc")) |_| // an arc is something that calls itself an arc
            lu.load(l, "seamstress.monome.Arc") catch unreachable
        else
            lu.load(l, "seamstress.monome.Grid") catch unreachable;
        l.pushValue(-2); // key
        if (l.getTable(-2) != .userdata) { // should be unlikely
            l.pop(2); // need key to be at the top of the stack to call addNew
            return addNewDevice(l, id, @"type", port);
        }
        _ = l.getField(-1, "id"); // check the device's id
        _ = l.pushString(id);
        if (l.compare(-1, -2, .eq)) return .no; // it's a match!
        // it's not a match, so let's prepare to call addNew
        l.pop(4); // device table, device, its id, id
        return addNewDevice(l, id, @"type", port);
    }
}

fn @"/serialosc/remove"(l: *Lua, msg: *z.Parse.MessageIterator, from: std.net.Address) z.Continue {
    // FIXME: this never runs if we raise a Lua error: is that fine?
    @"/serialosc/notify"(l, from);
    if (!std.mem.eql(u8, "ssi", msg.types)) // check the types: must be 'ssi'
        l.raiseErrorStr("bad argument types for %s: %s", .{
            @as([*:0]const u8, @ptrCast(msg.path.ptr)),
            @as([*:0]const u8, @ptrCast(msg.types.ptr)), // should this be part of zOSC?
        });
    const id = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.s;
    const @"type" = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.s;
    const port = (msg.next() catch l.raiseErrorStr("bad OSC data!", .{})).?.i;
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, std.math.cast(u16, port) orelse
        l.raiseErrorStr("bad port number %d", .{port}));
    if (std.mem.indexOf(u8, @"type", "arc")) |_| // an arc is something that calls itself an arc
        lu.load(l, "seamstress.monome.Arc") catch unreachable
    else
        lu.load(l, "seamstress.monome.Grid") catch unreachable;
    osc.pushAddress(l, .string, addr);
    if (l.getTable(-2) != .userdata) return .no;
    _ = l.getField(-1, "id");
    _ = l.pushString(id);
    if (!l.compare(-1, -2, .eq)) return .no;
    l.pushBoolean(false);
    l.setField(-3, "connected");
    return .no;
}

/// assumes that the top of the stack is a string key representing the address
/// and that stack index 1 is the server
/// stack effec: -1 (consumes key)
fn addNewDevice(l: *Lua, id: []const u8, @"type": []const u8, port: i32) z.Continue {
    if (std.mem.indexOf(u8, @"type", "arc")) |_| // an arc is something that calls itself an arc
        lu.load(l, "seamstress.monome.Arc") catch unreachable
    else
        lu.load(l, "seamstress.monome.Grid") catch unreachable;
    l.pushValue(-1); // duplicate the table
    l.rotate(-3, 1); // top of stack is now: seamstress.osc.[Arc|Grid], key, seamstress.osc.[Arc|Grid]
    l.pushValue(1); // server
    _ = l.pushString(id); // id
    _ = l.pushString(@"type"); // type
    l.pushInteger(port); // port
    l.call(4, 1); // dev = seamstress.osc.[Arc|Grid](server, id, type, port)
    l.rotate(-2, 1); // top of stack is now: dev, key
    _ = l.getField(-2, "client"); // dev.client
    l.setTable(1); // server[key] = dev.client
    l.len(-2); // #seamstress.osc.[Arc|Grid]
    const idx = l.toInteger(-1) catch unreachable;
    l.pop(1);
    l.setIndex(-2, idx + 1); // seamstress.osc.[Arc|Grid][#seamstress.osc.[Arc|Grid] + 1] = arc
    return .no; // we're done!
}

/// raises an error on failure
/// relies on the first upvalue being a preprepared /serialosc/notify message
/// and the serialosc server being stack index 1
/// stack effect: nothing (unless we error)
fn @"/serialosc/notify"(l: *Lua, to: std.net.Address) void {
    const idx = Lua.upvalueIndex(1); // preprepared /serialosc/notify message
    const server = l.checkUserdata(osc.Server, 1, "seamstress.osc.Server");
    server.sendOSCBytes(to, l.toString(idx) catch unreachable) catch |err| {
        _ = l.pushFString("error sending /serialosc/notify message! %s", .{@errorName(err).ptr});
        l.raiseError();
    };
}

/// raises an error on failure
/// relies on the first upvalue being a preprepared /serialosc/list message
/// stack effect: nothing (unless we error)
fn @"/serialosc/list"(l: *Lua) i32 {
    const idx = Lua.upvalueIndex(1); // preprepared /serialosc/list message
    const server = l.checkUserdata(osc.Server, 1, "seamstress.osc.Server");
    const to = osc.parseAddress(l, 2) catch l.raiseError();
    server.sendOSCBytes(to, l.toString(idx) catch unreachable) catch |err| {
        _ = l.pushFString("error sending /serialosc/list message! %s", .{@errorName(err).ptr});
        l.raiseError();
    };
    return 0;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("osc.zig");
const lu = @import("lua_util.zig");
const z = osc.z;
const std = @import("std");
