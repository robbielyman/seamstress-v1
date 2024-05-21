/// the Lua VM
const Spindle = @This();

// the lua instance
l: *Lua,
// the buffered writer which we log to
// here so that its underlying writer may be replaced easily by module code
stderr: *BufferedWriter,
// a little closure to say hello
hello: ?struct {
    ctx: *anyopaque,
    hello_fn: *const fn (*anyopaque) void,
} = null,

const logger = std.log.scoped(.spindle);

// initializes the lua VM
pub fn init(self: *Spindle, allocator: *const std.mem.Allocator, writer: *BufferedWriter) Error!void {
    self.* = .{
        .stderr = writer,
        .l = Lua.init(allocator) catch return error.OutOfMemory,
    };
    errdefer self.l.close();

    // open lua libraries
    self.l.openLibs();
    self.setUpSeamstress() catch return error.LaunchFailed;
    _ = self.l.atPanic(ziglua.wrap(luaPanic));
}

// sets up the _seamstress table
fn setUpSeamstress(self: *Spindle) !void {
    const l = self.l;
    const seamstress: *Seamstress = @fieldParentPtr("vm", self);
    // create a new table
    l.newTable();
    // push the event loop
    l.pushLightUserdata(&seamstress.loop);
    l.setField(-2, "_loop");
    // and another one
    l.newTable();
    // assign to the previous one
    l.setField(-2, "config");
    {
        var buf: [16 * 1024]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .{ .buffer = &buf, .end_index = 0 };
        const a = fba.allocator();
        const location = try std.fs.selfExeDirPathAlloc(a);
        defer a.free(location);
        const path = try std.fs.path.joinZ(a, &.{ location, "..", "share", "seamstress", "lua" });
        defer a.free(path);
        const prefix = try std.fs.realpathAlloc(a, path);
        _ = l.pushString(prefix);
        l.setField(-2, "prefix");
    }
    {
        const version = Seamstress.version;
        l.createTable(3, 1);
        l.pushInteger(@intCast(version.major));
        l.setIndex(-2, 1);
        l.pushInteger(@intCast(version.minor));
        l.setIndex(-2, 2);
        l.pushInteger(@intCast(version.patch));
        l.setIndex(-2, 3);
        if (version.pre) |pre| _ = l.pushString(pre) else l.pushNil();
        l.setField(-2, "pre");
        l.setField(-2, "version");
    }
    l.setGlobal("_seamstress");

    {
        var buf: [8 * 1024]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .{ .buffer = &buf, .end_index = 0 };
        const allocator = fba.allocator();
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        _ = l.pushString(cwd);
        l.setGlobal("_pwd");
    }
}

// have lua crash via our panic rather than its own way
fn luaPanic(l: *Lua) i32 {
    const msg = l.toString(-1) catch "";
    std.debug.panic("lua crashed: {s}", .{msg});
    return 0;
}

// closes the lua VM and frees memory
pub fn close(self: *Spindle) void {
    self.l.close();
}

// call init()
pub fn callInit(self: *Spindle) void {
    lu.getSeamstress(self.l);
    _ = self.l.getField(-1, "prefix");
    _ = self.l.pushString("/config.lua");
    self.l.concat(2);
    const file_name = self.l.toStringEx(-1);
    self.l.doFile(file_name) catch lu.panic(self.l, error.LaunchFailed);
    self.l.setTop(0);

    lu.getSeamstress(self.l);
    _ = self.l.getField(-1, "prefix");
    _ = self.l.pushString("/core/seamstress.lua");
    self.l.concat(2);
    const file_name2 = self.l.toStringEx(-1);
    self.l.doFile(file_name2) catch lu.panic(self.l, error.LaunchFailed);
    self.l.setTop(0);

    const t = self.l.getGlobal("_startup") catch {
        lu.panic(self.l, error.LaunchFailed);
        return;
    };
    if (t != .function) lu.panic(self.l, error.LaunchFailed);
    lu.doCall(self.l, 0, 0);
}

// call cleanup()
pub fn cleanup(self: *Spindle) void {
    lu.getSeamstress(self.l);
    const t = self.l.getField(-1, "cleanup");
    if (t != .function) return;
    lu.doCall(self.l, 0, 0);
}

// TODO: parse config
pub fn parseConfig(self: *Spindle) Error!Config {
    var iter = std.process.argsWithAllocator(self.l.allocator()) catch return error.LaunchFailed;
    defer iter.deinit();
    _ = iter.next();
    const script = iter.next();
    try lu.setConfig(self.l, "script_file", script);
    return .{ .tui = false };
}

// if the hello closure is avaiable, calls it
pub fn sayHello(self: *Spindle) void {
    if (self.hello) |h| {
        h.hello_fn(h.ctx);
    }
}

// uses the lua_loadbuffer API to process a chunk
fn processChunk(self: *Spindle, buf: []const u8) ?bool {
    // TODO: currently we only have one special command, but maybe we want more?
    if (std.mem.indexOf(u8, buf, "quit\n")) |idx| {
        if (idx == 0 or buf[idx - 1] == '\n') {
            lu.quit(self);
            return null;
        }
    }
    self.l.setTop(0);
    // pushes the buffer onto the stack
    _ = self.l.pushString(buf);
    // adds "return" to the beginning of the buffer
    const with_return = std.fmt.allocPrint(self.l.allocator(), "return {s}", .{buf}) catch {
        lu.panic(self, error.OutOfMemory);
        return false;
    };
    defer self.allocator.free(with_return);
    // loads the chunk...
    self.l.loadBuffer(with_return, "=stdin", .text) catch |err| {
        // ...if the chunk does not compile,
        switch (err) {
            // we ran out of RAM! panic!
            error.Memory => {
                self.l.pop(1);
                lu.panic(self, error.OutOfMemory);
                return false;
            },
            // the chunk had a syntax error
            error.Syntax => {
                // remove the failed chunk
                self.l.pop(1);
                // load the chunk without "return " added
                self.l.loadBuffer(buf, "=stdin", .text) catch |err2| switch (err2) {
                    error.Memory => {
                        self.l.pop(1);
                        lu.panic(self, error.OutOfMemory);
                        return false;
                    },
                    // that still didn't compile...
                    error.Syntax => {
                        // FIXME: is `unreachable` fine here? probably, right?
                        const msg = self.l.toString(-1) catch unreachable;
                        // is the syntax error telling us that the statement isn't finished yet?
                        if (std.mem.endsWith(u8, msg, "<eof>")) {
                            // pop the unfinished chunk
                            self.l.pop(1);
                            // true means we're continuing
                            return true;
                        } else {
                            // remove the failed chunk
                            self.l.remove(-2);
                            // process the error message (add a stack trace)
                            _ = lu.messageHandler(self.l);
                            return false;
                        }
                    },
                };
            },
        }
        // if we got here, the chunk compiled fine without "return " added
        // so we'll save the chunk, since it's a well-formed command
        self.saveBufferToHistory(buf);
        // bizarrely, we want to remove the compiled code---it's probably not a function but a value!
        self.l.remove(1);
        // instead let's call the buffer we pushed onto the stack earlier (tricksy tricksy)
        _ = lu.doCall(self.l, 0, ziglua.mult_return);
        return false;
    };
    // ... the chunk compiles fine with "return " added!
    // so we'll save the chunk, since it's a well-formed command
    self.saveBufferToHistory(buf);
    // let's remove the buffer we pushed onto the stack earlier
    self.l.remove(-2);
    // and call the compiled function
    _ = lu.doCall(self.l, 0, ziglua.mult_return);
    return false;
}

// TODO: implement saving to history
fn saveBufferToHistory(self: *Spindle, buf: []const u8) void {
    _ = buf; // autofix
    _ = self; // autofix
}

/// replaces `print`
/// pub because it is the UI module's responsibility to populate the context
pub fn printFn(l: *Lua) i32 {
    // how many things are we printing?
    const n = l.getTop();
    // get our closed-over value
    const ctx = lu.closureGetContext(l, std.io.AnyWriter) orelse return 0;

    // printing nothing should do nothing
    if (n == 0) return 0;

    // while loop because for loops are limited to `usize` in zig
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        // separate with tabs
        // FIXME: should we panic on error instead?
        if (i > 1) ctx.print("\t", .{}) catch {};
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
                const str = l.toString(i) catch continue;
                ctx.print("{s}", .{str}) catch {};
            },
        }
    }
    // finish out with a newline
    ctx.print("\n", .{}) catch {};
    return 0;
}

const std = @import("std");
const ziglua = @import("ziglua");
const lu = @import("lua_util.zig");
const Lua = ziglua.Lua;
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Config = @import("config.zig");
const Wheel = @import("wheel.zig");
const BufferedWriter = std.io.BufferedWriter(4096, std.io.AnyWriter);
