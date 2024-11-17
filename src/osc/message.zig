pub fn register(l: *Lua) i32 {
    blk: {
        l.newMetatable("seamstress.osc.Message") catch break :blk; // new metatable
        const funcs: []const ziglua.FnReg = &.{
            .{ .name = "__index", .func = ziglua.wrap(__index) },
            .{ .name = "__newindex", .func = ziglua.wrap(__newindex) },
            .{ .name = "__gc", .func = ziglua.wrap(__gc) },
            .{ .name = "bytes", .func = ziglua.wrap(bytes) },
            .{ .name = "__eq", .func = ziglua.wrap(__eq) },
            .{ .name = "__ipairs", .func = ziglua.wrap(__ipairs) },
            .{ .name = "__len", .func = ziglua.wrap(__len) },
        };
        l.setFuncs(funcs, 0);
        // _ = l.pushString("seamstress.osc.Message");
        // _ = l.pushString("__name");
        // l.setTable(-3);
    }
    l.pop(1);
    l.pushFunction(ziglua.wrap(new));
    return 1;
}

fn __index(l: *Lua) i32 {
    const builder = l.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
    _ = l.pushStringZ("path");
    _ = l.pushStringZ("types");
    if (l.compare(2, -2, .eq)) { // k == "path"
        _ = l.getUserValue(1, 1) catch unreachable; // user value: path
        return 1;
    }
    if (l.compare(2, -1, .eq)) { // k == "types"
        var buf: ziglua.Buffer = undefined;
        _ = buf.initSize(l, builder.data.items.len);
        for (builder.data.items) |data|
            buf.addChar(@tagName(data)[0]);
        buf.pushResult(); // push the constructed typetag
        return 1;
    }
    switch (l.typeOf(2)) {
        .string => {
            _ = l.getMetatable(1) catch unreachable;
            l.pushValue(2);
            _ = l.getTable(-2);
            return 1;
        },
        .number => if (!l.isInteger(2)) l.argError(2, "integer expected"),
        else => l.argError(2, "integer expected"),
    }
    const idx = l.toInteger(2) catch unreachable;
    if (idx <= 0 or idx > std.math.cast(ziglua.Integer, builder.data.items.len) orelse 0)
        return 0; // nothing at that index!
    osc.pushData(l, builder.data.items[@intCast(idx - 1)]); // push the data
    return 1;
}

fn __newindex(l: *Lua) i32 {
    const builder = l.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
    _ = l.pushStringZ("path");
    if (l.compare(2, -1, .eq)) { // k == "path"
        l.pushValue(3); // push v
        l.setUserValue(1, 1) catch unreachable; // set the user value
        return 0;
    }
    _ = l.getMetatable(1) catch unreachable;
    l.pushValue(2);
    switch (l.getTable(-2)) {
        .nil, .none => {},
        else => return 1,
    }
    if (l.typeOf(2) != .number or !l.isInteger(2)) l.argError(2, "integer or \"path\" expected");
    const idx = l.toInteger(2) catch unreachable;
    if (idx <= 0) l.argError(2, "positive integer expected");
    if (idx > builder.data.items.len + 1) l.argError(2, "index too large!");
    l.pushValue(3); // push v
    const data = osc.toData(l, null) catch |err| switch (err) { // it should be valid data
        error.TypeMismatch => l.raiseErrorStr("OSC data types mismatched!", .{}),
        error.BadIntegerValue => l.raiseErrorStr("OSC data does not support that integer value", .{}),
        error.BadOSCArgument, error.BadTag => l.raiseErrorStr("unable to parse OSC argument", .{}),
    };
    const @"usize": usize = @intCast(idx - 1);
    if (@"usize" == builder.data.items.len) { // if we're at the end, add it
        builder.append(data) catch l.raiseErrorStr("out of memory!", .{});
        return 0;
    } else { // otherwise replace it
        builder.data.items[@"usize"] = data;
        return 0;
    }
}

fn __eq(l: *Lua) i32 {
    if (l.rawEqual(1, 2)) { // lua has quick ways of telling equality, try them first
        l.pushBoolean(true);
        return 1;
    }
    const a = l.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
    const b = l.checkUserdata(z.Message.Builder, 2, "seamstress.osc.Message");
    if (a.data.items.len != b.data.items.len) { // equal messages have the same number of arguments
        l.pushBoolean(false);
        return 1;
    }
    for (a.data.items, b.data.items) |a_d, b_d| { // each argument should be equal
        if (!a_d.eql(b_d)) {
            l.pushBoolean(false);
            return 1;
        }
    }
    _ = l.getUserValue(1, 1) catch unreachable;
    _ = l.getUserValue(2, 1) catch unreachable;
    l.pushBoolean(l.compare(-1, -2, .eq)); // and the paths should be equal
    return 1;
}

fn __gc(l: *Lua) i32 {
    const builder = l.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
    builder.deinit(); // release the ArrayList
    return 0;
}

fn __len(l: *Lua) i32 {
    const builder = l.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
    l.pushInteger(@intCast(builder.data.items.len)); // push the number of arguments
    return 1;
}

fn __ipairs(l: *Lua) i32 {
    const iteratorFn = struct {
        /// function iterator(msg, i)
        ///   local v = msg[i]
        ///   if v ~= nil then return i + 1, v end
        /// end
        fn f(lua: *Lua) i32 {
            const builder = lua.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
            const idx = lua.checkInteger(2);
            const @"usize" = std.math.cast(usize, idx - 1) orelse lua.raiseErrorStr("bad index!", .{});
            if (@"usize" > builder.data.items.len) return 0;
            lua.pushInteger(idx + 1);
            osc.pushData(lua, builder.data.items[@"usize"]);
            return 2;
        }
    }.f;
    // return iterator, msg, 1
    l.pushFunction(ziglua.wrap(iteratorFn));
    l.pushValue(1);
    l.pushInteger(1);
    return 3;
}

fn bytes(l: *Lua) i32 {
    // the first argument is self
    const builder = l.checkUserdata(z.Message.Builder, 1, "seamstress.osc.Message");
    // if the path is bad, bail
    if (l.getUserValue(1, 1) catch unreachable != .string) l.raiseErrorStr("missing or invalid OSC path!", .{});
    const path = l.toString(-1) catch unreachable;
    // build a message
    const msg = builder.commit(l.allocator(), path) catch l.raiseErrorStr("out of memory!", .{});
    // be sure to release it
    defer msg.unref();
    // return the bytes
    _ = l.pushString(msg.toBytes());
    return 1;
}

/// transforms a lua table of the form
/// { path = "/some/osc/path", types = "typetag" or nil, arg1, arg2, ... }
/// into our message type
fn new(l: *Lua) i32 {
    const arg_exists = l.getTop() != 0;
    const builder = l.newUserdata(z.Message.Builder, 1); // create a builder
    builder.* = z.Message.Builder.init(l.allocator()); // initialize
    if (arg_exists) {
        // set path
        if (l.getField(1, "path") != .string) {
            l.pop(1);
            l.pushNil();
        }
        l.setUserValue(-2, 1) catch unreachable;
        // is there a types field?
        const types: ?[]const u8 = if (l.getField(1, "types") == .string) l.toString(-1) catch unreachable else null;
        l.pop(1);
        if (types) |string| {
            var idx: ziglua.Integer = 1; // traverse the array part of the table
            for (string) |tag| { // using the typetag as the source of truth
                _ = l.getIndex(1, idx);
                defer l.pop(1);
                defer idx += 1;
                pullIn(l, builder, tag) catch |err| {
                    // we're bailing, so don't leak memory
                    builder.deinit();
                    switch (err) {
                        error.OutOfMemory => l.raiseErrorStr("out of memory!", .{}),
                        error.BadIntegerValue, error.TypeMismatch, error.BadTag, error.BadOSCArgument => l.raiseErrorStr("bad data for OSC type %s at index %d", .{ &.{ tag, 0 }, idx }),
                    }
                };
            }
        } else {
            l.len(1); // get the length
            const len = l.toInteger(-1) catch unreachable;
            l.pop(1);
            var idx: ziglua.Integer = 1; // traverse the array part of the table
            while (idx <= len) : (idx += 1) {
                _ = l.getIndex(1, idx);
                defer l.pop(1);
                pullIn(l, builder, null) catch |err| {
                    // we're bailing, so don't leak memory
                    builder.deinit();
                    switch (err) {
                        error.OutOfMemory => l.raiseErrorStr("out of memory!", .{}),
                        error.BadIntegerValue, error.TypeMismatch, error.BadTag, error.BadOSCArgument => l.raiseErrorStr("bad data for OSC at index %d", .{idx}),
                    }
                };
            }
        }
    } else { // if there are no arguments, then the path is nil
        l.pushNil();
        l.setUserValue(-2, 1) catch unreachable;
    }
    _ = l.getMetatableRegistry("seamstress.osc.Message"); // set the metatable
    l.setMetatable(-2); // and return it
    return 1;
}

/// appends the item at the top of the stack to the given builder
fn pullIn(l: *Lua, builder: *z.Message.Builder, tag: ?u8) !void {
    const data = try osc.toData(l, tag);
    try builder.append(data);
}

const z = @import("zosc");
const osc = @import("../osc.zig");
const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("../lua_util.zig");
