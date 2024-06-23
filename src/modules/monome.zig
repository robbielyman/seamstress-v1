/// module for storing and interacting with monome arc or grid devices via serialosc
const Monome = @This();

/// register lua functions
pub fn registerSeamstress(self: *Monome, l: *Lua) !void {
    self.devices = std.ArrayList(DevHandle).init(l.allocator());
    try l.newMetatable("seamstress.monome.Grid");
    l.pushLightUserdata(self);
    l.setFuncs(grid_funcs, 1);
    l.pop(1);

    try l.newMetatable("seamstress.monome.Arc");
    l.pushLightUserdata(self);
    l.setFuncs(arc_funcs, 1);
    l.pop(1);

    lu.getSeamstress(l);
    _ = l.getField(-1, "monome");
    l.remove(-2);
    _ = l.getField(-1, "Grid");
    _ = l.pushStringZ("new");
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(new(.grid)), 1);
    l.setTable(-3);
    l.pop(1);

    _ = l.getField(-1, "Arc");
    _ = l.pushStringZ("new");
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(new(.arc)), 1);
    l.setTable(-3);
    l.pop(2);
}

serialosc_address: *lo.Address,
local_address: *lo.Message,
devices: std.ArrayList(DevHandle),

const DevHandle = struct {
    handle: i32,
    addr: std.net.Address,
};

const Device = struct {
    connected: bool = false,
    m_type: enum { grid, arc },
    rows: u8 = 0,
    cols: u8 = 0,
    data: [4][64]i32,
    dirty: [4]bool = .{ true, true, true, true },
    quads: enum { one, two, four } = .two,
    rotation: enum { zero, ninety, one_eighty, two_seventy } = .zero,
    index: ?usize = null,
};

pub fn init(self: *Monome, local_address: *lo.Message) void {
    self.* = .{
        .serialosc_address = lo.Address.new("127.0.0.1", "12002") orelse panic("out of memory!", .{}),
        .local_address = local_address,
        .devices = undefined,
    };
    const osc: *Osc = @fieldParentPtr("monome", self);
    const paths: [7][:0]const u8 = .{
        "*/enc/delta",
        "*/enc/key",
        "*/grid/key",
        "*/tilt",
        "/sys/size",
        "/sys/rotation",
        "/sys/prefix",
    };
    const typespecs: [7][:0]const u8 = .{ "ii", "ii", "iii", "iiii", "ii", "i", "s" };
    const methods: [7]lo.MethodHandler = .{
        delta,
        arcKey,
        gridKey,
        tilt,
        handleSize,
        handleRotation,
        handlePrefix,
    };
    inline for (paths, typespecs, methods) |path, typespec, method|
        _ = osc.server.addMethod(path, typespec, lo.wrap(method), self);
    _ = osc.server.addMethod("/serialosc/add", "ssi", lo.wrap(handleAdd), self);
    _ = osc.server.addMethod("/serialosc/device", "ssi", lo.wrap(handleAdd), self);
    _ = osc.server.addMethod("/serialosc/remove", "ssi", lo.wrap(handleRemove), self);
}

fn new(comptime which: enum { grid, arc }) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            const device = l.newUserdata(Device, 4);
            device.* = .{
                .m_type = switch (which) {
                    .grid => .grid,
                    .arc => .arc,
                },
                .data = undefined,
            };
            _ = l.getMetatableRegistry("seamstress.monome.Grid");
            l.setMetatable(-2);
            l.pushNil();
            l.setUserValue(-2, 1) catch unreachable;
            l.pushNil();
            l.setUserValue(-2, 2) catch unreachable;
            l.pushNil();
            l.setUserValue(-2, 3) catch unreachable;
            l.newTable();
            l.setUserValue(-2, 4) catch unreachable;
            return 1;
        }
    }.f;
}

const grid_funcs: []const ziglua.FnReg = &.{
    .{ .name = "led", .func = ziglua.wrap(gridLed) },
    .{ .name = "all", .func = ziglua.wrap(allLed) },
    .{ .name = "rotation", .func = ziglua.wrap(gridRotation) },
    .{ .name = "intensity", .func = ziglua.wrap(gridIntensity) },
    .{ .name = "refresh", .func = ziglua.wrap(gridRefresh) },
    .{ .name = "tiltEnable", .func = ziglua.wrap(gridTiltSensor) },
    .{ .name = "__index", .func = ziglua.wrap(gridIndex) },
    .{ .name = "__newindex", .func = ziglua.wrap(gridNewIndex) },
};

const arc_funcs: []const ziglua.FnReg = &.{
    .{ .name = "led", .func = ziglua.wrap(arcLed) },
    .{ .name = "all", .func = ziglua.wrap(allLed) },
    .{ .name = "refresh", .func = ziglua.wrap(arcRefresh) },
    .{ .name = "__index", .func = ziglua.wrap(arcIndex) },
    .{ .name = "__newindex", .func = ziglua.wrap(arcNewIndex) },
};

fn arcNewIndex(l: *Lua) i32 {
    _ = l.checkUserdata(Device, 1, "seamstress.monome.Arc");
    switch (l.typeOf(2)) {
        .string => {
            const key = l.toString(2) catch unreachable;
            inline for (arc_fields ++ arc_methods ++ .{ "name", "serial", "prefix" }) |field| {
                if (std.mem.eql(u8, key, field)) l.raiseErrorStr("cannot modify field %s", .{field.ptr});
            }
        },
        else => {},
    }
    _ = l.getUserValue(1, 4) catch unreachable; // data
    l.pushValue(2);
    l.pushValue(3);
    l.setTable(-3);
    return 0;
}

fn gridNewIndex(l: *Lua) i32 {
    _ = l.checkUserdata(Device, 1, "seamstress.monome.Grid");
    switch (l.typeOf(2)) {
        .string => {
            const key = l.toString(2) catch unreachable;
            inline for (grid_fields ++ grid_methods ++ .{ "name", "serial", "prefix" }) |field| {
                if (std.mem.eql(u8, key, field)) l.raiseErrorStr("cannot modify field %s", .{field.ptr});
            }
        },
        else => {},
    }
    _ = l.getUserValue(1, 4) catch unreachable; // data
    l.pushValue(2);
    l.pushValue(3);
    l.setTable(-3);
    return 0;
}

const arc_fields: [1][:0]const u8 = .{"connected"};
const arc_methods: [3][:0]const u8 = .{ "led", "all", "refresh" };
const arc_fallback: [2][:0]const u8 = .{ "delta", "key" };

/// responds to arc name, serial, etc
fn arcIndex(l: *Lua) i32 {
    const device = l.checkUserdata(Device, 1, "seamstress.monome.Arc");
    switch (l.typeOf(2)) {
        .string => {
            const key = l.toString(2) catch unreachable;
            inline for (arc_fields) |field| {
                if (std.mem.eql(u8, field, key)) {
                    l.pushAny(@field(device, field)) catch unreachable;
                    return 1;
                }
            }
            for (arc_methods) |method| {
                if (std.mem.eql(u8, method, key)) {
                    _ = l.getMetaField(1, method) catch unreachable;
                    return 1;
                }
            }
            if (std.mem.eql(u8, "name", key)) {
                _ = l.getUserValue(1, 1) catch unreachable;
                return 1;
            }
            if (std.mem.eql(u8, "serial", key)) {
                _ = l.getUserValue(1, 2) catch unreachable;
                return 1;
            }
            if (std.mem.eql(u8, "prefix", key)) {
                _ = l.getUserValue(1, 3) catch unreachable;
                return 1;
            }
            _ = l.getUserValue(1, 4) catch unreachable; // data
            _ = l.getField(-1, key);
            inline for (arc_fallback) |function| {
                if (std.mem.eql(u8, function, key)) {
                    const t = l.typeOf(-1);
                    switch (t) {
                        .function => return 1,
                        .table, .userdata => {
                            if ((l.getMetaField(-1, "__call") catch .nil) == .function) {
                                l.pop(1);
                                return 1;
                            }
                            l.pop(2);
                        },
                        else => l.pop(1),
                    }
                    l.pushFunction(ziglua.wrap(postEvent(&.{ "monome", "arc", function })));
                    return 1;
                }
            }
            return 1;
        },
        else => {
            _ = l.getUserValue(1, 5) catch unreachable;
            l.pushValue(2);
            _ = l.getTable(-2);
            return 1;
        },
    }
}

const grid_fields: [3][:0]const u8 = .{ "connected", "cols", "rows" };
const grid_methods: [6][:0]const u8 = .{ "led", "all", "rotation", "intensity", "refresh", "tiltEnable" };
const grid_fallback: [2][:0]const u8 = .{ "tilt", "key" };

/// responds to grid.rows, grid.cols, name, serial, etc
fn gridIndex(l: *Lua) i32 {
    const device = l.checkUserdata(Device, 1, "seamstress.monome.Grid");
    switch (l.typeOf(2)) {
        .string => {
            const key = l.toString(2) catch unreachable;
            inline for (grid_fields) |field| {
                if (std.mem.eql(u8, field, key)) {
                    l.pushAny(@field(device, field)) catch unreachable;
                    return 1;
                }
            }
            if (std.mem.eql(u8, "quads", key)) {
                l.pushInteger(switch (device.quads) {
                    .one => 1,
                    .two => 2,
                    .four => 4,
                });
                return 1;
            }
            for (grid_methods) |method| {
                if (std.mem.eql(u8, method, key)) {
                    _ = l.getMetaField(1, method) catch unreachable;
                    return 1;
                }
            }
            if (std.mem.eql(u8, "name", key)) {
                _ = l.getUserValue(1, 1) catch unreachable;
                return 1;
            }
            if (std.mem.eql(u8, "serial", key)) {
                _ = l.getUserValue(1, 2) catch unreachable;
                return 1;
            }
            if (std.mem.eql(u8, "prefix", key)) {
                _ = l.getUserValue(1, 3) catch unreachable;
                return 1;
            }

            _ = l.getUserValue(1, 4) catch unreachable; // data
            _ = l.getField(-1, key);
            inline for (grid_fallback) |function| {
                if (std.mem.eql(u8, function, key)) {
                    const t = l.typeOf(-1);
                    switch (t) {
                        .function => return 1,
                        .table, .userdata => {
                            if ((l.getMetaField(-1, "__call") catch .nil) == .function) {
                                l.pop(1);
                                return 1;
                            }
                            l.pop(2);
                        },
                        else => l.pop(1),
                    }
                    l.pushFunction(ziglua.wrap(postEvent(&.{ "monome", "grid", function })));
                    return 1;
                }
            }
            return 1;
        },
        else => {
            _ = l.getUserValue(1, 5) catch unreachable;
            l.pushValue(2);
            _ = l.getTable(-2);
            return 1;
        },
    }
}

/// default key / tilt / delta handler
fn postEvent(comptime namespace: []const []const u8) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            const args = l.getTop();
            lu.preparePublish(l, namespace);
            var i: i32 = 1;
            while (i <= args) : (i += 1) {
                l.pushValue(-args - 2);
            }
            l.call(args + 1, 0);
            return 0;
        }
    }.f;
}

pub fn deinit(self: *Monome) void {
    self.local_address.free();
    self.serialosc_address.free();
    self.devices.deinit();
}

fn loAddressFromNetAddress(addr: std.net.Address) ?*lo.Address {
    var buf: std.BoundedArray(u8, 1024) = .{};
    addr.format("", .{}, buf.writer()) catch return null;
    const slice = buf.slice();
    const idx = std.mem.lastIndexOfScalar(u8, slice, ':').?;
    var mem: [2048]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const a = fba.allocator();
    const host = a.dupeZ(u8, slice[0..idx]) catch return null;
    const port = a.dupeZ(u8, slice[idx + 1 ..]) catch return null;
    return lo.Address.new(host, port);
}

/// sends /sys/info to serialosc
fn getInfo(self: *Monome, id: usize) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    const addr = loAddressFromNetAddress(self.devices.items[id].addr) orelse return error.AddressCreationFailed;
    defer addr.free();
    osc.server.send(addr, "/sys/info", self.local_address) catch return error.MessageSendFailed;
}

/// set's the device's port to us
fn setPort(self: *Monome, id: usize) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    const addr = loAddressFromNetAddress(self.devices.items[id].addr) orelse return error.AddressCreationFailed;
    defer addr.free();
    const msg = lo.Message.new() orelse return error.MessageCreationFailed;
    defer msg.free();
    msg.add(.{self.local_address.getArg(i32, 1) catch unreachable}) catch unreachable;
    osc.server.send(addr, "/sys/port", msg) catch return error.MessageSendFailed;
}

/// tells lua to add or remove a device
fn addOrRemove(l: *Lua, idx: usize, monome: *Monome) void {
    const top = l.getTop();
    defer std.debug.assert(top == l.getTop());
    _ = l.rawGetIndex(ziglua.registry_index, monome.devices.items[idx].handle);
    const device = l.toUserdata(Device, -1) catch unreachable;
    const is_add = device.connected;
    const m_type = device.m_type;
    lu.getSeamstress(l);
    _ = l.getField(-1, "monome");
    l.remove(-2);
    _ = l.getField(-1, switch (m_type) {
        .grid => "Grid",
        .arc => "Arc",
    });
    l.remove(-2);
    _ = l.getField(-1, if (is_add) "add" else "remove");
    l.remove(-2);
    l.rotate(-2, 1); // put the function below device
    lu.doCall(l, 1, 0);
}

/// pub so that it can be called from osc.zig
pub fn sendList(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(self.serialosc_address, "/serialosc/list", self.local_address) catch {
        logger.err("error sending /serialosc/list!", .{});
    };
    self.sendNotify();
}

/// asks serialosc to send updates
fn sendNotify(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(self.serialosc_address, "/serialosc/notify", self.local_address) catch {
        logger.err("error sending /serialosc/notify!", .{});
    };
}

// the "inner" responder to a remove message.
fn remove(self: *Monome, port: i32) !void {
    const handle, const idx = handle: {
        for (self.devices.items, 0..) |handle, idx|
            if (port == handle.addr.getPort()) break :handle .{ handle, idx };
        return error.NotFound;
    };
    const osc: *Osc = @fieldParentPtr("monome", self);
    _ = osc.lua.rawGetIndex(ziglua.registry_index, handle.handle);
    defer osc.lua.pop(1);
    const device = try osc.lua.toUserdata(Device, -1);
    device.connected = false;
    // let's tell lua to remove this device
    return addOrRemove(osc.lua, idx, self);
}

// the "inner" responder to an add message.
fn add(self: *Monome, id: [:0]const u8, m_type: [:0]const u8, port: i32) !void {
    logger.info("new device: {s}, {s}, at port {d}", .{ id, m_type, port });
    const osc: *Osc = @fieldParentPtr("monome", self);
    const idx: ?usize = idx: {
        for (self.devices.items, 0..) |handle, idx|
            if (handle.addr.getPort() == port) break :idx idx;
        break :idx null;
    };
    if (idx) |index| {
        _ = osc.lua.rawGetIndex(ziglua.registry_index, self.devices.items[index].handle);
        defer osc.lua.pop(1);
        const device = try osc.lua.toUserdata(Device, -1);
        device.connected = true;
        return addOrRemove(osc.lua, index, self);
    }
    const handle = try self.devices.addOne();
    if (port < 0) return error.BadPort;
    const l = osc.lua;
    const device = l.newUserdata(Device, 4);
    device.index = self.devices.items.len - 1;
    l.pushValue(-1);
    handle.handle = try l.ref(ziglua.registry_index);
    // set the device type: an arc is a device that calls itself an arc
    device.m_type = if (std.mem.indexOf(u8, m_type, "arc")) |_| .arc else .grid;
    _ = l.getMetatableRegistry(switch (device.m_type) {
        .grid => "seamstress.monome.Grid",
        .arc => "seamstress.monome.Arc",
    });
    l.setMetatable(-2);
    // push the name
    _ = l.pushStringZ(m_type);
    l.setUserValue(-2, 1) catch unreachable;
    // push the serial
    _ = l.pushStringZ(id);
    l.setUserValue(-2, 2) catch unreachable;
    l.newTable();
    l.setUserValue(-2, 4) catch unreachable;
    // set the address
    handle.addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, @intCast(port));
    device.quads = .four;
    // we actually add the device from the `size` handler
    try self.getInfo(self.devices.items.len - 1);
    try self.setPort(self.devices.items.len - 1);
    for (&device.data) |*ptr| {
        @memset(ptr, 0);
    }
    device.rotation = .zero;
    device.connected = true;
}

// responds to /serialosc/remove messages
fn handleRemove(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx.?));
    defer self.sendNotify();
    const port = msg.getArg(i32, 2) catch return true;
    self.remove(port) catch |err| {
        logger.err("error removing device at port {d}: {s}", .{ port, @errorName(err) });
        return true;
    };
    return false;
}

// responds to /serialosc/device and /serialosc/add messages
fn handleAdd(path: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
    // if what we got was an /add message, finish out by requesting that we continue getting them
    defer if (std.mem.eql(u8, "/serialosc/add", path)) self.sendNotify();
    const id = msg.getArg([:0]const u8, 0) catch return true;
    const m_type = msg.getArg([:0]const u8, 1) catch return true;
    const port = msg.getArg(i32, 2) catch return true;
    self.add(id, m_type, port) catch |err| {
        logger.err("error adding device {s} at port {d}: {s}", .{ id, port, @errorName(err) });
        return true;
    };
    return false;
}

// responds to /sys/prefix
fn handlePrefix(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx.?));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: message must have typespec s
    const prefix = msg.getArg([:0]const u8, 0) catch unreachable;
    for (self.devices.items) |handle| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            _ = l.pushStringZ(prefix);
            l.setUserValue(-2, 3) catch unreachable;
            return false;
        }
    }
    return true;
}

// responds to /sys/rotation
fn handleRotation(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx.?));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: message must have typespec i
    const degs = msg.getArg(i32, 0) catch unreachable;
    for (self.devices.items) |handle| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            const device = l.toUserdata(Device, -1) catch unreachable;
            device.rotation = switch (degs) {
                0 => .zero,
                90 => .ninety,
                180 => .one_eighty,
                270 => .two_seventy,
                else => unreachable,
            };
            return false;
        }
    }
    return true;
}

// responds to /sys/size; adds the device on the lua side
fn handleSize(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx.?));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: message must have typespec ii
    for (self.devices.items, 0..) |handle, idx| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            const device = l.toUserdata(Device, -1) catch unreachable;
            const rows = msg.getArg(i32, 0) catch unreachable;
            const cols = msg.getArg(i32, 1) catch unreachable;
            device.rows = @min(@max(0, rows), 255);
            device.cols = @min(@max(0, cols), 255);
            device.quads = switch (@divExact(rows * cols, 64)) {
                0 => .four, // this is an arc
                1 => .one,
                2 => .two,
                4 => .four,
                else => unreachable,
            };
            addOrRemove(osc.lua, idx, self);
            return false;
        }
    }
    return true;
}

/// handles a grid key event
fn gridKey(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx.?));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: the message must be of type iii
    const x = msg.getArg(i32, 0) catch unreachable;
    const y = msg.getArg(i32, 1) catch unreachable;
    const z = msg.getArg(i32, 2) catch unreachable;
    for (self.devices.items) |handle| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            _ = l.getField(-1, "key");
            // convert from 0-indexed
            osc.lua.pushInteger(x + 1);
            osc.lua.pushInteger(y + 1);
            // already 0 or 1
            osc.lua.pushInteger(z);
            lu.doCall(osc.lua, 3, 0);
            return false;
        }
    }
    return true;
}

/// handles an arc delta event
fn delta(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx.?));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: the message must be of type ii
    const n = msg.getArg(i32, 0) catch unreachable;
    const d = msg.getArg(i32, 1) catch unreachable;
    for (self.devices.items) |handle| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            _ = l.getField(-1, "delta");
            // convert from 0-indexed
            osc.lua.pushInteger(n + 1);
            // correctly 0-indexed
            osc.lua.pushInteger(d);
            osc.lua.call(2, 0);
            return false;
        }
    }
    return true;
}

/// handles a grid tilt event
fn tilt(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: the message must be of type iiii
    const n = msg.getArg(i32, 0) catch unreachable;
    const x = msg.getArg(i32, 1) catch unreachable;
    const y = msg.getArg(i32, 2) catch unreachable;
    const z = msg.getArg(i32, 3) catch unreachable;
    for (self.devices.items) |handle| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            _ = l.getField(-1, "delta");
            // convert from 0-indexed
            osc.lua.pushInteger(n + 1);
            // correctly 0-indexed
            osc.lua.pushInteger(x);
            osc.lua.pushInteger(y);
            osc.lua.pushInteger(z);
            lu.doCall(osc.lua, 4, 0);
            return false;
        }
    }
    return true;
}

/// hndles an arc key event
fn arcKey(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
    const osc: *Osc = @fieldParentPtr("monome", self);
    // catch unreachable is valid: the message must be of type ii
    const n = msg.getArg(i32, 0) catch unreachable;
    const z = msg.getArg(i32, 1) catch unreachable;
    for (self.devices.items) |handle| {
        if (osc.last_addr.?.eql(handle.addr)) {
            const l = osc.lua;
            _ = l.rawGetIndex(ziglua.registry_index, handle.handle);
            defer l.pop(1);
            _ = l.getField(-1, "key");
            // convert from 0-indexed
            osc.lua.pushInteger(n + 1);
            // correctly 0 or 1
            osc.lua.pushInteger(z);
            lu.doCall(osc.lua, 2, 0);
            return false;
        }
    }
    return true;
}

/// set grid led
fn gridLed(l: *Lua) i32 {
    lu.checkNumArgs(l, 4);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    // let's be nice; accept numbers as well as integers
    const x: ziglua.Integer = x: {
        if (l.isInteger(2)) break :x l.checkInteger(2);
        break :x @intFromFloat(l.checkNumber(2));
    };
    const y: ziglua.Integer = y: {
        if (l.isInteger(3)) break :y l.checkInteger(3);
        break :y @intFromFloat(l.checkNumber(3));
    };
    const val: ziglua.Integer = val: {
        if (l.isInteger(4)) break :val l.checkInteger(4);
        break :val @intFromFloat(l.checkNumber(4));
    };
    // FIXME: if there are grids out there with more than 16 rows or columns, they'll be sad about this
    const x_w: u4 = @intCast(x - 1 % 16);
    const y_w: u4 = @intCast(y - 1 % 16);
    const idx = quadIdx(x_w, y_w);
    // let's be nice; saturate at the edges
    device.data[idx][quadOffset(x_w, y_w)] = @min(@max(0, val), 15);
    device.dirty[idx] = true;
    return 0;
}

/// set arc led
fn arcLed(l: *Lua) i32 {
    lu.checkNumArgs(l, 4);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    // let's be nice; accept numbers as well as integers
    const n: ziglua.Integer = n: {
        if (l.isInteger(2)) break :n l.checkInteger(2);
        break :n @intFromFloat(l.checkNumber(2));
    };
    const led: ziglua.Integer = led: {
        if (l.isInteger(3)) break :led l.checkInteger(3);
        break :led @intFromFloat(l.checkNumber(3));
    };
    const val: ziglua.Integer = val: {
        if (l.isInteger(4)) break :val l.checkInteger(4);
        break :val @intFromFloat(l.checkNumber(4));
    };
    // let's be nice; saturate at the edges;
    const n_w: u4 = @min(@max((n - 1), 0), 3);
    // let's be nice; wrap at the edges;
    const led_w: u6 = @intCast(@abs(led - 1) % 64);
    // let's be nice; saturate at the edges
    device.data[n_w][led_w] = @min(@max(0, val), 15);
    device.dirty[n_w] = true;
    return 0;
}

/// sets all leds
fn allLed(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    // let's be nice; accept numbers as well as integers
    const val: ziglua.Integer = val: {
        if (l.isInteger(2)) break :val l.checkInteger(2);
        break :val @intFromFloat(l.checkNumber(2));
    };
    inline for (0..4) |q| {
        // let's be nice; saturate at the edges
        @memset(&device.data[q], @min(@max(0, val), 15));
    }
    @memset(&device.dirty, true);
    return 0;
}

fn quadIdx(x: u4, y: u4) u8 {
    return switch (y) {
        0...7 => switch (x) {
            0...7 => 0,
            8...15 => 1,
        },
        8...15 => switch (x) {
            0...7 => 2,
            8...15 => 3,
        },
    };
}

fn quadOffset(x: u4, y: u4) u8 {
    return (@as(u8, (y & 7)) * 8) + (x & 7);
}

/// set grid rotation
fn gridRotation(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const monome = lu.closureGetContext(l, Monome);
    const osc: *Osc = @fieldParentPtr("monome", monome);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    const rotation = l.checkInteger(2);
    l.argCheck(rotation == 0 or
        rotation == 1 or
        rotation == 2 or
        rotation == 3 or
        rotation == 90 or
        rotation == 180 or
        rotation == 270, 2, "rotation must be 0, 90, 180 or 270");
    const msg = lo.Message.new() orelse {
        logger.err("error creating message!", .{});
        return 0;
    };
    defer msg.free();
    switch (rotation) {
        0 => {
            device.rotation = .zero;
            msg.add(.{0}) catch return 0;
        },
        1, 90 => {
            device.rotation = .ninety;
            msg.add(.{90}) catch return 0;
        },
        2, 180 => {
            device.rotation = .one_eighty;
            msg.add(.{180}) catch return 0;
        },
        3, 270 => {
            device.rotation = .two_seventy;
            msg.add(.{270}) catch return 0;
        },
        else => unreachable,
    }
    if (device.index) |idx| {
        const addr = loAddressFromNetAddress(monome.devices.items[idx].addr) orelse {
            logger.err("error creating address!", .{});
            return 0;
        };
        defer addr.free();
        osc.server.send(addr, "/sys/rotation", msg) catch {
            logger.err("error sending /sys/rotation!", .{});
        };
    }
    return 0;
}

/// enable / disable tilt sensor
fn gridTiltSensor(l: *Lua) i32 {
    lu.checkNumArgs(l, 3);
    const monome = lu.closureGetContext(l, Monome);
    const osc: *Osc = @fieldParentPtr("monome", monome);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    const sensor: i32 = @intCast(l.checkInteger(2));
    const enable = l.toBoolean(3);
    const msg = lo.Message.new() orelse {
        logger.err("error creating message!", .{});
        return 0;
    };
    defer msg.free();
    msg.add(.{ sensor, @as(i32, if (enable) 1 else 0) }) catch return 0;
    const index = device.index orelse return 0;
    if (l.getUserValue(-1, 3) catch unreachable != .string) l.raiseErrorStr("unknown prefix!", .{});
    const prefix = l.toString(-1) catch unreachable;
    var buf: [512]u8 = undefined;
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/tilt/set");
    const addr = loAddressFromNetAddress(monome.devices.items[index].addr) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    osc.server.send(addr, path, msg) catch {
        logger.err("error sending /tilt/set", .{});
    };
    return 0;
}

/// limit LED intensity
fn gridIntensity(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const monome = lu.closureGetContext(l, Monome);
    const osc: *Osc = @fieldParentPtr("monome", monome);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    // let's be nice; accept numbers as well as integers
    const val: ziglua.Integer = val: {
        if (l.isInteger(2)) break :val l.checkInteger(2);
        break :val @intFromFloat(l.checkNumber(2));
    };
    const index = device.index orelse return 0;
    if (l.getUserValue(-1, 3) catch unreachable != .string) l.raiseErrorStr("unknown prefix!", .{});
    const prefix = l.toString(-1) catch unreachable;
    const msg = lo.Message.new() orelse {
        logger.err("error creating message!", .{});
        return 0;
    };
    defer msg.free();
    // let's be nice; saturate at edges
    msg.add(.{@as(i32, @min(@max(val, 0), 15))}) catch return 0;
    var buf: [512]u8 = undefined;
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/grid/led/intensity");
    const addr = loAddressFromNetAddress(monome.devices.items[index].addr) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    osc.server.send(addr, path, msg) catch {
        logger.err("error setting intensity", .{});
    };
    return 0;
}

/// pushes dirty quads to the grid
fn gridRefresh(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome);
    const osc: *Osc = @fieldParentPtr("monome", monome);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    if (l.getUserValue(-1, 3) catch unreachable != .string) l.raiseErrorStr("unknown prefix!", .{});
    const index = device.index orelse return 0;
    var buf: [512]u8 = undefined;
    const prefix = l.toString(-1) catch unreachable;
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/grid/led/level/map");
    const x_off: [4]i32 = .{ 0, 8, 0, 8 };
    const y_off: [4]i32 = .{ 0, 0, 8, 8 };
    const addr = loAddressFromNetAddress(monome.devices.items[index].addr) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    switch (device.quads) {
        .one => {
            if (!device.dirty[0]) return 0;
            const msg = lo.Message.new() orelse {
                logger.err("error creating message!", .{});
                return 0;
            };
            defer msg.free();
            msg.add(.{ 0, 0 }) catch return 0;
            msg.addSlice(i32, &device.data[0]) catch return 0;
            osc.server.send(addr, path, msg) catch {
                logger.err("error sending /led/level/map", .{});
            };
            device.dirty[0] = false;
        },
        .two => {
            const quad: [2]u2 = switch (device.rotation) {
                .zero => .{ 0, 1 },
                .ninety => .{ 0, 2 },
                .one_eighty => .{ 1, 0 },
                .two_seventy => .{ 2, 0 },
            };
            for (&quad) |i| {
                if (!device.dirty[i]) continue;
                const msg = lo.Message.new() orelse {
                    logger.err("error creating message!", .{});
                    return 0;
                };
                defer msg.free();
                msg.add(.{ x_off[i], y_off[i] }) catch return 0;
                msg.addSlice(i32, &device.data[i]) catch return 0;
                osc.server.send(addr, path, msg) catch {
                    logger.err("error sending /led/level/map", .{});
                };
                device.dirty[i] = false;
            }
        },
        // oh lol, we have four quads, let's push four quads... see if we were right
        .four => {
            for (0..4) |i| {
                if (!device.dirty[i]) continue;
                const msg = lo.Message.new() orelse {
                    logger.err("error creating message!", .{});
                    return 0;
                };
                defer msg.free();
                msg.add(.{ x_off[i], y_off[i] }) catch return 0;
                msg.addSlice(i32, &device.data[i]) catch return 0;
                osc.server.send(addr, path, msg) catch {
                    logger.err("error sending /grid/led/level/map", .{});
                };
                device.dirty[i] = false;
            }
        },
    }
    return 0;
}

/// pushes dirty quads to the arc
fn arcRefresh(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome);
    const osc: *Osc = @fieldParentPtr("monome", monome);
    _ = l.getField(1, "dev");
    const device = l.toUserdata(Device, -1) catch unreachable;
    if (l.getUserValue(-1, 3) catch unreachable != .string) l.raiseErrorStr("unknown prefix!", .{});
    const index = device.index orelse return 0;
    var buf: [512]u8 = undefined;
    const prefix = l.toString(-1) catch unreachable;
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/ring/map");
    const addr = loAddressFromNetAddress(monome.devices.items[index].addr) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    for (0..4) |i| {
        if (!device.dirty[i]) continue;
        const msg = lo.Message.new() orelse {
            logger.err("error creating message!", .{});
            return 0;
        };
        defer msg.free();
        msg.add(.{@as(i32, @intCast(i))}) catch return 0;
        msg.addSlice(i32, &device.data[i]) catch return 0;
        osc.server.send(addr, path, msg) catch {
            logger.err("error sending /ring/map", .{});
        };
        device.dirty[i] = false;
    }
    return 0;
}

/// concatenates two strings into a buffer asserting capacity
/// returns a slice of buf
fn concatIntoBufZAssumeCapacity(buf: []u8, first: []const u8, second: []const u8) [:0]const u8 {
    std.debug.assert(first.len + second.len + 1 <= buf.len);
    @memcpy(buf[0..first.len], first);
    @memcpy(buf[first.len..][0..second.len], second);
    buf[first.len + second.len] = 0;
    return buf[0 .. first.len + second.len :0];
}

const logger = std.log.scoped(.serialosc);
const Osc = @import("osc.zig");
const std = @import("std");
const lo = @import("ziglo");
const xev = @import("libxev");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("../lua_util.zig");
const Seamstress = @import("../seamstress.zig");
const panic = std.debug.panic;

test "ref" {
    _ = Monome;
}
