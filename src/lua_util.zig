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

/// registers a closure as _seamstress.field_name
/// we're using closures instead of global state!
/// makes me feel fancy
/// the closure has one "upvalue" in Lua terms: ptr
pub fn registerSeamstress(l: *Lua, field_name: [:0]const u8, comptime f: ziglua.ZigFn, ptr: *anyopaque) void {
    // pushes _seamstress onto the stack
    getSeamstress(l);
    // pushes our upvalue
    l.pushLightUserdata(ptr);
    // creates the function (consuming the upvalue)
    l.pushClosure(ziglua.wrap(f), 1);
    // assigns it to _seamstress.field_name
    l.setField(-2, field_name);
    // and removes _seamstress from the stack
    l.pop(1);
}

/// must be called within a closure registered with `registerSeamstress`.
/// gets the one upvalue associated with the closure
/// returns null on failure
pub fn closureGetContext(l: *Lua, comptime T: type) ?*T {
    const idx = Lua.upvalueIndex(1);
    const ctx = l.toUserdata(T, idx) catch return null;
    return ctx;
}

// attempts to push _seamstress onto the stack
pub fn getSeamstress(l: *Lua) void {
    const t = l.getGlobal("_seamstress") catch |err|
        panic("error getting _seamstress: {s}", .{@errorName(err)});
    if (t == .table) return;
    panic("_seamstress corrupted!", .{});
}

// attempts to get the method specified by name onto the stack
pub fn getMethod(l: *Lua, field: [:0]const u8, method: [:0]const u8) void {
    getSeamstress(l);
    const t = l.getField(-1, field);
    // nothing sensible to do other than panic if something goes wrong
    if (t != .table) panic("_seamstress corrupted!", .{});
    l.remove(-2);
    const t2 = l.getField(-1, method);
    if (t2 != .function) panic("_seamstress corrupted!", .{});
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
    if (t != .table) panic("_seamstress corrupted!", .{});
    _ = l.getField(-1, field);
    const ret = l.toAny(T, -1) catch |err| panic("error getting config: {s}", .{@errorName(err)});
    l.setTop(0);
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
            const msg = l.toString(1) catch return 1;
            l.pop(1);
            l.traceback(l, msg, 1);
        },
        // TODO: could we use checkString instead?
        else => {
            const msg = std.fmt.allocPrintZ(l.allocator(), "(error object is an {s} value)", .{l.typeName(t)}) catch return 1;
            defer l.allocator().free(msg);
            l.pop(1);
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
        // bizarrely, we want to remove the compiled code---it's probably not a function but a value!
        l.remove(1);
        // instead let's call the buffer we pushed onto the stack earlier (tricksy tricksy)
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
    getSeamstress(l);
    // put _print onto the stack
    _ = l.getField(-1, "_print");
    // remove _seamstress from the stack
    l.remove(-2);
    // put print where we can call it
    l.insert(1);
    l.call(n, 0);
}

/// replaces `print`
/// the terminal UI module is responsible for registering this function
pub fn printFn(l: *Lua) i32 {
    // how many things are we printing?
    const n = l.getTop();
    // get our closed-over value
    const ctx = closureGetContext(l, std.io.AnyWriter).?;
    // printing nothing should do nothing
    if (n == 0) return 0;
    // while loop because for loops are limited to `usize` in zig
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        // separate with tabs
        if (i > 1) ctx.writeAll("\t") catch {};
        const t = l.typeOf(i);
        switch (t) {
            .number => {
                if (l.isInteger(i)) {
                    const int = l.checkInteger(i);
                    ctx.print("{d}", .{int}) catch {};
                } else {
                    const double = l.checkNumber(i);
                    ctx.print("{d}", .{double}) catch {};
                }
            },
            .table => {
                const str = l.toString(i) catch {
                    const ptr = l.toPointer(i) catch unreachable;
                    ctx.print("table: 0x{x}", .{@intFromPtr(ptr)}) catch {};
                    continue;
                };
                ctx.print("{s}", .{str}) catch {};
            },
            .function => {
                const ptr = l.toPointer(i) catch unreachable;
                ctx.print("function: 0x{x}", .{@intFromPtr(ptr)}) catch {};
            },
            else => {
                const str = l.toStringEx(i);
                ctx.print("{s}", .{str}) catch {};
            },
        }
    }
    // finish with a newline
    ctx.writeAll("\n") catch {};
    return 0;
}
