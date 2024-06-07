/// OSC module
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
    for (&self.monome.devices.server, &self.monome.devices.dev_addr) |server, other| {
        if (addr.eql(other orelse continue)) {
            server.dispatchData(b.slice[0..size]) catch {
                logger.err("liblo error!", .{});
            };
            return .rearm;
        }
    }
    self.last_addr = addr;
    self.server.dispatchData(b.slice[0..size]) catch {
        logger.err("liblo error!", .{});
    };
    return .rearm;
}

// quits
fn setQuit(_: [:0]const u8, _: []const u8, _: *lo.Message, ctx: ?*anyopaque) bool {
    const wheel: *Wheel = @ptrCast(@alignCast(ctx.?));
    wheel.quit();
    return false;
}

/// handles OSC events that aren't intercepted by another module
/// this _includes_ custom functions registered from Lua
/// ah, whose registry we can manage entirely in Lua actually lol, nice
fn defaultHandler(path: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Osc = @ptrCast(@alignCast(ctx orelse return true));
    const l = self.lua;
    // push _seamstress onto the stack
    lu.getSeamstress(l);
    // grab osc.method_list
    _ = l.getField(-1, "osc");
    l.remove(-2);
    _ = l.getField(-1, "method_list");
    l.remove(-2);
    // nil, to get the first key
    l.pushNil();
    // if one of our lua-defined functions returns something truthy, we stop
    var keep_going = true;
    while (l.next(-2) and keep_going) {
        {
            const t = l.typeOf(-2);
            // if the key is not a string, keep going
            if (t != .string) {
                logger.err("OSC handler: string expected, got {s}", .{l.typeName(t)});
                // remove the value, keep the key
                l.pop(1);
                continue;
            }
        }
        // if it is, check to see if we match the path of this event
        if (!lo.patternMatch(path, l.toStringEx(-2))) {
            l.pop(1);
            continue;
        }

        // first of all, the value had better be a function or a table of functions
        const t = l.typeOf(-1);
        switch (t) {
            .function => keep_going = pushArgsAndCall(l, msg, self.last_addr.?, path),
            .table => {
                l.len(-1);
                // if it's a table, how long is it?
                const len = l.toInteger(-1) catch unreachable;
                l.pop(1);
                var index: ziglua.Integer = 1;
                // while loop because in Zig for loops are limited to `usize`
                while (index <= len and keep_going) : (index += 1) {
                    const t2 = l.getIndex(-1, index);
                    if (t2 != .function) {
                        logger.err("OSC handler: function expected, got {s}", .{l.typeName(t2)});
                        l.pop(1);
                        continue;
                    }
                    keep_going = pushArgsAndCall(l, msg, self.last_addr.?, path);
                }
            },
            else => {
                logger.err("OSC handler: function or list of functions expected, got: {s}", .{l.typeName(t)});
                l.pop(1);
                continue;
            },
        }
        // if keep_going is still true, call the default handler
        if (keep_going) {
            lu.getSeamstress(l);
            _ = l.getField(-1, "osc");
            l.remove(-2);
            _ = l.getField(-1, "event");
            l.remove(-2);
            _ = pushArgsAndCall(l, msg, self.last_addr.?, path);
        }
    }
    return false;
}

/// pushes the contents of `msg` onto the stack and calls the function at the top of the stack
/// the function will receive the args as `path`, `args` (which may be an empty table) and `{from_hostname, from_port}`
fn pushArgsAndCall(l: *Lua, msg: *lo.Message, addr: std.net.Address, path: [:0]const u8) bool {
    const top = l.getTop();
    // push path first
    _ = l.pushString(path);
    const len = msg.argCount();
    l.createTable(@intCast(len), 0);
    // grab the list of types
    const types: []const u8 = if (len > 0) msg.types().?[0..len] else "";
    // cheeky way to handle the errors only once
    _ = err: {
        // loop over the types, adding them to our table
        for (types, 0..) |t, i| {
            switch (t) {
                'i', 'h' => {
                    const arg = msg.getArg(i64, i) catch |err| break :err err;
                    l.pushInteger(@intCast(arg));
                    l.setIndex(-2, @intCast(i + 1));
                },
                'f', 'd' => {
                    const arg = msg.getArg(f64, i) catch |err| break :err err;
                    l.pushNumber(arg);
                    l.setIndex(-2, @intCast(i + 1));
                },
                's', 'S' => {
                    const arg = msg.getArg([:0]const u8, i) catch |err| break :err err;
                    _ = l.pushStringZ(arg);
                    l.setIndex(-2, @intCast(i + 1));
                },
                'm' => {
                    const arg = msg.getArg([4]u8, i) catch |err| break :err err;
                    _ = l.pushString(&arg);
                    l.setIndex(-2, @intCast(i + 1));
                },
                'b' => {
                    const arg = msg.getArg([]const u8, i) catch |err| break :err err;
                    _ = l.pushString(arg);
                    l.setIndex(-2, @intCast(i + 1));
                },
                'c' => {
                    const arg = msg.getArg(u8, i) catch |err| break :err err;
                    _ = l.pushString(&.{arg});
                    l.setIndex(-2, @intCast(i + 1));
                },
                'T', 'F' => {
                    const arg = msg.getArg(bool, i) catch |err| break :err err;
                    l.pushBoolean(arg);
                    l.setIndex(-2, @intCast(i + 1));
                },
                'I', 'N' => {
                    const arg = msg.getArg(lo.LoType, i) catch |err| break :err err;
                    switch (arg) {
                        .infinity => l.pushInteger(ziglua.max_integer),
                        .nil => l.pushNil(),
                    }
                    l.setIndex(-2, @intCast(i + 1));
                },
                else => unreachable,
            }
        }
    } catch |err| {
        logger.err("error getting argument: {s}", .{@errorName(err)});
        l.pop(l.getTop() - top);
        return true;
    };
    pushAddress(l, addr);
    // call the function
    lu.doCall(l, 3, 1);
    defer l.pop(1);
    // if we got something truthy, that means we're done so should return false
    return !l.toBoolean(-1);
}

fn pushAddress(l: *Lua, addr: std.net.Address) void {
    l.createTable(2, 0);
    var counter = std.io.countingWriter(std.io.null_writer);
    addr.format("", .{}, counter.writer()) catch unreachable;
    const count = counter.bytes_written;
    var buf: ziglua.Buffer = .{};
    const slice = buf.initSize(l, @intCast(count));
    var stream = std.io.fixedBufferStream(slice);
    addr.format("", .{}, stream.writer()) catch unreachable;
    const idx = std.mem.lastIndexOfScalar(u8, slice, ':').?;
    _ = l.pushString(slice[idx + 1 ..]);
    l.setIndex(-2, 2);
    buf.addSize(idx);
    buf.pushResult();
    l.setIndex(-2, 1);
}

/// sends an OSC message
// users should use `osc.send` instead.
// @tparam table|string address either a table of the form {host,port}
// where `host` and `port` are both strings,
// or a string, in which case `host` is taken to be "localhost" and the string is the port
// @tparam string path an OSC path `/like/this`
// @tparam table args a list whose data is passed over OSC as arguments
// @see osc.send
// @usage osc.send({"localhost", "777"}, "/send/stuff", {"a", 0, 0.5, nil, true})
// @function osc_send
pub fn oscSend(l: *Lua) i32 {
    const num_args = l.getTop();
    const osc = lu.closureGetContext(l, Osc) orelse return 0;
    if (num_args < 2) return 0;
    if (num_args > 3) l.raiseErrorStr("expected 3 args, got %d", .{num_args});
    // grab the address
    const hostname, const port = address: {
        switch (l.typeOf(1)) {
            // if we have a string, it's the port number; use what localhost should resolve to as our hostname
            .string => break :address .{ "127.0.0.1", l.toString(1) catch unreachable },
            // if we have a number, it's the port number; use what localhost should resolve to as our hostname
            .number => break :address .{ "127.0.0.1", l.toString(1) catch unreachable },
            // if passed a table, it must specify both host and port
            .table => {
                if (l.rawLen(1) != 2) l.argError(1, "address should be a table in the form {host, port}");
                const t1 = l.getIndex(1, 1);
                // hostname must be a string
                if (t1 != .string) l.argError(1, "address should be a table in the form {host, port}");
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
            inline else => |t| l.raiseErrorStr("bad argument #1: table or string expected, got %s", .{l.typeName(t).ptr}),
        }
    };
    // grab the path
    const path = l.checkString(2);
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
    // if we have args, let's pack them into our message
    if (num_args == 3) {
        l.checkType(3, .table);
        l.len(3);
        const n = l.toInteger(-1) catch unreachable;
        l.pop(1);
        var index: ziglua.Integer = 1;
        // tricksy trick to `catch` only once
        _ = err: {
            while (index <= n) : (index += 1) {
                switch (l.getIndex(3, index)) {
                    .nil => msg.add(.{.nil}) catch |err| break :err err,
                    .boolean => {
                        msg.add(.{l.toBoolean(-1)}) catch |err| break :err err;
                        l.pop(1);
                    },
                    .string => {
                        msg.add(.{l.toString(-1) catch unreachable}) catch |err| break :err err;
                        l.pop(1);
                    },
                    .number => {
                        if (l.isInteger(-1)) {
                            msg.add(.{@as(i32, @intCast(l.toInteger(-1) catch unreachable))}) catch |err| break :err err;
                            l.pop(1);
                        } else {
                            msg.add(.{@as(f32, @floatCast(l.toNumber(-1) catch unreachable))}) catch |err| break :err err;
                            l.pop(1);
                        }
                    },
                    // other types don't make sense to send via OSC
                    inline else => |t| l.raiseErrorStr("unsupported argument type: %s", .{l.typeName(t).ptr}),
                }
            }
        } catch {
            logger.err("osc.send: unable to add arguments to message!", .{});
            return 0;
        };
    }
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
fn init(m: *Module, vm: *Spindle, allocator: std.mem.Allocator) void {
    const l = vm.l;
    const self = allocator.create(Osc) catch panic("out of memory!", .{});
    const port = lu.getConfig(l, "local_port", ?[*:0]const u8);
    var addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 0);
    self.* = .{
        .watcher = xev.UDP.init(addr) catch panic("unable to init UDP listener!", .{}),
        .server = lo.Server.new(null, lo.wrap(Osc.errHandler)) orelse panic("out of memory!", .{}),
        .lua = l,
        .s = .{ .userdata = null },
        .buffer = allocator.alloc(u8, 65535) catch panic("out of memory!", .{}),
        .last_addr = null,
        .monome = undefined,
    };
    var port_num: u16 = std.fmt.parseUnsigned(u16, std.mem.sliceTo(port orelse "7777", 0), 10) catch 7777;
    var try_again = true;
    var rand = std.rand.DefaultPrng.init(7777);
    const r = rand.random();
    while (try_again) {
        addr.setPort(port_num);
        self.watcher.bind(addr) catch {
            port_num = r.int(u16);
            continue;
        };
        try_again = false;
    }
    var buf: std.BoundedArray(u8, 256) = .{};
    std.fmt.format(buf.writer(), "{d}\x00", .{port_num}) catch unreachable;
    const slice: [:0]const u8 = buf.slice()[0 .. buf.len - 1 :0];
    lu.setConfig(l, "local_port", slice);

    const local_address = lo.Message.new() orelse panic("out of memory!", .{});
    local_address.add(.{ "127.0.0.1", @as(i32, @intCast(port_num)) }) catch panic("out of memory!", .{});
    self.monome.init(local_address);
    logger.info("local port: {s}", .{slice});

    _ = self.server.addMethod("/seamstress/quit", null, lo.wrap(setQuit), lu.getWheel(l));
    self.monome.addMethods();
    _ = self.server.addMethod(null, null, lo.wrap(defaultHandler), self);

    lu.registerSeamstress(l, "osc_send", oscSend, self);
    self.monome.registerLua(l);

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

fn launch(m: *const Module, _: *Lua, wheel: *Wheel) void {
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

const Module = @import("module.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const Seamstress = @import("seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const Wheel = @import("wheel.zig");
const Spindle = @import("spindle.zig");
const xev = @import("xev");
const lo = @import("ziglo");
const lu = @import("lua_util.zig");
const std = @import("std");
const panic = std.debug.panic;
