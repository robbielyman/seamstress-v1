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

fn dispatchInner(comptime which: enum { bytes, object }) fn (*Lua) i32 {
    return struct {
        fn inner(l: *Lua) i32 {
            const server_idx = Lua.upvalueIndex(1);
            const addr_idx = Lua.upvalueIndex(2);
            const msg_idx = Lua.upvalueIndex(3);
            const time_idx = Lua.upvalueIndex(4);
            switch (which) {
                .bytes => {
                    const parsed = z.parseOSC(l.toString(msg_idx) catch unreachable) catch l.raiseErrorStr("bad OSC data!", .{});
                    if (!z.matchPath(l.checkString(1), parsed.message.path)) {
                        l.pushBoolean(true);
                        return 1;
                    }
                },
                .object => {
                    _ = l.getField(msg_idx, "path");
                    const path = l.toString(-1) catch unreachable;
                    if (!z.matchPath(l.checkString(1), path)) {
                        l.pushBoolean(true);
                        return 1;
                    }
                },
            }
            l.pushValue(2);
            l.pushValue(server_idx);
            l.pushValue(addr_idx);
            l.pushValue(msg_idx);
            l.pushValue(time_idx);
            l.call(4, 1);
            return 1;
        }
    }.inner;
}

fn dispatch(l: *Lua) i32 {
    const client = l.checkUserdata(Client, 1, "seamstress.osc.Client");
    const time_exists = l.typeOf(5) != .none;
    const addr = if (l.typeOf(4) == .none) client.addr else osc.parseAddress(l, 4) catch
        l.typeError(4, "address");
    l.pushNil();
    const bytes_fn = l.getTop();
    l.pushNil();
    const obj_fn = l.getTop();
    var bytes_fn_prepped, var obj_fn_prepped = blk: {
        switch (l.typeOf(3)) {
            .string => {
                l.pushValue(1);
                osc.pushAddress(l, .array, addr);
                l.pushValue(3);
                if (time_exists) l.pushValue(5) else l.pushNil();
                l.pushClosure(ziglua.wrap(dispatchInner(.bytes)), 4);
                l.replace(bytes_fn);
                break :blk .{ true, false };
            },
            .table => {
                lu.load(l, "seamstress.osc.Message") catch unreachable;
                l.pushValue(3);
                l.call(1, 1);
                l.replace(3);
            },
            .userdata => {},
            else => l.typeError(3, "seamstress.osc.Message"),
        }
        l.pushValue(1);
        osc.pushAddress(l, .array, addr);
        l.pushValue(3);
        if (time_exists) l.pushValue(5) else l.pushNil();
        l.pushClosure(ziglua.wrap(dispatchInner(.object)), 4);
        l.replace(obj_fn);
        break :blk .{ false, true };
    };
    _ = obj_fn_prepped; // autofix
    _ = bytes_fn_prepped; // autofix
}

fn dispatch(l: *Lua) i32 {
    const client = l.checkUserdata(Client, 1, "seamstress.osc.Client");
    const addr = if (l.typeOf(4) == .none) client.addr else osc.parseAddress(l, 4) catch
        l.typeError(4, "address");
    const time_exists = l.typeOf(5) != .none;
    const msg_idx, const bytes_idx, const bytes, var msg_created = blk: {
        const msg_idx = switch (l.typeOf(3)) {
            .string => {
                l.pushNil();
                const msg_idx = l.getTop();
                const bytes = l.toString(3) catch unreachable;
                break :blk .{ msg_idx, 3, bytes, false };
            },
            .table => msg_idx: {
                lu.load(l, "seamstress.osc.Message") catch unreachable;
                l.pushValue(3);
                l.call(1, 1);
                break :msg_idx l.getTop();
            },
            .userdata => 3,
            else => l.typeError(3, "seamstress.osc.Message"),
        };
        _ = l.getMetaField(msg_idx, "bytes") catch unreachable;
        l.pushValue(msg_idx);
        l.call(1, 1);
        const bytes = l.toString(-1) catch unreachable;
        const bytes_idx = l.getTop();
        break :blk .{ msg_idx, bytes_idx, bytes, true };
    };
    var parsed = z.parseOSC(bytes) catch l.raiseErrorStr("bad OSC data", .{});
    switch (parsed) {
        .bundle => |*iter| {
            while (iter.next() catch l.raiseErrorStr("bad OSC data", .{})) |msg| {
                _ = l.getMetaField(1, "dispatch") catch unreachable;
                l.pushValue(1);
                l.pushValue(2);
                _ = l.pushString(msg);
                l.pushValue(4);
                osc.pushData(l, .{ .t = iter.time });
                lu.doCall(l, 5, 1) catch lu.reportError(l);
            }
        },
        .message => |*iter| {
            _ = l.getMetaField(1, "__pairs") catch unreachable;
            l.pushValue(1);
            l.call(1, 3);
            while (true) {
                l.pushValue(-3); // iterator function
                l.pushValue(-3); // state
                l.rotate(-3, 1); // stack now is function state key
                l.call(2, 2); // key, val = function(state, key)
                if (!lu.isCallable(l, -1)) break; // if val is not a function, we're done
                const key = l.toString(-2) catch l.raiseError(); // key should always be a string
                if (!z.matchPath(key, iter.path)) { // match the key against our message
                    l.pop(1);
                    continue;
                }
                const top = l.getTop();
                defer l.setTop(top - 1); // end by popping the function
                l.pushValue(-1); // duplicate the function in case we need to call it again
                l.pushValue(2); // server
                osc.pushAddress(l, .array, addr); // address
                l.pushValue(bytes_idx); // bytes
                if (time_exists) l.pushValue(5); // timetag
                lu.doCall(l, if (time_exists) 4 else 3, 1) catch {
                    // try again with message as a lua table
                    if (!msg_created) {
                        msg_created = true;
                        osc.pushMessage(l, iter) catch l.raiseErrorStr("invalid OSC!", .{});
                        l.insert(msg_idx);
                    }
                    l.pushValue(2); // server
                    osc.pushAddress(l, .array, addr); // address
                    l.pushValue(msg_idx);
                    if (time_exists) l.pushValue(5);
                    lu.doCall(l, if (time_exists) 4 else 3, 1) catch {
                        lu.reportError(l);
                        continue; // keep going on error seems reasonable
                    };
                    const keep_going = l.toBoolean(-1);
                    if (!keep_going) break;
                    l.pop(1);
                    continue;
                }; // continue = function(server, address, bytes, timetag)
                const keep_going = l.toBoolean(-1);
                if (!keep_going) break;
            }
        },
    }
    return 0;
}

fn new(l: *Lua) i32 {
    switch (l.typeOf(1)) {
        .table => {
            _ = l.getField(1, "address"); // fetch the address field
            const addr = osc.parseAddress(l, -1) catch std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0);
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
            if (!lua.next(1)) return 0;
            while (!lu.isCallable(lua, -1) or !lua.isString(-2)) {
                lua.pop(1);
                if (!lua.next(1)) return 0;
            }
            return 2;
        }
    }.f;
    // return iterator, tbl, nil
    l.pushFunction(ziglua.wrap(iterator));
    _ = l.getUserValue(1, 1) catch unreachable;
    l.pushNil();
    return 3;
}

const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const osc = @import("../osc.zig");
const lu = @import("../lua_util.zig");
const z = @import("zosc");
