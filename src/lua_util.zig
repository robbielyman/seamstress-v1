/// a collection of useful functions for modules to use when interacting with Lua
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Wheel = @import("wheel.zig");
const std = @import("std");
const panic = std.debug.panic;

/// checks that the function has exactly the specified number of arguments
pub fn checkNumArgs(l: *Lua, n: i32) void {
    if (l.getTop() != n) l.raiseErrorStr("error: requires %d arguments", .{n});
}

/// registers a closure as seamstress.field_name or seamstress.submodule.field_name
/// we're using closures instead of global state!
/// makes me feel fancy
/// the closure has one "upvalue" in Lua terms: ptr
pub fn registerSeamstress(l: *Lua, submodule: ?[:0]const u8, field_name: [:0]const u8, comptime f: ziglua.ZigFn, ptr: *anyopaque) void {
    const n = l.getTop();
    // pushes _seamstress onto the stack
    getSeamstress(l);
    if (submodule) |s| {
        _ = l.getField(-1, s);
        l.remove(-2);
    }
    _ = l.pushStringZ(field_name);
    // pushes our upvalue
    l.pushLightUserdata(ptr);
    // creates the function (consuming the upvalue)
    l.pushClosure(ziglua.wrap(f), 1);
    // assigns it to _seamstress.field_name
    l.setTable(-3);
    // and removes _seamstress from the stack
    l.pop(1);
    std.debug.assert(n == l.getTop());
}

/// must be called within a closure with a single upvalue.
/// gets the one upvalue associated with the closure
/// returns null on failure
pub fn closureGetContext(l: *Lua, comptime T: type) *T {
    const idx = Lua.upvalueIndex(1);
    const ctx = l.toUserdata(T, idx) catch |err| panic("unexpected error: {s}", .{@errorName(err)});
    return ctx;
}

// attempts to push _seamstress onto the stack
pub fn getSeamstress(l: *Lua) void {
    const t = l.getGlobal("seamstress") catch |err|
        panic("error getting seamstress: {s}", .{@errorName(err)});
    if (t == .table) return;
    panic("seamstress corrupted!", .{});
}

/// pushes seamstress.event.publish onto the stack
/// also pushes the strings given as the namespace as the first argument
/// if namespace is empty, does nothing!
pub fn preparePublish(l: *Lua, namespace: []const []const u8) void {
    if (namespace.len == 0) return;
    getMethod(l, "event", "publish");
    l.createTable(@intCast(namespace.len), 0);
    for (namespace, 1..) |str, i| {
        _ = l.pushString(str);
        l.setIndex(-2, @intCast(i));
    }
}

// attempts to get the method specified by name onto the stack
pub fn getMethod(l: *Lua, field: [:0]const u8, method: [:0]const u8) void {
    getSeamstress(l);
    const t = l.getField(-1, field);
    // nothing sensible to do other than panic if something goes wrong
    if (t != .table) panic("seamstress corrupted! table expected for field {s}, got {s}", .{ field, @tagName(t) });
    l.remove(-2);
    const t2 = l.getField(-1, method);
    if (t2 != .function and t2 != .table and t2 != .userdata) panic("seamstress corrupted! function expected for field {s}, got {s}", .{ method, @tagName(t2) });
    l.remove(-2);
}

// attempts to get a reference to the event loop
pub fn getWheel(l: *Lua) *Wheel {
    getSeamstress(l);
    const t = l.getField(-1, "_loop");
    // nothing sensible to do other than panic if something goes wrong
    if (t != .userdata and t != .light_userdata) panic("_seamstress corrupted!", .{});
    const self = l.toUserdata(Wheel, -1) catch panic("_seamstress corrupted!", .{});
    l.pop(2);
    return self;
}

// attempts to set the specified field of the _seamstress.config table
pub fn setConfig(l: *Lua, field: [:0]const u8, val: anytype) void {
    getSeamstress(l);
    defer l.setTop(0);
    const t = l.getField(-1, "config");
    // nothing sensible to do other than panic if something goes wrong
    if (t != .table) panic("_seamstress corrupted!", .{});
    l.pushAny(val) catch |err| panic("error setting config: {s}", .{@errorName(err)});
    l.setField(-2, field);
}

// attempts to get the specified field of the _seamstress.config table
pub fn getConfig(l: *Lua, field: [:0]const u8, comptime T: type) T {
    getSeamstress(l);
    const t = l.getField(-1, "config");
    // nothing sensible to do other than panic if something goes wrong
    if (t != .table) panic("seamstress corrupted!", .{});
    _ = l.getField(-1, field);
    const ret = l.toAny(T, -1) catch |err| panic("error getting config: {s}", .{@errorName(err)});
    l.pop(3);
    return ret;
}

// a wrapper around lua_pcall
pub fn doCall(l: *Lua, nargs: i32, nres: i32) void {
    const base = l.getTop() - nargs;
    l.pushFunction(ziglua.wrap(messageHandler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        return;
    };
    l.remove(base);
}

// adds a stack trace to an error message (and turns it into a string if it is not already)
pub fn messageHandler(l: *Lua) i32 {
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const msg = l.checkString(1);
            l.traceback(l, msg, 1);
        },
        // TODO: could we use checkString instead?
        else => {
            const msg = std.fmt.allocPrintZ(l.allocator(), "(error object is an {s} value: {s})", .{ l.typeName(t), l.toStringEx(1) }) catch return 1;
            l.pop(1);
            defer l.allocator().free(msg);
            l.traceback(l, msg, 1);
        },
    }
    return 1;
}

/// uses the lua_loadbuffer API to process a chunk
/// returns true if the chunk is not a complete lua statement
pub fn processChunk(l: *Lua, chunk: []const u8) bool {
    // pushes the buffer onto the stack
    _ = l.pushString(chunk);
    // adds "return" to the beginning of the buffer
    const with_return = std.fmt.allocPrint(l.allocator(), "return {s}", .{chunk}) catch panic("out of memory!", .{});
    defer l.allocator().free(with_return);
    // loads the chunk...
    l.loadBuffer(with_return, "=stdin", .text) catch |err| {
        // ... if the chunk does not compile
        switch (err) {
            // we ran out of RAM! ack!
            error.Memory => panic("out of memory!", .{}),
            // the chunk had a syntax error
            error.Syntax => {
                // remove the failed chunk
                l.pop(1);
                // load the chunk without "return " added
                l.loadBuffer(chunk, "=stdin", .text) catch |err2| switch (err2) {
                    error.Memory => panic("out of memory!", .{}),
                    error.Syntax => {
                        const msg = l.toStringEx(-1);
                        // is the syntax error telling us that the statement isn't finished yet?
                        if (std.mem.endsWith(u8, msg, "<eof>")) {
                            // pop the unfinished chunk and any error message
                            l.setTop(0);
                            // true means we're continuing
                            return true;
                        } else {
                            // remove the failed chunk
                            l.remove(-2);
                            // process the error message (add a stack trace)
                            _ = messageHandler(l);
                            return false;
                        }
                    },
                };
            },
        }
        // if we got here, the chunk compiled fine without "return " added
        // so remove the string at the beginning
        l.remove(1);
        _ = doCall(l, 0, ziglua.mult_return);
        return false;
    };
    // ... the chunk compiles fine with "return " added!
    // let's remove the buffer we pushed onto the stack earlier
    l.remove(-2);
    // and call the compiled function
    doCall(l, 0, ziglua.mult_return);
    return false;
}

/// call print from outside lua
pub fn luaPrint(l: *Lua) void {
    const n = l.getTop();
    _ = l.getGlobal("print") catch unreachable;
    // put print where we can call it
    l.insert(1);
    l.call(n, 0);
}

/// checks whether the given argument is callable, raises a type error if not
/// if so, pushes the relevant function onto the stack
pub fn checkCallable(l: *Lua, arg: i32) void {
    const t = l.typeOf(arg);
    switch (t) {
        .function => {
            l.pushValue(arg);
            return;
        },
        .table, .userdata => {
            if ((l.getMetaField(arg, "__call") catch .nil) == .function) {
                return;
            }
            l.pop(1);
        },
        else => {},
    }
    l.typeError(arg, "callable value");
}

/// checks whether any elements of the table on top of the stack are truthy
/// does not pop the table
pub fn anyTruthy(l: *Lua) bool {
    l.len(-1);
    const len = l.toInteger(-1) catch unreachable;
    l.pop(1);
    var i: ziglua.Integer = 1;
    while (i <= len) : (i += 1) {
        _ = l.getIndex(-1, i);
        const truthy = l.toBoolean(-1);
        l.pop(1);
        if (truthy) break;
    } else return false;
    return true;
}
