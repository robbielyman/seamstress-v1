/// OSC module
// @module _seamstress.osc
const Osc = @This();

// pub so that submodules like monome.zig can access it
pub fn errHandler(errno: i32, msg: ?[*:0]const u8, path: ?[*:0]const u8) void {
    logger.err("liblo error {d} at {s}: {s}", .{ errno, path orelse "", msg orelse "" });
}

// pub so that submodules like monome.zig can access it
pub const OscServer = struct {
    server: *lo.Server,
    lua: *Lua,
    addr: std.net.Address,
};

fn noopCallback(_: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, _: xev.UDP, err: xev.UDP.CloseError!void) xev.CallbackAction {
    _ = err catch {};
    return .disarm;
}

fn callbackOSC(
    ud: ?*Osc,
    _: *xev.Loop,
    _: *xev.Completion,
    _: *xev.UDP.State,
    addr: std.net.Address,
    _: xev.UDP,
    b: xev.ReadBuffer,
    r: xev.ReadError!usize,
) xev.CallbackAction {
    const size = r catch |e| {
        logger.err("error while reading: {}", .{e});
        return .rearm;
    };
    const self = ud.?;
    self.last_addr = addr;
    self.server.dispatchData(b.slice[0..size]) catch {
        logger.err("liblo error!", .{});
    };
    return .rearm;
}

/// handles OSC events that aren't intercepted by another module
fn defaultHandler(path: [:0]const u8, types: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Osc = @ptrCast(@alignCast(ctx orelse return true));
    const l = self.lua;
    // trim the initial "/seamstress" if present
    const prefix = "/seamstress";
    const prefixed = std.mem.startsWith(u8, path, prefix);
    const un_prefixed = if (prefixed) path[prefix.len..] else path;
    var list = std.ArrayList([]const u8).init(l.allocator());
    defer list.deinit();
    var tokenizer = std.mem.tokenizeScalar(u8, un_prefixed, '/');
    // if "/seamstress" was not present, we namespace under "osc"
    if (!prefixed) list.append("osc") catch panic("out of memory!", .{});
    // split the path at slashes
    while (tokenizer.next()) |token| list.append(token) catch panic("out of memory!", .{});
    // the prepared path will be the namespace for our event
    lu.preparePublish(l, list.items);
    const top = l.getTop(); // the number of arguments is variable, so we need to know how big we're making the stack.
    // the first argument to our event will be info about the message
    l.createTable(1, 2); // t
    _ = l.pushStringZ(path);
    l.setIndex(-2, 1); // t[1] = path
    var counter = std.io.countingWriter(std.io.null_writer);
    self.last_addr.?.format("", .{}, counter.writer()) catch unreachable;
    const count = counter.bytes_written;
    const slice = l.allocator().alloc(u8, count) catch panic("out of memory!", .{});
    defer l.allocator().free(slice);
    var stream = std.io.fixedBufferStream(slice);
    self.last_addr.?.format("", .{}, stream.writer()) catch unreachable;
    const idx = std.mem.lastIndexOfScalar(u8, slice, ':').?;
    l.newTable(); // s = {}
    _ = l.pushString(slice[idx + 1 ..]); // push the port
    _ = l.pushString(slice[0..idx]);
    l.setIndex(-3, 1); // s[1] = host
    l.setIndex(-2, 2); // s[2] = port
    l.setField(-2, "from"); // t.from = s
    _ = l.pushString(types);
    l.setField(-2, "types"); // t.types = types
    // cheeky way to handle the errors only once
    _ = err: {
        // loop over the types, pushing onto the stack
        for (types, 0..) |t, i| {
            switch (t) {
                'i', 'h' => {
                    const arg = msg.getArg(i64, i) catch |err| break :err err;
                    l.pushInteger(@intCast(arg));
                },
                'f', 'd' => {
                    const arg = msg.getArg(f64, i) catch |err| break :err err;
                    l.pushNumber(arg);
                },
                's', 'S' => {
                    const arg = msg.getArg([:0]const u8, i) catch |err| break :err err;
                    _ = l.pushStringZ(arg);
                },
                'm' => {
                    const arg = msg.getArg([4]u8, i) catch |err| break :err err;
                    _ = l.pushString(&arg);
                },
                'b' => {
                    const arg = msg.getArg([]const u8, i) catch |err| break :err err;
                    _ = l.pushString(arg);
                },
                'c' => {
                    const arg = msg.getArg(u8, i) catch |err| break :err err;
                    _ = l.pushString(&.{arg});
                },
                'T', 'F' => {
                    const arg = msg.getArg(bool, i) catch |err| break :err err;
                    l.pushBoolean(arg);
                },
                'I', 'N' => {
                    const arg = msg.getArg(lo.LoType, i) catch |err| break :err err;
                    switch (arg) {
                        .infinity => l.pushInteger(ziglua.max_integer),
                        .nil => l.pushNil(),
                    }
                },
                else => unreachable,
            }
        }
    } catch |err| {
        logger.err("error getting argument: {s}", .{@errorName(err)});
        l.pop(2 + l.getTop() - top);
        return true;
    };
    // call the function
    l.call(1 + l.getTop() - top, 0);
    return false;
}

/// matches an OSC path against a pattern
fn match(l: *Lua) i32 {
    const pattern = l.checkString(1);
    const path = l.checkString(2);
    l.pushBoolean(lo.patternMatch(path.ptr, pattern.ptr));
    return 1;
}

/// sends an OSC message
fn oscSend(l: *Lua) i32 {
    const num_args = l.getTop();
    const osc = lu.closureGetContext(l, Osc);
    if (num_args < 2) return 0;
    // grab the address
    const hostname, const port = address: {
        switch (l.typeOf(1)) {
            // if we have a string, it's the port number; use what localhost should resolve to as our hostname
            .string => break :address .{ "127.0.0.1", l.toString(1) catch unreachable },
            // if we have a number, it's the port number; use what localhost should resolve to as our hostname
            .number => break :address .{ "127.0.0.1", l.toString(1) catch unreachable },
            // if passed a table, it must specify both host and port
            .table => {
                if (l.rawLen(1) != 2) l.argError(1, "address should be a table in the form [host, port]");
                const t1 = l.getIndex(1, 1);
                // hostname must be a string
                if (t1 != .string) l.argError(1, "address should be a table in the form [host, port]");
                const hostname = l.toString(-1) catch unreachable;
                l.pop(1);

                const t2 = l.getIndex(1, 2);
                // we'll allow numbers for port
                if (t2 != .string and t2 != .number) l.argError(1, "address should be a table in the form {host, port}");
                const port = l.toString(-1) catch unreachable;
                l.pop(1);
                break :address .{ hostname, port };
            },
            // bad argument
            else => l.typeError(1, "table, integer or string"),
        }
    };
    // grab the path
    const t2 = l.typeOf(2);
    const path, const types: ?[]const u8 = switch (t2) {
        .string => .{ l.checkString(2), null },
        .table => blk: {
            if (l.rawLen(2) < 1) l.argError(2, "path is required!");
            if (l.getIndex(2, 1) != .string) l.argError(2, "path must be a string!");
            const path = l.toString(-1) catch unreachable;
            l.pop(1);

            const types: ?[]const u8 = switch (l.getIndex(2, 2)) {
                .string => l.toString(-1) catch unreachable,
                else => null,
            };
            l.pop(1);
            break :blk .{ path, types };
        },
        else => l.typeError(2, "string or [string, string] expected"),
    };
    // create a lo.Address
    const address = lo.Address.new(hostname.ptr, port.ptr) orelse {
        logger.err("osc.send: unable to create address!", .{});
        return 0;
    };
    defer address.free();
    // create a lo.Message
    const msg = lo.Message.new() orelse {
        logger.err("osc.send: unable to create message!", .{});
        return 0;
    };
    defer msg.free();
    _ = err: {
        if (types) |spec| {
            // trust the spec
            for (spec, 3..) |char, index|
                switch (char) {
                    'i' => msg.add(.{@as(i32, @intCast(l.checkInteger(@intCast(index))))}) catch |err| break :err err,
                    'h' => msg.add(.{@as(i64, @intCast(l.checkInteger(@intCast(index))))}) catch |err| break :err err,
                    'f' => msg.add(.{@as(f32, @floatCast(l.checkNumber(@intCast(index))))}) catch |err| break :err err,
                    'd' => msg.add(.{l.checkNumber(@intCast(index))}) catch |err| break :err err,
                    's', 'S' => msg.add(.{l.checkString(@intCast(index))}) catch |err| break :err err,
                    'm' => {
                        var midi: [4]u8 = .{ 0, 0, 0, 0 };
                        const str = l.checkString(@intCast(index));
                        for (0..4) |i| {
                            if (i >= str.len) break;
                            midi[i] = str[i];
                        }
                        msg.add(.{midi}) catch |err| break :err err;
                    },
                    'b' => msg.add(.{l.toStringEx(@intCast(index))}) catch |err| break :err err,
                    'c' => msg.add(.{l.toStringEx(@intCast(index))[0]}) catch |err| break :err err,
                    'T', 'F' => msg.add(.{l.toBoolean(@intCast(index))}) catch |err| break :err err,
                    'I' => msg.add(.{lo.LoType.infinity}) catch |err| break :err err,
                    'N' => msg.add(.{lo.LoType.nil}) catch |err| break :err err,
                    else => l.raiseErrorStr("bad type tag %c", .{char}),
                };
        } else {
            var index: i32 = 3;
            // tricksy trick to `catch` only once
            while (index <= num_args) : (index += 1)
                switch (l.typeOf(index)) {
                    .nil => msg.add(.{.nil}) catch |err| break :err err,
                    .boolean => msg.add(.{l.toBoolean(index)}) catch |err| break :err err,
                    .string => msg.add(.{l.toString(index) catch unreachable}) catch |err| break :err err,
                    .number => if (l.isInteger(index))
                        msg.add(.{@as(i32, @intCast(l.toInteger(index) catch unreachable))}) catch |err| break :err err
                    else
                        msg.add(.{@as(f32, @floatCast(l.toNumber(index) catch unreachable))}) catch |err| break :err err,
                    // other types don't make sense to send via OSC
                    else => l.typeError(index, "unsupported OSC argument type!"),
                };
        }
    } catch {
        logger.err("osc.send: unable to add arguments to message!", .{});
        return 0;
    };

    // send the message
    osc.server.send(address, path.ptr, msg) catch {
        logger.err("osc.send: error sending message!", .{});
    };
    // nothing to return
    return 0;
}

watcher: xev.UDP,
c: xev.Completion = .{},
s: xev.UDP.State,
server: *lo.Server,
lua: *Lua,
monome: @import("monome.zig"),
last_addr: ?std.net.Address,
buffer: []u8,

// sets up the OSC server, using the config-provided port if it exists, otherwise using a free one
fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    const self = try allocator.create(Osc);
    errdefer allocator.destroy(self);
    var port = std.math.cast(u16, lu.getConfig(l, "local_port", ziglua.Integer) orelse 7777) orelse 7777;
    var addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 0);
    self.* = .{
        .watcher = xev.UDP.init(addr) catch panic("unable to init UDP listener!", .{}),
        .server = lo.Server.new(null, lo.wrap(Osc.errHandler)) orelse return error.OutOfMemory,
        .lua = l,
        .s = .{ .userdata = null },
        .buffer = try allocator.alloc(u8, 65535), // magic number recommended by liblo
        .last_addr = null,
        .monome = undefined,
    };
    var try_again = true;
    var rand = std.rand.DefaultPrng.init(7777);
    const r = rand.random();
    while (try_again) {
        addr.setPort(port);
        self.watcher.bind(addr) catch {
            port = r.int(u16);
            continue;
        };
        try_again = false;
    }
    const top = l.getTop();
    defer std.debug.assert(l.getTop() == top);
    lu.getSeamstress(l);
    _ = l.getField(-1, "osc");
    l.pushInteger(port);
    l.setField(-2, "local_port");
    l.pop(2);

    const local_address = lo.Message.new() orelse return error.OutOfMemroy;
    try local_address.add(.{ "127.0.0.1", @as(i32, @intCast(port)) });
    self.monome.init(local_address);
    logger.info("local port: {d}", .{port});
    try self.monome.registerSeamstress(l);
    _ = self.server.addMethod(null, null, lo.wrap(defaultHandler), self);

    lu.registerSeamstress(l, "osc", "send", oscSend, self);
    lu.registerSeamstress(l, "osc", "match", match, self);

    m.self = self;
}

fn deinit(m: *const Module, l: *Lua, allocator: std.mem.Allocator, cleanup: Cleanup) void {
    _ = l; // autofix
    if (cleanup != .full) return;
    const self: *Osc = @ptrCast(@alignCast(m.self orelse return));
    std.posix.close(self.watcher.fd);

    self.monome.deinit();
    self.server.free();
    allocator.free(self.buffer);
    allocator.destroy(self);
}

fn launch(m: *const Module, _: *Lua, wheel: *Wheel) anyerror!void {
    const self: *Osc = @ptrCast(@alignCast(m.self.?));
    self.monome.sendList();
    const buf: xev.ReadBuffer = .{ .slice = self.buffer };
    self.watcher.read(&wheel.loop, &self.c, &self.s, buf, Osc, self, callbackOSC);
}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

const logger = std.log.scoped(.osc);

const Module = @import("../module.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Seamstress = @import("../seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const Wheel = @import("../wheel.zig");
const Spindle = @import("../spindle.zig");
const xev = @import("xev");
const lo = @import("ziglo");
const lu = @import("../lua_util.zig");
const std = @import("std");
const panic = std.debug.panic;

test "ref" {
    _ = Osc;
    _ = @import("monome.zig");
}
