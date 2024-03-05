/// spindle is the seamstress Lua VM
/// it is responsible for responding to chunks of Lua and other commands (like 'quit') over stdin
/// setting up the Lua experience
/// and parsing the config file / arguments
const std = @import("std");
const ziglua = @import("ziglua");
const Seamstress = @import("seamstress.zig");
const Config = Seamstress.Config;
const Error = Seamstress.Error;
pub const Lua = ziglua.Lua;
const Events = @import("events.zig");
const Io = @import("io.zig");
const Spindle = @This();

// available to everything by default, essentially
allocator: std.mem.Allocator,
// the events queue
events: Events,
// the lua object
lvm: Lua,
// the IO mutex
io: *Io,
// a little closure used to say hello
hello: ?struct {
    ctx: *anyopaque,
    hello_fn: *const fn (*anyopaque) void,
} = null,
stdin_buffer: std.ArrayListUnmanaged(u8) = .{},

const logger = std.log.scoped(.spindle);

// registers a closure as _seamstress.field_name
// we're using closures this time around instead of global state!
// makes me feel fancy
// the closure has one "upvalue" in Lua terms: ptr
pub fn registerSeamstress(self: *Spindle, field_name: [:0]const u8, comptime f: ziglua.ZigFn, ptr: *anyopaque) void {
    // pushes _seamstress onto the stack
    getSeamstress(&self.lvm);
    // upshes our upvalue
    self.lvm.pushLightUserdata(ptr);
    // creates the function (consuming the upvalue)
    self.lvm.pushClosure(ziglua.wrap(f), 1);
    // assigns it to _seamstress.field_name
    self.lvm.setField(-2, field_name);
    // and removes _seamstress from the stack
    self.lvm.pop(1);
}

// attempts to push _seamstress onto the stack
// pub so that it can be used in module code
pub fn getSeamstress(l: *Lua) void {
    const t = l.getGlobal("_seamstress") catch |err| blk: {
        logger.err("error getting _seamstress: {s}", .{@errorName(err)});
        break :blk .nil;
    };
    if (t == .table) return;
    // FIXME: since the `Lua` object may be stack allocated by Ziglua,
    // we can't use @fieldParentPtr to find the VM,
    // so our only sensible option is to panic this way
    @panic("_seamstress corrupted!");
}

// attempts to get a reference to the Lua VM
// pub so that it can be used in module code
pub fn getVM(l: *Lua) *Spindle {
    getSeamstress(l);
    const t = l.getField(-1, "_context");
    // FIXME: again, nothing sensible to do other than panic if something goes wrong
    if (t != .userdata or t != .light_userdata) @panic("_seamstress corrupted!");
    const self = l.toUserdata(Spindle, -1) catch @panic("_seamstress corrupted!");
    l.pop(2);
    return self;
}

// initializes the Lua VM
pub fn init(self: *Spindle, allocator: *const std.mem.Allocator, io: *Io) Error!void {
    self.* = .{
        .allocator = allocator.*,
        .io = io,
        .stdin_buffer = .{},
        .lvm = Lua.init(allocator) catch return error.OutOfMemory,
        .events = undefined,
    };
    self.events = Events.init(self, allocator.*);

    self.lvm.openLibs();

    self.lvm.newTable();
    self.lvm.setGlobal("_seamstress");
}

// closes the event queue and the lua VM and frees memory
pub fn close(self: *Spindle) void {
    self.events.close();
    self.lvm.close();
    self.stdin_buffer.deinit(self.allocator);
}

// allows us to panic on the main thread by pushing it through the event queue
// pub so modules can access it
pub fn panic(self: *Spindle, err: Error) void {
    self.events.post(.{ .panic = err });
}

// posts a quit event
// pub so modules can access it
pub fn quit(self: *Spindle) void {
    self.events.post(.{ .quit = {} });
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
    return .{
        .tui = false,
    };
}

// if the hello closure is avaiable, calls it
pub fn sayHello(self: *Spindle) void {
    if (self.hello) |h| {
        h.hello_fn(h.ctx);
    }
}

// 16kB should be enough for anyone
const MAX_STDIN_LEN = 16 * 1024;

pub const StdinContext = struct {
    spindle: *Spindle,
    continuing: *bool,
};

// handler for reading from stdin
// pub so that modules can access it
pub fn stdinHandler(ctx: *anyopaque, reader: std.io.AnyReader, len: usize) void {
    const context: *StdinContext = @ptrCast(@alignCast(ctx));
    const self = context.spindle;
    if (len > MAX_STDIN_LEN) {
        logger.err("line too long! discarding", .{});
        reader.skipBytes(len, .{}) catch |err| {
            logger.err("error skipping bytes! {s}", .{@errorName(err)});
        };
        self.io.cond.signal();
    }
    self.stdin_buffer.ensureUnusedCapacity(self.allocator, len) catch {
        self.panic(error.OutOfMemory);
        return;
    };
    const buf = self.stdin_buffer.unusedCapacitySlice();
    const actual = reader.read(buf[0..len]) catch |err| {
        logger.err("error {s} while reading from stdin!", .{@errorName(err)});
        self.io.cond.signal();
        return;
    };
    self.stdin_buffer.items.len += actual;

    // doesn't signal the thread if processChunk returns null
    if (self.processChunk(self.stdin_buffer.items)) |continuing| {
        // false means the chunk is no longer needed, so we can discard it
        if (!continuing) self.stdin_buffer.clearRetainingCapacity();
        context.continuing.* = continuing;
        self.io.cond.signal();
    } // FIXME: null actually also means the chunk is no longer needed,
    // but currently it also means we're quitting, so there's no point in discarding it
}

// uses the lua_loadbuffer API to process a chunk
// pub so that modules can use it in their handlers
fn processChunk(self: *Spindle, buf: []const u8) ?bool {
    // TODO: currently we only have one special command, but maybe we want more?
    if (std.mem.indexOf(u8, buf, "quit\n")) |idx| {
        if (idx == 0 or buf[idx - 1] == '\n') {
            self.quit();
            return null;
        }
    }
    self.lvm.setTop(0);
    // pushes the buffer onto the stack
    _ = self.lvm.pushBytes(buf);
    // adds "return" to the beginning of the buffer
    const with_return = std.fmt.allocPrint(self.allocator, "return {s}", .{buf}) catch {
        self.panic(error.OutOfMemory);
        return false;
    };
    // loads the chunk...
    self.lvm.loadBuffer(with_return, "=stdin", .text) catch |err| {
        // ...if the chunk does not compile,
        switch (err) {
            // we ran out of RAM! panic!
            error.Memory => {
                self.lvm.pop(1);
                self.panic(error.OutOfMemory);
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
                        self.panic(error.OutOfMemory);
                        return false;
                    },
                    // that still didn't compile...
                    error.Syntax => {
                        // FIXME: is `unreachable` fine here? probably, right?
                        const msg = self.lvm.toBytes(-1) catch unreachable;
                        // is the syntax error telling us that the statement isn't finished yet?
                        if (std.mem.endsWith(u8, msg, "<eof>")) {
                            self.lvm.pop(1);
                            // true means we're continuing
                            return true;
                        } else {
                            // remove the failed chunk
                            self.lvm.remove(-2);
                            // process the error message (add a stack trace)
                            _ = messageHandler(&self.lvm);
                            // print out the error message
                            luaPrint(&self.lvm);
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
        self.callAndPrint();
        return false;
    };
    // ... the chunk compiles fine with "return " added!
    // so we'll save the chunk, since it's a well-formed command
    self.saveBufferToHistory(buf);
    // let's remove the buffer we pushed onto the stack earlier
    self.lvm.remove(-2);
    // and call the compiled function
    self.callAndPrint();
    return false;
}

// lua_pcall followed by print if the function returns any values
fn callAndPrint(self: *Spindle) void {
    _ = doCall(&self.lvm, 0, ziglua.mult_return);
    if (self.lvm.getTop() > 0) {
        luaPrint(&self.lvm);
    }
}

// a wrapper around lua_pcall
// pub so that modules can access it
pub fn doCall(l: *Lua, nargs: i32, nres: i32) void {
    const base = l.getTop() - nargs;
    l.pushFunction(ziglua.wrap(messageHandler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        luaPrint(l);
        return;
    };
    l.remove(base);
}

// adds a stack trace to an error message (and turns it into a string if it is not already)
fn messageHandler(l: *Lua) i32 {
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const msg = l.toBytes(1) catch return 1;
            l.pop(1);
            l.traceback(l, msg, 1);
        },
        else => {
            const msg = std.fmt.allocPrintZ(l.allocator(), "(error object is an {s} value)", .{l.typeName(t)}) catch return 1;
            defer l.allocator().free(msg);
            l.pop(1);
            l.traceback(l, msg, 1);
        },
    }
    return 1;
}

// calls our monkey-patched print function directly
fn luaPrint(l: *Lua) void {
    const n = l.getTop();
    getSeamstress(l);
    // gets the _print field of _seamstress
    _ = l.getField(-1, "_print");
    // removes _seamstress from the stack
    l.remove(-2);
    // moves _print so that we can call it
    l.insert(1);
    // TODO: should we pcall instead?
    l.call(n, 0);
}

// TODO: implement saving to history
fn saveBufferToHistory(self: *Spindle, buf: []const u8) void {
    _ = buf; // autofix
    _ = self; // autofix
}
