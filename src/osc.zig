/// OSC module

// returns the module interface
pub fn module() Module {
    return .{
        .vtable = &.{
            .init_fn = init,
            .deinit_fn = deinit,
            .launch_fn = launch,
        },
    };
}

// sets up the OSC server, using the config-provided port if it exists, otherwise using a free one
fn init(m: *Module, vm: *Spindle) Error!void {
    const self = try vm.allocator.create(Osc);
    const port = lu.getConfig(vm, "local_port", [*:0]const u8) catch null;
    self.* = .{
        .server = lo.Server.new(port, lo.wrap(errHandler)) orelse return error.LaunchFailed,
        .vm = vm,
        .path_pool = StringPool.init(vm.allocator),
        .event_pool = std.heap.MemoryPool(OscEvent).initPreheated(vm.allocator, 256) catch return error.LaunchFailed,
    };
    var buf: std.BoundedArray(u8, 1024) = .{};
    std.fmt.format(
        buf.writer(),
        "{d}\x00",
        .{self.server.getPort() catch return error.LaunchFailed},
    ) catch unreachable;
    const slice: [:0]const u8 = buf.slice()[0 .. buf.len - 1 :0];
    try lu.setConfig(vm, "local_port", slice);
    logger.info("local port: {s}", .{slice});
    m.self = self;

    _ = self.server.addMethod("/seamstress/quit", null, lo.wrap(Osc.setQuit), self);
    _ = self.server.addMethod(null, null, lo.wrap(defaultHandler), self);
    lu.registerSeamstress(vm, "osc_send", oscSend, self);
}

// starts the OSC server thread
fn launch(m: *const Module, vm: *Spindle) Error!void {
    _ = vm; // autofix
    const self: *Osc = @ptrCast(@alignCast(m.self orelse return error.LaunchFailed));
    self.pid = std.Thread.spawn(.{}, Osc.loop, .{self}) catch return error.LaunchFailed;
}

// shuts down the OSC server thread
fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    const self: *Osc = @ptrCast(@alignCast(m.self orelse return));
    defer if (cleanup == .full) {
        self.server.free();
        self.event_pool.deinit();
        self.path_pool.deinit();
        vm.allocator.destroy(self);
    };
    if (self.pid) |p| {
        var buf: [4096]u8 = undefined;
        const quit_msg = lo.Message.new() orelse {
            p.detach();
            return;
        };
        defer if (cleanup == .full) quit_msg.free();
        const data = quit_msg.serialise("/seamstress/quit", &buf) catch {
            p.detach();
            return;
        };
        self.server.dispatchData(data) catch {
            p.detach();
            return;
        };
        switch (cleanup) {
            .full => {
                p.join();
            },
            .panic, .clean => p.detach(),
        }
    }
}

// FIXME: no real way to panic on error, so let's assume they're "fine"
fn errHandler(errno: i32, msg: ?[*:0]const u8, path: ?[*:0]const u8) void {
    logger.err("liblo error {d} at {s}: {s}", .{
        errno,
        path orelse "",
        msg orelse "",
    });
}

// pub so submodules like monome.zig can access it
pub const Osc = struct {
    server: *lo.Server,
    vm: *Spindle,
    pid: ?std.Thread = null,
    path_pool: StringPool,
    event_pool: std.heap.MemoryPool(OscEvent),
    quit: bool = false,
    monome: Monome,

    // the main OSC loop
    fn loop(self: *Osc) void {
        const server = self.server;
        while (!self.quit) {
            // TODO: theoretically we could allow an infinite timeout, huh
            const ready = server.wait(1000);
            if (ready) {
                _ = server.receive() catch {
                    logger.err("OSC receive failed! shutting down OSC...", .{});
                    return;
                };
            }
        }
        self.pid = null;
    }

    fn setQuit(_: [:0]const u8, _: []const u8, _: *lo.Message, ctx: ?*anyopaque) bool {
        const osc: *Osc = @ptrCast(@alignCast(ctx orelse return true));
        osc.quit = true;
        lu.quit(osc.vm);
        return false;
    }
};

/// sends an OSC message
// users should use `osc.send` instead.
// @tparam address table|string either a table of the form {host,port}
// where `host` and `port` are both strings,
// or a string, in which case `host` is taken to be "localhost" and the string is the port
// @tparam path string an OSC path `/like/this`
// @tparam args table a list whose data is passed over OSC as arguments
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
                        msg.add(.{l.toString(-1) catch unreachable }) catch |err| break :err err;
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

// handles an OSC event by submitting it to the events queue
fn defaultHandler(path: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const osc: *Osc = @ptrCast(@alignCast(ctx orelse return true));
    const interned = osc.path_pool.intern(path) catch {
        lu.panic(osc.vm, error.OutOfMemory);
        return true;
    };
    // prevents the message from being freed until oscHandler calls free on it
    msg.incRef();
    const ev: *OscEvent = osc.event_pool.create() catch {
        lu.panic(osc.vm, error.OutOfMemory);
        return true;
    };
    ev.* = .{
        .msg = msg,
        .path = interned,
        .osc = osc,
    };
    osc.vm.events.submit(&ev.node);
    return false;
}

// event closure for default handling of OSC events
const OscEvent = struct {
    path: [:0]const u8,
    msg: *lo.Message,
    osc: *Osc,
    node: Events.Node = .{
        .handler = Events.handlerFromClosure(OscEvent, oscHandler, "node"),
    },

    // handles OSC events that aren't intercepted by another module
    // this includes custom functions registered from Lua
    // ah, whose registry we can manage entirely in Lua actually lol, nice
    fn oscHandler(self: *OscEvent) void {
        const l = self.osc.vm.lvm;
        defer {
            l.setTop(0);
            self.msg.free();
            self.osc.event_pool.destroy(self);
        }
        // push _seamstress onto the stack
        lu.getSeamstress(l);
        // grabs `osc.method_list`
        _ = l.getField(-1, "osc");
        l.remove(-2);
        _ = l.getField(-1, "method_list");
        l.remove(-2);
        // nil, to get the first key
        l.pushNil();
        // if one of our lua-defined functions returns something truthy, we stop
        var keep_going = true;
        // iterate over the key / value pairs of _seamstress.osc.method_list
        while (l.next(-2) and keep_going) {
            const t = l.typeOf(-2);
            // if the key is not a string, keep going
            if (t != .string) {
                logger.err("OSC handler: string expected, got {s}", .{l.typeName(t)});
                // remove the value, keep the key
                l.pop(1);
                continue;
            }
            // if it is, check to see if we match the path of this event
            if (lo.patternMatch(self.path, l.toString(-2) catch unreachable)) {
                // first of all, the value had better be a function or a table of functions
                const t2 = l.typeOf(-1);
                switch (t2) {
                    // if it's a function, call it
                    .function => keep_going = pushArgsAndCall(l, self.msg, self.path),
                    .table => {
                        l.len(-1);
                        // if it's a table, how long is it?
                        const len = l.toInteger(-1) catch unreachable;
                        l.pop(1);

                        var index: ziglua.Integer = 1;
                        // while loop because in Zig for loops are limited to `usize`
                        while (index <= len and keep_going) : (index += 1) {
                            const t3 = l.getIndex(-1, index);
                            if (t3 != .function) {
                                logger.err("OSC handler: function expected, got {s}", .{l.typeName(t3)});
                                l.pop(1);
                                continue;
                            }
                            keep_going = pushArgsAndCall(l, self.msg, self.path);
                        }
                    },
                    else => {
                        logger.err("OSC handler: function or list of functions expected, got {s}", .{l.typeName(t2)});
                        l.pop(1);
                        continue;
                    },
                }
            } else l.pop(1);
        }

        // if keep_going is still true, call the default handler
        if (keep_going) {
            lu.getSeamstress(l);
            _ = l.getField(-1, "osc");
            l.remove(-2);
            _ = l.getField(-1, "event");
            l.remove(-2);
            _ = pushArgsAndCall(l, self.msg, self.path);
        }
    }

    // pushes the contents of `msg` onto the stack and calls the function at the top of the stack
    // the function will receive the args as `path`, `args` (which may be an empty table) and `{from_hostname, from_port}`
    fn pushArgsAndCall(l: *Lua, msg: *lo.Message, path: [:0]const u8) bool {
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
        // should never be null
        const addr = msg.source().?;
        l.createTable(2, 0);
        // get the address
        if (addr.getHostname()) |host| {
            _ = l.pushStringZ(std.mem.sliceTo(host, 0));
            l.setIndex(-2, 1);
        } else {
            l.pushNil();
            l.setIndex(-2, 1);
        }
        // get the port
        if (addr.getPort()) |port| {
            _ = l.pushStringZ(std.mem.sliceTo(port, 0));
            l.setIndex(-2, 2);
        } else {
            l.pushNil();
            l.setIndex(-2, 2);
        }
        // call the function
        l.call(3, 1);
        defer l.pop(1);
        // if we got something truthy, that means we're done, so should return false
        return if (l.toBoolean(-1)) false else true;
    }
};

const Module = @import("module.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Spindle = @import("spindle.zig");
const StringPool = @import("string_pool.zig").StringPool(0);
const Events = @import("events.zig");
const lo = @import("ziglo");
const std = @import("std");
const logger = std.log.scoped(.osc);
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("lua_util.zig");
const Monome = @import("monome.zig");
