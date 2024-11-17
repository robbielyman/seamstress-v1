/// iterates over the integer keys of the table at the top of the stack,
/// returns the first one whose first UserValue is nil
/// stack effect: +1
fn findOrCreateDevice(l: *Lua) void {
    l.len(-1); // get the length
    const len = l.toInteger(-1) catch unreachable;
    l.pop(1); // pop length
    var idx: ziglua.Integer = 1;
    while (idx <= len) : (idx += 1) {
        if (l.getIndex(-1, idx) != .userdata) { // only userdata have uservalues
            l.pop(1);
            continue;
        }
        if ((l.getUserValue(-1, 1) catch unreachable) != .table) { // is the uservalue empty?
            l.pop(2);
            continue;
        }
        l.pop(1); // if so, leave the device at the top of the stack
        return;
    }
    // if we got here, we need to create a new device
    l.pushValue(-1); // duplicate the table
    l.call(0, 1); // call it to create a new device
    l.pushValue(-1); // duplicate the device
    l.setIndex(-3, len + 1); // assign the copy to the table
    // leave the device at the top of the stack
}

/// assumes that the top of the stack is a string key representing the address
/// stack effect: -1 (consumes key)
pub fn addNewDevice(l: *Lua, server_idx: i32, id: []const u8, @"type": []const u8, port: i32, comptime which: enum { grid, arc }) void {
    const key_idx = l.getTop();
    switch (which) {
        .grid => lu.load(l, "seamstress.monome.Grid"),
        .arc => lu.load(l, "seamstress.monome.Arc"),
    }
    findOrCreateDevice(l); // dev
    l.newTable(); // uservalue
    switch (which) {
        .grid => {
            const grid = @import("grid.zig");
            createClient(l, id, @"type", port, l.getTop() - 1, grid.Decls, grid.DeclsTypes); // client
        },
        .arc => {
            const arc = @import("arc.zig");
            createClient(l, id, @"type", port, l.getTop() - 1, arc.Decls, arc.DeclsTypes); // client
        },
    }
    l.pushValue(key_idx); // key
    l.pushValue(-2); // client
    l.setTable(server_idx); // server[key] = client
    l.setField(-2, "client"); // dev.client = client
    l.pushValue(server_idx); // server
    l.setField(-2, "server"); // dev.server = server
    osc.pushAddress(l, .array, std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 0));
    l.setField(-2, "destination");
    l.setUserValue(-2, 1) catch unreachable;
    l.pushValue(key_idx); // key
    l.pushValue(-2); // dev
    l.setTable(key_idx + 1); // seamstress.monome.[Arc|Grid][key] = dev
    const connected = switch (which) {
        .grid => connected: {
            const grid = l.toUserdata(@import("grid.zig"), -1) catch unreachable;
            break :connected grid.connected;
        },
        .arc => connected: {
            const arc = l.toUserdata(@import("arc.zig"), -1) catch unreachable;
            break :connected arc.connected;
        },
    };
    if (connected) {
        _ = l.getField(-1, "connect"); // connect
        l.pushValue(-2);
        l.call(1, 0); // dev:connect()
    }
    // leave dev on top of the stack
}

/// uses the arguments provided to create a seamstress.osc.Client
fn createClient(
    l: *Lua,
    id: []const u8,
    @"type": []const u8,
    port: i32,
    dev_idx: i32,
    comptime decls: type,
    comptime map: std.StaticStringMap([]const u8),
) void {
    lu.load(l, "seamstress.osc.Client");
    l.newTable(); // the argument: t
    const info = @typeInfo(decls);
    inline for (info.Struct.decls) |decl| {
        _ = l.pushString(decl.name); // name
        l.pushValue(dev_idx);
        const arg_types = comptime map.get(decl.name) orelse @compileError("unexpected name!");
        osc.wrap(l, arg_types, @field(decls, decl.name), 1); // consumes dev, creates fn
        l.setTable(-3); // t[name] = fn
    }
    _ = l.pushString(id);
    l.setField(-2, "id");
    _ = l.pushString(@"type");
    l.setField(-2, "type");
    l.pushInteger(port);
    l.setField(-2, "address");
    l.call(1, 1); // return seamstress.osc.Client(t)
}

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
            _ = l.pushStringZ("connected");
            if (l.compare(-1, 2, .eq)) {
                l.pushBoolean(switch (which) {
                    .grid => connected: {
                        const grid = l.checkUserdata(@import("grid.zig"), 1, "seamstress.monome.Grid");
                        break :connected grid.connected;
                    },
                    .arc => connected: {
                        const arc = l.checkUserdata(@import("arc.zig"), 1, "seamstress.monome.Arc");
                        break :connected arc.connected;
                    },
                });
                return 1;
            }
            nil: {
                switch (l.getUserValue(1, 1) catch unreachable) {
                    .nil, .none => break :nil,
                    else => {},
                }
                l.pushValue(2);
                switch (l.getTable(-2)) {
                    .nil, .none => break :nil,
                    else => return 1,
                }
            }
            l.getMetatable(1) catch unreachable;
            l.pushValue(2);
            _ = l.getTable(-2);
            return 1;
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
            const maybe_server = getServer(l, 1);
            if (which == .grid) if (l.compare(2, -1, .eq)) {
                const server = maybe_server orelse return 0;
                const rotation = l.checkInteger(3);
                const grid = l.checkUserdata(@import("grid.zig"), 1, "seamstress.monome.Grid");
                grid.rotation = switch (rotation) {
                    0 => .zero,
                    1, 90 => .ninety,
                    2, 180 => .one_eighty,
                    3, 270 => .two_seventy,
                    else => l.raiseErrorStr("rotation must be 0, 90, 180 or 270", .{}),
                };
                _ = l.getField(1, "client");
                const client = l.toUserdata(osc.Client, -1) catch unreachable;
                const rot: i32 = switch (grid.rotation) {
                    .zero => 0,
                    .ninety => 90,
                    .one_eighty => 180,
                    .two_seventy => 270,
                };
                const msg = osc.z.Message.fromTuple(l.allocator(), "/sys/rotation", .{rot}) catch
                    l.raiseErrorStr("out of memory!", .{});
                defer msg.unref();
                server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
                    msg.unref();
                    l.raiseErrorStr("error sending /sys/rotation: %s", .{@errorName(err).ptr});
                };
                return 0;
            };
            _ = l.pushString("prefix");
            if (l.compare(2, -1, .eq)) {
                const server = maybe_server orelse return 0;
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
                const actual_prefix = l.toString(-1) catch unreachable;
                l.pushValue(-1);
                l.rotate(-4, 1);
                l.setTable(-3);
                _ = l.getField(1, "client");
                const client = l.toUserdata(osc.Client, -1) catch unreachable;
                const msg = osc.z.Message.fromTuple(l.allocator(), "/sys/prefix", .{actual_prefix}) catch
                    l.raiseErrorStr("out of memory!", .{});
                defer msg.unref();
                server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
                    msg.unref();
                    l.raiseErrorStr("error sending /sys/prefix: %s", .{@errorName(err).ptr});
                };
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
            _ = l.getField(1, "connected");
            if (!l.toBoolean(-1)) return 0;
            const reps = if (which == .grid) 1 else 4;
            for (0..reps) |i| {
                _ = l.getField(1, "server");
                _ = l.getField(-1, "send");
                l.pushValue(-2);
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
pub fn @"/sys/info"(l: *Lua) i32 {
    const server = getServer(l, 1) orelse return 0;
    _ = l.getField(1, "client");
    const client = l.toUserdata(osc.Client, -1) catch unreachable;
    osc.pushAddress(l, .array, server.addr); // t = {host, port}
    _ = l.getIndex(-1, 1);
    const host = l.toString(-1) catch unreachable;
    _ = l.getIndex(-2, 2);
    const port: i32 = @intCast(l.toInteger(-1) catch unreachable);
    const msg = osc.z.Message.fromTuple(l.allocator(), "/sys/info", .{ host, port }) catch
        l.raiseErrorStr("out of memory!", .{});
    defer msg.unref();
    server.sendOSCBytes(client.addr, msg.toBytes()) catch |err| {
        msg.unref();
        l.raiseErrorStr("error sending /sys/info: %s", .{@errorName(err).ptr});
    };
    return 0;
}

pub fn @"/sys/port"(l: *Lua, _: std.net.Address, _: []const u8, port: i32) osc.z.Continue {
    const dev_idx = Lua.upvalueIndex(1);
    const server = getServer(l, dev_idx).?;
    _ = l.getField(dev_idx, "destination");
    _ = l.pushInteger(port);
    l.setIndex(-2, 2);
    const addr = osc.parseAddress(l, -1) catch l.raiseErrorStr("bad OSC data!", .{});
    _ = l.getUserValue(dev_idx, 1) catch unreachable;
    l.pushBoolean(server.addr.eql(addr));
    l.setField(-2, "connected");
    return .no;
}

pub fn @"/sys/host"(l: *Lua, _: std.net.Address, _: []const u8, host: []const u8) osc.z.Continue {
    const dev_idx = Lua.upvalueIndex(1);
    const server = getServer(l, dev_idx).?;
    _ = l.getField(dev_idx, "destination");
    _ = l.pushString(host);
    l.setIndex(-2, 1);
    const addr = osc.parseAddress(l, -1) catch l.raiseErrorStr("bad OSC data!", .{});
    _ = l.getUserValue(dev_idx, 1) catch unreachable;
    l.pushBoolean(server.addr.eql(addr));
    l.setField(-2, "connected");
    return .no;
}

pub fn @"/sys/prefix"(l: *Lua, _: std.net.Address, _: []const u8, prefix: []const u8) osc.z.Continue {
    const dev_idx = Lua.upvalueIndex(1);
    _ = l.getUserValue(dev_idx, 1) catch unreachable;
    _ = l.pushString(prefix);
    l.setField(-2, "prefix");
    return .no;
}

fn getServer(l: *Lua, dev: i32) ?*osc.Server {
    defer l.pop(1);
    if ((l.getUserValue(dev, 1) catch return null) != .table) return null;
    _ = l.getField(-1, "server");
    defer l.pop(1);
    return l.toUserdata(osc.Server, -1) catch null;
}

pub fn connect(comptime which: enum { grid, arc }) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            switch (which) {
                .grid => {
                    const grid = l.checkUserdata(@import("grid.zig"), 1, "seamstress.monome.Grid");
                    grid.connected = true;
                },
                .arc => {
                    const arc = l.checkUserdata(@import("arc.zig"), 1, "seamstress.monome.Arc");
                    arc.connected = true;
                },
            }
            const server = getServer(l, 1) orelse return 0;
            _ = l.getField(1, "client");
            const client = l.toUserdata(osc.Client, -1) catch unreachable;
            osc.pushAddress(l, .array, server.addr);
            _ = l.getIndex(-1, 1);
            const host = l.toString(-1) catch unreachable;
            _ = l.getIndex(-2, 2);
            const port = l.toInteger(-1) catch unreachable;
            {
                const msg = osc.z.Message.fromTuple(l.allocator(), "/sys/host", .{host}) catch
                    l.raiseErrorStr("out of memory!", .{});
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
            if (which == .arc) {
                l.createTable(4, 0); // create arc led data
                lu.load(l, "seamstress.osc.Message"); // each datum is a seamstress.osc.Message
                var i: i32 = 1;
                while (i <= 4) : (i += 1) {
                    l.pushValue(-1); // push the function
                    l.call(0, 1); // call it
                    const builder = l.toUserdata(osc.z.Message.Builder, -1) catch unreachable; // the result is a Builder
                    const arr = builder.data.addManyAsArray(builder.allocator, 65) catch l.raiseErrorStr("out of memory!", .{}); // add 64 elements
                    @memset(arr, .{ .i = 0 }); // all of which are 0-valued integers
                    l.setIndex(-3, i); // assign it to the new table
                }
                l.pop(1); // pop the seamstress.osc.Message function
                l.setUserValue(1, 2) catch unreachable; // assign the new table
            }
            _ = l.getField(1, "info");
            l.pushValue(1);
            l.call(1, 0);
            return 0;
        }
    }.f;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const std = @import("std");
const lu = @import("../lua_util.zig");
