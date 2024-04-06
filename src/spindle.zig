/// spindle is the seamstress Lua VM
/// it is responsible for responding to chunks of Lua and other commands (like 'quit') over stdin
/// setting up the Lua experience
/// and parsing the config file / arguments
const Spindle = @This();

// available to everything by default, essentially
allocator: std.mem.Allocator,
// the events queue
events: Events,
// the lua object
lvm: *Lua,
// the IO mutex
io: *Io,
// a little closure used to say hello
hello: ?struct {
    ctx: *anyopaque,
    hello_fn: *const fn (*anyopaque) void,
} = null,

pub const logger = std.log.scoped(.spindle);

// initializes the Lua VM
pub fn init(self: *Spindle, allocator: *const std.mem.Allocator, io: *Io) Error!void {
    self.* = .{
        .allocator = allocator.*,
        .io = io,
        .lvm = Lua.init(allocator) catch return error.OutOfMemory,
        .events = undefined,
    };
    self.events.init();

    // open lua libraries
    self.lvm.openLibs();
    self.setUpSeamstress();

    _ = self.lvm.atPanic(ziglua.wrap(luaPanic));
}

// sets up the _seamstress table
fn setUpSeamstress(self: *Spindle) void {
    // create a new table
    self.lvm.newTable();
    // push ourselves
    self.lvm.pushLightUserdata(self);
    self.lvm.setField(-2, "_context");
    // and another one
    self.lvm.newTable();
    // assign to the previous one
    self.lvm.setField(-2, "config");
    self.lvm.setGlobal("_seamstress");
}

fn luaPanic(l: *Lua) i32 {
    const msg = l.toString(-1) catch "";
    std.debug.panic("lua crashed: {s}", .{msg});
    return 0;
}

// closes the event queue and the lua VM and frees memory
pub fn close(self: *Spindle) void {
    self.events.close();
    self.lvm.close();
}

// TODO: call init()
pub fn callInit(self: *Spindle) void {
    _ = self; // autofix
}

// TODO: call cleanup()
pub fn cleanup(self: *Spindle) void {
    _ = self; // autofix
}

// TODO: parse config
pub fn parseConfig(self: *Spindle) Error!Config {
    _ = self; // autofix
    return .{ .tui = false };
}

// if the hello closure is avaiable, calls it
pub fn sayHello(self: *Spindle) void {
    if (self.hello) |h| {
        h.hello_fn(h.ctx);
    }
}

// struct for handling REPL input
pub const ReplContext = struct {
    spindle: *Spindle,
    buffer: *ThreadSafeBuffer(u8),
    length_to_read: usize = 0,
    node: Events.Node = .{
        .handler = Events.handlerFromClosure(ReplContext, replHandler, "node"),
    },
    // allows modules to "bring their own" memory management for ReplContext structs
    data: ?*anyopaque = null,
    discard: ?*const fn (*ReplContext, ?*anyopaque) void = null,

    // 16kB should be enough for anyone
    const max_repl_len = 16 * 1024;

    // handler for responding to REPL input
    fn replHandler(self: *ReplContext) void {
        // calculate the length to read
        const length_to_read = @min(self.length_to_read, self.buffer.readableLength());
        if (length_to_read > max_repl_len) {
            logger.err("line too long! discarding", .{});
            self.buffer.discard(length_to_read);
        }
        var buf: [max_repl_len]u8 = undefined;
        // read it in
        var actual: usize = 0;
        while (actual < length_to_read) {
            actual += self.buffer.peekContents(buf[actual..length_to_read], actual);
        }

        if (self.spindle.processChunk(buf[0..length_to_read])) |continuing| {
            if (!continuing) {
                // the chunk is no longer needed
                self.buffer.discard(length_to_read);
                self.length_to_read = 0;
            }
            // this has the useful side-effect of telling the UI thread to render,
            // regardless of whether we have output.
            // when continuing is true, this is important for the prompt to change
            _ = lu.luaPrint(self.spindle.lvm);
        } // null actually also means the chunk is no longer needed,
        // but it _also_ means we're quitting, so there's no point in discarding it

        // call our discard closure
        if (self.discard) |f| f(self, self.data);
    }
};

// uses the lua_loadbuffer API to process a chunk
fn processChunk(self: *Spindle, buf: []const u8) ?bool {
    // TODO: currently we only have one special command, but maybe we want more?
    if (std.mem.indexOf(u8, buf, "quit\n")) |idx| {
        if (idx == 0 or buf[idx - 1] == '\n') {
            lu.quit(self);
            return null;
        }
    }
    self.lvm.setTop(0);
    // pushes the buffer onto the stack
    _ = self.lvm.pushString(buf);
    // adds "return" to the beginning of the buffer
    const with_return = std.fmt.allocPrint(self.allocator, "return {s}", .{buf}) catch {
        lu.panic(self, error.OutOfMemory);
        return false;
    };
    defer self.allocator.free(with_return);
    // loads the chunk...
    self.lvm.loadBuffer(with_return, "=stdin", .text) catch |err| {
        // ...if the chunk does not compile,
        switch (err) {
            // we ran out of RAM! panic!
            error.Memory => {
                self.lvm.pop(1);
                lu.panic(self, error.OutOfMemory);
                return false;
            },
            // the chunk had a syntax error
            error.Syntax => {
                // remove the failed chunk
                self.lvm.pop(1);
                // load the chunk without "return " added
                self.lvm.loadBuffer(buf, "=stdin", .text) catch |err2| switch (err2) {
                    error.Memory => {
                        self.lvm.pop(1);
                        lu.panic(self, error.OutOfMemory);
                        return false;
                    },
                    // that still didn't compile...
                    error.Syntax => {
                        // FIXME: is `unreachable` fine here? probably, right?
                        const msg = self.lvm.toString(-1) catch unreachable;
                        // is the syntax error telling us that the statement isn't finished yet?
                        if (std.mem.endsWith(u8, msg, "<eof>")) {
                            // pop the unfinished chunk
                            self.lvm.pop(1);
                            // true means we're continuing
                            return true;
                        } else {
                            // remove the failed chunk
                            self.lvm.remove(-2);
                            // process the error message (add a stack trace)
                            _ = lu.messageHandler(self.lvm);
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
        self.lvm.remove(1);
        // instead let's call the buffer we pushed onto the stack earlier (tricksy tricksy)
        _ = lu.doCall(self.lvm, 0, ziglua.mult_return);
        return false;
    };
    // ... the chunk compiles fine with "return " added!
    // so we'll save the chunk, since it's a well-formed command
    self.saveBufferToHistory(buf);
    // let's remove the buffer we pushed onto the stack earlier
    self.lvm.remove(-2);
    // and call the compiled function
    _ = lu.doCall(self.lvm, 0, ziglua.mult_return);
    return false;
}

// TODO: implement saving to history
fn saveBufferToHistory(self: *Spindle, buf: []const u8) void {
    _ = buf; // autofix
    _ = self; // autofix
}

/// the context for printing
/// NB: we cannot and do not need to grab the IO mutex;
/// instead the UI module will pull from the other end of our Writer
/// when it receives input from ready
pub const PrintContext = struct {
    stdout: std.io.AnyWriter,
    ready: std.io.AnyWriter,
};

/// replaces `print`
/// pub because it is the UI module's responsibility to populate the context
pub fn printFn(l: *Lua) i32 {
    // how many things are we printing?
    const n = l.getTop();
    // get our closed-over value
    const ctx = lu.closureGetContext(l, PrintContext) orelse return 0;

    //  we end by tell the UI module we're ready to render
    defer _ = ctx.ready.write("r") catch {};
    // printing nothing should do nothing
    // this is actually useful behavior: we use it in stdinHandler
    if (n == 0) return 0;

    // while loop because for loops are limited to `usize` in zig
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        // separate with tabs
        // FIXME: should we panic on error instead?
        if (i > 1) ctx.stdout.print("\t", .{}) catch {};
        const t = l.typeOf(i);
        switch (t) {
            .number => {
                if (l.isInteger(i)) {
                    const int = l.checkInteger(i);
                    ctx.stdout.print("{d}", .{int}) catch {};
                } else {
                    const double = l.checkNumber(i);
                    ctx.stdout.print("{d}", .{double}) catch {};
                }
            },
            .table => {
                const str = l.toString(i) catch {
                    const ptr = l.toPointer(i) catch unreachable;
                    ctx.stdout.print("table: 0x{x}", .{@intFromPtr(ptr)}) catch {};
                    continue;
                };
                ctx.stdout.print("{s}", .{str}) catch {};
            },
            .function => {
                const ptr = l.toPointer(i) catch unreachable;
                ctx.stdout.print("function: 0x{x}", .{@intFromPtr(ptr)}) catch {};
            },
            else => {
                const str = l.toString(i) catch continue;
                ctx.stdout.print("{s}", .{str}) catch {};
            },
        }
    }
    // finish out with a newline
    ctx.stdout.print("\n", .{}) catch {};
    return 0;
}

const lu = @import("lua_util.zig");
const std = @import("std");
const ziglua = @import("ziglua");
const Seamstress = @import("seamstress.zig");
const Config = Seamstress.Config;
const Error = Seamstress.Error;
const Lua = ziglua.Lua;
const Events = @import("events.zig");
const Io = @import("io.zig");
const ThreadSafeBuffer = @import("thread_safe_buffer.zig").ThreadSafeBuffer;
