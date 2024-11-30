pub fn register(l: *Lua) i32 {
    blk: {
        l.newMetatable("seamstress.osc.Client") catch break :blk;
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(__index) },
            .{ .name = "__newindex", .func = ziglua.wrap(__newindex) },
            .{ .name = "__pairs", .func = ziglua.wrap(__pairs) },
            .{ .name = "dispatch", .func = ziglua.wrap(dispatch) },
        };
        l.setFuncs(funcs, 0);
    }
    l.pop(1);
    l.pushFunction(ziglua.wrap(new));
    return 1;
}

const Client = @This();

addr: std.net.Address,

fn dispatchWhich(l: *Lua, comptime which: enum { bytes, msg }) void {
    l.setTop(5); // client, msg (passed), address, time, nil
    _ = l.pushStringZ("seamstress.osc.Method");
    const path = switch (which) {
        .bytes => path: {
            const bytes = l.toString(2) catch unreachable;
            break :path switch (z.parseOSC(bytes) catch l.raiseErrorStr("bad OSC data!", .{})) {
                .bundle => unreachable,
                .message => |m| m.path,
            };
        },
        .msg => path: {
            _ = l.getField(2, "path");
            const path = l.toString(-1) catch unreachable;
            l.pop(1);
            break :path path;
        },
    };
    const addr = switch (l.typeOf(3)) {
        .nil, .none => addr: {
            const client = l.checkUserdata(Client, 1, "seamstress.osc.Client");
            break :addr client.addr;
        },
        else => osc.parseAddress(l, 3) catch l.typeError(3, "address"),
    };
    osc.pushAddress(l, .array, addr);
    l.replace(3);
    _ = l.getMetaField(1, "__pairs") catch unreachable;
    l.pushValue(1);
    l.call(1, 3); // next, tbl, key
    const key = l.getTop();
    const next = key - 2;
    const tbl = key - 1;
    while (true) {
        defer l.setTop(key);
        l.pushValue(next);
        l.pushValue(tbl);
        l.pushValue(key);
        l.call(2, 2); // next_key, val
        l.copy(-2, key); // set the next key
        if (l.typeOf(key) == .nil) return; // we're done!
        const pattern = l.toString(key) catch unreachable;
        if (!z.matchPath(pattern, path)) continue;
        switch (l.typeOf(-1)) {
            .nil, .none => return, // we're done!
            .table => blk: {
                _ = l.getMetaField(-1, "__name") catch {
                    l.pop(1);
                    break :blk;
                };
                if (!l.compare(-1, 6, .eq)) {
                    l.pop(1);
                    break :blk;
                }
                // we're looking at a seamstress.osc.Method; we must call it with bytes
                l.pop(1);
                switch (which) {
                    .bytes => l.pushValue(2), // message (bytes)
                    .msg => {
                        if (l.typeOf(5) == .nil) {
                            // we have to create the bytes
                            const msg = l.checkUserdata(z.Message.Builder, 2, "seamstress.osc.Message");
                            const m = msg.commit(lu.allocator(l), path) catch l.raiseErrorStr("out of memory!", .{});
                            defer m.unref();
                            _ = l.pushString(m.toBytes());
                            l.replace(5);
                            l.pop(1); // pop path
                        }
                        l.pushValue(5); // message (bytes)
                    },
                }
                l.pushValue(3); // address
                l.pushValue(4); // time
                lu.doCall(l, 3, 1) catch {
                    lu.reportError(l);
                    continue;
                };
                if (!l.toBoolean(-1)) return else continue; // we're done!
            },
            else => {},
        }
        // we're looking at another kind of handler; we must call it with a message
        switch (which) {
            .bytes => {
                if (l.typeOf(5) == .nil) {
                    // we have to create the message
                    const bytes = l.toString(2) catch unreachable;
                    var msg = switch (z.parseOSC(bytes) catch l.raiseErrorStr("bad OSC data!", .{})) {
                        .bundle => unreachable,
                        .message => |m| m,
                    };
                    osc.pushMessage(l, &msg) catch l.raiseErrorStr("bad OSC data!", .{});
                    l.replace(5);
                }
                l.pushValue(5); // message (userdata)
            },
            .msg => l.pushValue(2), // message (userdata)
        }
        l.pushValue(3); // address
        l.pushValue(4); // time
        lu.doCall(l, 3, 1) catch {
            lu.reportError(l);
            continue;
        };
        if (!l.toBoolean(-1)) return; // we're done!
    }
}

/// function seamstress.osc.Client:dispatch(msg, [addr, time])
fn dispatch(l: *Lua) i32 {
    if (l.typeOf(3) == .none) l.setTop(3);
    const t = l.typeOf(2);
    // if we get a bundle, recurse
    if (t == .string) {
        var parsed = z.parseOSC(l.toString(2) catch unreachable) catch
            l.raiseErrorStr("bad OSC data", .{});
        switch (parsed) {
            .bundle => |*iter| {
                while (iter.next() catch l.raiseErrorStr("bad OSC data", .{})) |msg| {
                    _ = l.getMetaField(1, "dispatch") catch unreachable;
                    l.pushValue(1);
                    _ = l.pushString(msg);
                    l.pushValue(3);
                    osc.pushData(l, .{ .t = iter.time });
                    lu.doCall(l, 4, 0) catch lu.reportError(l);
                }
                return 0;
            },
            // nothing here so we fall through to the rest of the function
            .message => {},
        }
        dispatchWhich(l, .bytes);
        return 0;
    }

    if (t == .table) {
        lu.load(l, "seamstress.osc.Message");
        l.pushValue(2);
        l.call(1, 1);
        l.replace(2);
    }

    dispatchWhich(l, .msg);
    return 0;
}

fn new(l: *Lua) i32 {
    switch (l.typeOf(1)) {
        .table => {
            _ = l.getField(1, "address"); // fetch the address field
            const addr = osc.parseAddress(l, -1) catch std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0);
            l.pop(1);
            _ = l.getField(1, "default");
            if (!lu.isCallable(l, -1)) {
                l.pushFunction(ziglua.wrap(default));
                l.setField(1, "default");
            }
            l.pop(1);
            const client = l.newUserdata(Client, 2); // create the userdata
            client.* = .{ .addr = addr };
            l.pushValue(1); // assign the table as the uservalue
            l.setUserValue(-2, 1) catch unreachable;
        },
        .nil, .none => {
            const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0); // default address
            const client = l.newUserdata(Client, 2); // create the userdata
            client.* = .{ .addr = addr };
            l.newTable(); // create a new table for the uservalue
            l.pushFunction(ziglua.wrap(default));
            l.setField(-2, "default");
            l.setUserValue(-2, 1) catch unreachable;
        },
        else => l.typeError(1, "table"),
    }
    _ = l.getMetatableRegistry("seamstress.osc.Client");
    l.setMetatable(-2);
    return 1;
}

fn __index(l: *Lua) i32 {
    const client = l.checkUserdata(Client, 1, "seamstress.osc.Client");
    _ = l.pushStringZ("address");
    if (l.compare(2, -1, .eq)) { // k == "address"
        osc.pushAddress(l, .array, client.addr);
        return 1;
    }
    l.getMetatable(1) catch unreachable;
    l.pushValue(2);
    switch (l.getTable(-2)) { // does the metatable have this key?
        .nil, .none => { // no, so check thet data table
            _ = l.getUserValue(1, 1) catch unreachable;
            l.pushValue(2);
            _ = l.getTable(-2);
            return 1;
        },
        else => return 1, // great, return it
    }
}

fn __newindex(l: *Lua) i32 {
    _ = l.pushStringZ("default");
    if (l.compare(2, -1, .eq)) {
        switch (l.typeOf(3)) {
            .table, .function, .userdata => {
                lu.checkCallable(l, 3);
            },
            else => l.typeError(3, "function"),
        }
        l.pushValue(3);
        l.setUserValue(1, 2) catch unreachable;
        return 0;
    }
    const key = l.checkString(2);
    l.argCheck(key[0] == '/', 2, "OSC path pattern expected");
    switch (l.typeOf(3)) {
        .table, .function, .userdata => {
            lu.checkCallable(l, 3);
        },
        else => l.typeError(3, "function"),
    }
    _ = l.getUserValue(1, 1) catch unreachable; // this is t
    l.pushValue(2); // k
    l.pushValue(3); // v
    l.setTable(-3); // t[k] = v
    return 0;
}

fn __pairs(l: *Lua) i32 {
    const iterator = struct {
        fn f(lua: *Lua) i32 {
            _ = lua.pushStringZ("default");
            const default_str = lua.getTop();
            while (true) {
                lua.pushValue(2);
                if (!lua.next(1)) return 0;
                if (lua.compare(default_str, -2, .eq)) {
                    lua.pop(1); // remove val
                    lua.replace(2); // replace key
                    continue;
                }
                if (!lu.isCallable(lua, -1)) {
                    lua.pop(1); // remove val
                    lua.replace(2); // replace key
                    continue;
                }
                if (!lua.isString(-2)) {
                    lua.pop(1); // remove val
                    lua.replace(2); // replace key
                    continue;
                }
                return 2;
            }
        }
    }.f;
    // return iterator, tbl, nil
    l.pushFunction(ziglua.wrap(iterator));
    _ = l.getUserValue(1, 1) catch unreachable;
    l.pushNil();
    return 3;
}

fn default(l: *Lua) i32 {
    _ = l.getField(2, "path");
    const path = l.toString(-1) catch unreachable;
    var iter = std.mem.tokenizeScalar(u8, path, '/');
    // we don't use prepare publish because it duplicates the work
    lu.load(l, "seamstress.event");
    _ = l.getField(-1, "publish"); // publish
    var index: ziglua.Integer = index: {
        // messages starting with "/seamstress" result in events without prepended "/seamstress"
        // messages without "/seamstress" instead are namespaced under "osc"
        if (std.mem.eql(u8, "seamstress", iter.peek() orelse return 0)) {
            _ = iter.next();
            l.newTable(); // t
            break :index 1;
        }
        l.newTable();
        _ = l.pushStringZ("osc");
        l.setIndex(-2, 1);
        break :index 2;
    };
    while (iter.next()) |component| {
        _ = l.pushString(component);
        l.setIndex(-2, index);
        index += 1;
    }
    l.pushValue(1); // addr
    l.pushValue(2); // msg
    l.pushValue(3); // time
    l.call(4, 0); // publish(t, addr, msg, time)
    l.pushBoolean(true);
    return 1; // return true
}

const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const lu = @import("../lua_util.zig");
const z = @import("zosc");
