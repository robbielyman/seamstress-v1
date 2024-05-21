/// struct-of-arrays for storing and interacting with monome arc or grid devices
const Monome = @This();

const num_devs = 8;

serialosc_address: *lo.Address,
local_address: *lo.Message,
devices: Devices = .{},

// not sure struct-of-arrays actually buys us much, but it's fun
const Devices = struct {
    connected: [num_devs]bool = .{false} ** num_devs,
    name_buf: [num_devs][256]u8 = .{.{0} ** 256} ** num_devs,
    serial_buf: [num_devs][256]u8 = .{.{0} ** 256} ** num_devs,
    prefix_buf: [num_devs][256]u8 = .{.{0} ** 256} ** num_devs,
    m_type: [num_devs]enum { grid, arc } = undefined,
    // are there grids with more than 16 rows / cols??
    rows: [num_devs]u8 = .{0} ** num_devs,
    cols: [num_devs]u8 = .{0} ** num_devs,
    // something something store the data in the format you actually use...
    data: [num_devs][4][64]i32 = .{.{.{0} ** 64} ** 4} ** num_devs,
    dirty: [num_devs][4]bool = .{.{false} ** 4} ** num_devs,
    quads: [num_devs]enum { one, two, four } = undefined,
    rotation: [num_devs]enum { zero, ninety, one_eighty, two_seventy } = .{.zero} ** num_devs,
    dev_addr: [num_devs]?std.net.Address = .{null} ** num_devs,
    server: [num_devs]*lo.Server = undefined,
};

pub fn init(self: *Monome, local_address: *lo.Message) Error!void {
    self.* = .{
        .serialosc_address = lo.Address.new("127.0.0.1", "12002") orelse return error.LaunchFailed,
        .local_address = local_address,
    };
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
    inline for (0..num_devs) |i| {
        const methods: [7]lo.MethodHandler = .{
            delta(@intCast(i)),
            arcKey(@intCast(i)),
            gridKey(@intCast(i)),
            tilt(@intCast(i)),
            handleSize(@intCast(i)),
            handleRotation(@intCast(i)),
            handlePrefix(@intCast(i)),
        };
        self.devices.server[i] = lo.Server.new(null, lo.wrap(Osc.errHandler)) orelse return error.LaunchFailed;
        inline for (paths, typespecs, methods) |path, typespec, method| {
            _ = self.devices.server[i].addMethod(path, typespec, lo.wrap(method), self);
        }
    }
}

// register lua functions
pub fn registerLua(self: *Monome, l: *Lua) void {
    const field_names: [11][:0]const u8 = .{
        "grid_set_led",
        "arc_set_led",
        "monome_all_led",
        "grid_set_rotation",
        "grid_tilt_sensor",
        "grid_intensity",
        "grid_refresh",
        "arc_refresh",
        "grid_rows",
        "grid_cols",
        "grid_quads",
    };
    const functions: [11]ziglua.ZigFn = .{
        gridLed,
        arcLed,
        allLed,
        gridRotation,
        gridTiltSensor,
        gridIntensity,
        gridRefresh,
        arcRefresh,
        gridRows,
        gridCols,
        gridQuads,
    };
    inline for (field_names, functions) |field, f| {
        lu.registerSeamstress(l, field, f, self);
    }
}

pub fn addMethods(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    _ = osc.server.addMethod("/serialosc/add", "ssi", lo.wrap(handleAdd), self);
    _ = osc.server.addMethod("/serialosc/device", "ssi", lo.wrap(handleAdd), self);
    _ = osc.server.addMethod("/serialosc/remove", "ssi", lo.wrap(handleRemove), self);
}

pub fn deinit(self: *Monome) void {
    for (&self.devices.server) |server| {
        server.free();
    }
    self.local_address.free();
    self.serialosc_address.free();
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

// sends /sys/info to serialosc
fn getInfo(self: *Monome, id: u3) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    const addr = loAddressFromNetAddress(self.devices.dev_addr[id].?) orelse return error.AddressCreationFailed;
    defer addr.free();
    osc.server.send(addr, "/sys/info", self.local_address) catch return error.MessageSendFailed;
}

// set's the device's port to us
fn setPort(self: *Monome, id: u3) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    const addr = loAddressFromNetAddress(self.devices.dev_addr[id].?) orelse return error.AddressCreationFailed;
    defer addr.free();
    osc.server.send(addr, "/sys/port", self.local_address) catch return error.MessageSendFailed;
}

// tells lua to add or remove a device
fn addOrRemove(l: *Lua, idx: u3, monome: *Monome) void {
    const is_add = monome.devices.connected[idx];
    const m_type = monome.devices.m_type[idx];
    lu.getMethod(l, switch (m_type) {
        .grid => "grid",
        .arc => "arc",
    }, if (is_add) "add" else "remove");
    // convert to 1-based
    l.pushInteger(idx + 1);
    _ = l.pushString(std.mem.sliceTo(&monome.devices.serial_buf[idx], 0));
    _ = l.pushString(std.mem.sliceTo(&monome.devices.name_buf[idx], 0));
    lu.doCall(l, 3, 0);
}

// pub so that it can be called from osc.zig
pub fn sendList(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(self.serialosc_address, "/serialosc/list", self.local_address) catch {
        logger.err("error sending /serialosc/list!", .{});
    };
    self.sendNotify();
}

// asks serialosc to send updates
fn sendNotify(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(self.serialosc_address, "/serialosc/notify", self.local_address) catch {
        logger.err("error sending /serialosc/notify!", .{});
    };
}

// the "inner" responder to a remove message.
fn remove(self: *Monome, port: i32) !void {
    const id: u3 = id: for (&self.devices.dev_addr, 0..) |addr, i| {
        if (addr) |a| {
            const prt = a.getPort();
            if (prt == port) break :id @intCast(i);
        }
    } else return error.NotFound;
    // remove method handlers on the OSC thread
    const osc: *Osc = @fieldParentPtr("monome", self);
    self.devices.connected[id] = false;
    // let's tell lua to remove this device
    addOrRemove(osc.lua, id, self);
    return;
}

// the "inner" responder to an add message.
fn add(self: *Monome, id: [:0]const u8, m_type: [:0]const u8, port: i32) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    var idx: ?u3 = null;
    for (&self.devices.connected, &self.devices.serial_buf, 0..num_devs) |connected, *buf, i| {
        if (!connected and idx == null) idx = @intCast(i);
        if (std.mem.startsWith(u8, buf, id)) {
            idx = @intCast(i);
            break;
        }
    }
    const num = idx orelse return error.NoDevicesFree;
    if (self.devices.dev_addr[num]) |addr| reconnect: {
        if (port != addr.getPort())
            break :reconnect;
        self.devices.connected[num] = true;
        // we've already set up the device at this port, so let's tell lua to add it
        addOrRemove(osc.lua, num, self);
        return;
    }
    // this isn't a reconnect
    // overwrite the name
    if (id.len >= 256) return error.NameTooLong;
    @memset(&self.devices.serial_buf[num], 0);
    @memcpy(self.devices.serial_buf[num][0..id.len], id);
    if (m_type.len >= 256) return error.NameTooLong;
    @memset(&self.devices.name_buf[num], 0);
    @memcpy(self.devices.name_buf[num][0..m_type.len], m_type);
    if (port < 0) return error.BadPort;
    // set the address
    self.devices.dev_addr[num] = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, @intCast(port));
    // set the device type: an arc is a device that calls itself an arc
    self.devices.m_type[num] = if (std.mem.indexOf(u8, m_type, "arc")) |_| .arc else .grid;
    self.devices.quads[num] = .four;
    try self.setPort(num);
    // we actually add the device from the `size` handler
    try self.getInfo(num);
    self.devices.connected[num] = true;
}

// responds to /serialosc/device and /serialosc/add messages
fn handleRemove(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
    // if what we got was an /add message, finish out by requesting that we continue getting them
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
fn handlePrefix(comptime idx: u3) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    // the actual handler
    return struct {
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            // catch unreachable is valid: message must have typespec s
            const prefix = msg.getArg([:0]const u8, 0) catch unreachable;
            if (prefix.len >= 256) {
                logger.err("device prefix {s} too long!", .{prefix});
                return false;
            }
            @memset(&self.devices.prefix_buf[idx], 0);
            @memcpy(self.devices.prefix_buf[idx][0..prefix.len], prefix);
            return false;
        }
    }.f;
}

// responds to /sys/rotation
fn handleRotation(comptime idx: u3) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            // catch unreachable is valid: message must have typespec i
            const degs = msg.getArg(i32, 0) catch unreachable;
            switch (degs) {
                0 => self.devices.rotation[idx] = .zero,
                90 => self.devices.rotation[idx] = .ninety,
                180 => self.devices.rotation[idx] = .one_eighty,
                270 => self.devices.rotation[idx] = .two_seventy,
                else => unreachable,
            }
            return false;
        }
    }.f;
}

// responds to /sys/size; adds the device on the lua side
fn handleSize(comptime idx: u3) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            // catch unreachable is valid: message must have typespec ii
            const rows = msg.getArg(i32, 0) catch unreachable;
            const cols = msg.getArg(i32, 1) catch unreachable;
            self.devices.rows[idx] = @min(@max(0, rows), 255);
            self.devices.cols[idx] = @min(@max(0, cols), 255);
            self.devices.quads[idx] = switch (@divExact(rows * cols, 64)) {
                1 => .one,
                2 => .two,
                4 => .four,
                else => unreachable,
            };
            const osc: *Osc = @fieldParentPtr("monome", self);
            addOrRemove(osc.lua, idx, self);
            return false;
        }
    }.f;
}

/// handles a grid key event
fn gridKey(comptime idx: u8) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            const osc: *Osc = @fieldParentPtr("monome", self);
            // catch unreachable is valid: the message must be of type iii
            const x = msg.getArg(i32, 0) catch unreachable;
            const y = msg.getArg(i32, 1) catch unreachable;
            const z = msg.getArg(i32, 2) catch unreachable;
            lu.getMethod(osc.lua, "grid", "key");
            // convert from 0-indexed
            osc.lua.pushInteger(idx + 1);
            osc.lua.pushInteger(x + 1);
            osc.lua.pushInteger(y + 1);
            // already 0 or 1
            osc.lua.pushInteger(z);
            lu.doCall(osc.lua, 4, 0);
            return false;
        }
    }.f;
}

/// handles an arc delta event
fn delta(comptime idx: u8) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            const osc: *Osc = @fieldParentPtr("monome", self);
            // catch unreachable is valid: the message must be of type ii
            const n = msg.getArg(i32, 0) catch unreachable;
            const d = msg.getArg(i32, 1) catch unreachable;
            lu.getMethod(osc.lua, "arc", "delta");
            // convert from 0-indexed
            osc.lua.pushInteger(idx + 1);
            osc.lua.pushInteger(n + 1);
            // correctly 0-indexed
            osc.lua.pushInteger(d);
            lu.doCall(osc.lua, 3, 0);
            return false;
        }
    }.f;
}

/// handles a grid tilt event
fn tilt(comptime idx: u8) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            const osc: *Osc = @fieldParentPtr("monome", self);
            // catch unreachable is valid: the message must be of type iiii
            const n = msg.getArg(i32, 0) catch unreachable;
            const x = msg.getArg(i32, 1) catch unreachable;
            const y = msg.getArg(i32, 2) catch unreachable;
            const z = msg.getArg(i32, 3) catch unreachable;
            lu.getMethod(osc.lua, "grid", "tilt");
            // convert from 0-indexed
            osc.lua.pushInteger(idx + 1);
            osc.lua.pushInteger(n + 1);
            // correctly 0-indexed
            osc.lua.pushInteger(x);
            osc.lua.pushInteger(y);
            osc.lua.pushInteger(z);
            lu.doCall(osc.lua, 5, 0);
            return false;
        }
    }.f;
}

/// hndles an arc key event
fn arcKey(comptime idx: u8) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const self: *Monome = @ptrCast(@alignCast(ctx orelse return true));
            const osc: *Osc = @fieldParentPtr("monome", self);
            // catch unreachable is valid: the message must be of type ii
            const n = msg.getArg(i32, 0) catch unreachable;
            const z = msg.getArg(i32, 1) catch unreachable;
            lu.getMethod(osc.lua, "arc", "key");
            // convert from 0-indexed
            osc.lua.pushInteger(idx + 1);
            osc.lua.pushInteger(n + 1);
            // correctly 0 or 1
            osc.lua.pushInteger(z);
            lu.doCall(osc.lua, 3, 0);
            return false;
        }
    }.f;
}

/// set grid led
// users should use `grid:led` instead.
// @tparam integer id (1-8); identifies the grid
// @tparam integer x x-coordinate (1-based)
// @tparam integer y y-coordinate (1-based)
// @tparam integer val (0-15); level
// @see grid:led
// @function grid_set_led
fn gridLed(l: *Lua) i32 {
    lu.checkNumArgs(l, 4);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const id = l.checkInteger(1);
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
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    // FIXME: if there are grids out there with more than 16 rows or columns, they'll be sad about this
    const x_w: u4 = @intCast(x - 1 % 16);
    const y_w: u4 = @intCast(y - 1 % 16);
    const idx = quadIdx(x_w, y_w);
    // let's be nice; saturate at the edges
    monome.devices.data[num][idx][quadOffset(x_w, y_w)] = @min(@max(0, val), 15);
    return 0;
}

/// set arc led
// users should use `arc:led` instead.
// @tparam integer id (1-8); identifies the arc
// @tparam integer n ring (1-based)
// @tparam integer led (1-based)
// @tparam integer val (0-15); level
// @see arc:led
// @function arc_set_led
fn arcLed(l: *Lua) i32 {
    lu.checkNumArgs(l, 4);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const id = l.checkInteger(1);
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
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    // let's be nice; saturate at the edges;
    const n_w: u4 = @min(@max((n - 1), 0), 3);
    // let's be nice; wrap at the edges;
    const led_w: u4 = @intCast(@abs(led - 1) % 64);
    // let's be nice; saturate at the edges
    monome.devices.data[num][n_w][led_w] = @min(@max(0, val), 15);
    monome.devices.dirty[num][n_w] = true;
    return 0;
}

/// sets all leds
// users should use `grid:all` or `arc:all` instead.
// @tparam integer id (1-8); identifies the grid
// @tparam val (0-15); level
// @see grid:all, arc:all
// @function monome_all_led
fn allLed(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const id = l.checkInteger(1);
    // let's be nice; accept numbers as well as integers
    const val: ziglua.Integer = val: {
        if (l.isInteger(2)) break :val l.checkInteger(2);
        break :val @intFromFloat(l.checkNumber(2));
    };
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    inline for (0..4) |q| {
        // let's be nice; saturate at the edges
        @memset(&monome.devices.data[num][q], @min(@max(0, val), 15));
    }
    @memset(&monome.devices.dirty[num], true);
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
// users should use `grid:rotation` instead.
// @tparam integer id (1-8); identifies the grid
// @tparam integer val (0, 90, 180, 270) rotation value in degrees
// @see grid:rotation
// @function grid_set_rotation
fn gridRotation(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const osc: *Osc = @fieldParentPtr("monome", monome);
    const id = l.checkInteger(1);
    const rotation = l.checkInteger(2);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    l.argCheck(rotation == 0 or
        rotation == 1 or
        rotation == 2 or
        rotation == 3 or
        rotation == 90 or
        rotation == 180 or
        rotation == 270, 2, "rotation must be 0, 90, 180 or 270");
    const num: u3 = @intCast(id - 1);
    const msg = lo.Message.new() orelse {
        logger.err("error creating message!", .{});
        return 0;
    };
    defer msg.free();
    switch (rotation) {
        0 => {
            monome.devices.rotation[num] = .zero;
            msg.add(.{0}) catch return 0;
        },
        1, 90 => {
            monome.devices.rotation[num] = .ninety;
            msg.add(.{90}) catch return 0;
        },
        2, 180 => {
            monome.devices.rotation[num] = .one_eighty;
            msg.add(.{180}) catch return 0;
        },
        3, 270 => {
            monome.devices.rotation[num] = .two_seventy;
            msg.add(.{270}) catch return 0;
        },
        else => unreachable,
    }
    const addr = loAddressFromNetAddress(monome.devices.dev_addr[num].?) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    osc.server.send(addr, "/sys/rotation", msg) catch {
        logger.err("error sending /sys/rotation!", .{});
    };
    return 0;
}

/// enable / disable tilt sensor
// users should use `grid:tilt_sensor`
// @tparam integer id (1-8); identifies the grid
// @tparam integer sensor (1-based)
// @tparam bool enable enable/disable flag
// @see grid:tilt_sensor
// @function grid_tilt_sensor
fn gridTiltSensor(l: *Lua) i32 {
    lu.checkNumArgs(l, 3);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const osc: *Osc = @fieldParentPtr("monome", monome);
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const sensor: i32 = @intCast(l.checkInteger(2));
    const enable = l.toBoolean(3);
    const num: u3 = @intCast(id - 1);
    const msg = lo.Message.new() orelse {
        logger.err("error creating message!", .{});
        return 0;
    };
    defer msg.free();
    msg.add(.{ sensor, @as(i32, if (enable) 1 else 0) }) catch return 0;
    var buf: [512]u8 = undefined;
    const prefix = std.mem.sliceTo(&monome.devices.prefix_buf[num], 0);
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/tilt/set");
    const addr = loAddressFromNetAddress(monome.devices.dev_addr[num].?) orelse {
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
// users should use `grid:intensity`
// @tparam integer id (1-8); identifies the grid
// @tparam integer level (0-15)
// @see grid:intensity
// @function grid_intensity
fn gridIntensity(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const osc: *Osc = @fieldParentPtr("monome", monome);
    const id = l.checkInteger(1);
    // let's be nice; accept numbers as well as integers
    const val: ziglua.Integer = val: {
        if (l.isInteger(2)) break :val l.checkInteger(2);
        break :val @intFromFloat(l.checkNumber(2));
    };
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    const msg = lo.Message.new() orelse {
        logger.err("error creating message!", .{});
        return 0;
    };
    defer msg.free();
    // let's be nice; saturate at edges
    msg.add(.{@as(i32, @min(@max(val, 0), 15))}) catch return 0;
    var buf: [512]u8 = undefined;
    const prefix = std.mem.sliceTo(&monome.devices.prefix_buf[num], 0);
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/grid/led/intensity");
    const addr = loAddressFromNetAddress(monome.devices.dev_addr[num].?) orelse {
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
// users should use `grid:refresh()` instead
// @tparam integer id (1-8); identifies the device
// @see grid:refresh
// @function grid_refresh
fn gridRefresh(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const osc: *Osc = @fieldParentPtr("monome", monome);
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);

    var buf: [512]u8 = undefined;
    const prefix = std.mem.sliceTo(&monome.devices.prefix_buf[num], 0);
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/grid/led/level/map");
    const x_off: [4]i32 = .{ 0, 8, 0, 8 };
    const y_off: [4]i32 = .{ 0, 0, 8, 8 };
    const addr = loAddressFromNetAddress(monome.devices.dev_addr[num].?) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    switch (monome.devices.quads[num]) {
        .one => {
            if (!monome.devices.dirty[num][0]) return 0;
            const msg = lo.Message.new() orelse {
                logger.err("error creating message!", .{});
                return 0;
            };
            defer msg.free();
            msg.add(.{ 0, 0 }) catch return 0;
            msg.addSlice(i32, &monome.devices.data[num][0]) catch return 0;
            osc.server.send(addr, path, msg) catch {
                logger.err("error sending /led/level/map", .{});
            };
            monome.devices.dirty[num][0] = false;
        },
        .two => {
            const quad: [2]u2 = switch (monome.devices.rotation[num]) {
                .zero => .{ 0, 1 },
                .ninety => .{ 0, 2 },
                .one_eighty => .{ 1, 0 },
                .two_seventy => .{ 2, 0 },
            };
            for (&quad) |i| {
                if (!monome.devices.dirty[num][i]) continue;
                const msg = lo.Message.new() orelse {
                    logger.err("error creating message!", .{});
                    return 0;
                };
                defer msg.free();
                msg.add(.{ x_off[i], y_off[i] }) catch return 0;
                msg.addSlice(i32, &monome.devices.data[num][i]) catch return 0;
                osc.server.send(addr, path, msg) catch {
                    logger.err("error sending /led/level/map", .{});
                };
                monome.devices.dirty[num][i] = false;
            }
        },
        // oh lol, we have four quads, let's push four quads... see if we were right
        .four => {
            for (0..4) |i| {
                if (!monome.devices.dirty[num][i]) continue;
                const msg = lo.Message.new() orelse {
                    logger.err("error creating message!", .{});
                    return 0;
                };
                defer msg.free();
                msg.add(.{ x_off[i], y_off[i] }) catch return 0;
                msg.addSlice(i32, &monome.devices.data[num][i]) catch return 0;
                osc.server.send(addr, path, msg) catch {
                    logger.err("error sending /grid/led/level/map", .{});
                };
                monome.devices.dirty[num][i] = false;
            }
        },
    }
    return 0;
}

/// pushes dirty quads to the arc
// users should use `arc:refresh()` instead
// @tparam integer id (1-8); identifies the device
// @see arc:refresh
// @function arc_refresh
fn arcRefresh(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const osc: *Osc = @fieldParentPtr("monome", monome);
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);

    var buf: [512]u8 = undefined;
    const prefix = std.mem.sliceTo(&monome.devices.prefix_buf[num], 0);
    const path = concatIntoBufZAssumeCapacity(&buf, prefix, "/ring/map");
    const addr = loAddressFromNetAddress(monome.devices.dev_addr[num].?) orelse {
        logger.err("error creating address!", .{});
        return 0;
    };
    defer addr.free();
    for (0..4) |i| {
        if (!monome.devices.dirty[num][i]) continue;
        const msg = lo.Message.new() orelse {
            logger.err("error creating message!", .{});
            return 0;
        };
        defer msg.free();
        msg.add(.{@as(i32, @intCast(i))}) catch return 0;
        msg.addSlice(i32, &monome.devices.data[num][i]) catch return 0;
        osc.server.send(addr, path, msg) catch {
            logger.err("error sending /ring/map", .{});
        };
        monome.devices.dirty[num][i] = false;
    }
    return 0;
}

/// reports number of rows of grid device.
// @tparam integer id (1-8); identifies the device
// @function grid_rows
fn gridRows(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    // push the number of rows
    l.pushInteger(monome.devices.rows[num]);
    // return it
    return 1;
}

/// reports number of cols of grid device.
// @tparam integer id (1-8); identifies the device
// @function grid_cols
fn gridCols(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    // push the number of cols
    l.pushInteger(monome.devices.cols[num]);
    // return it
    return 1;
}

/// reports number of quads of grid device.
// @tparam integer id (1-8); identifies the device
// @function grid_quads
fn gridQuads(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const monome = lu.closureGetContext(l, Monome) orelse return 0;
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 8, 1, "id must be between 1 and 8");
    const num: u3 = @intCast(id - 1);
    // push the number of cols
    l.pushInteger(switch (monome.devices.quads[num]) {
        .one => 1,
        .two => 2,
        .four => 4,
    });
    // return it
    return 1;
}

// concatenates two strings into a buffer asserting capacity
// returns a slice of buf
fn concatIntoBufZAssumeCapacity(buf: []u8, first: []const u8, second: []const u8) [:0]const u8 {
    std.debug.assert(first.len + second.len + 1 <= buf.len);
    @memcpy(buf[0..first.len], first);
    @memcpy(buf[first.len..][0..second.len], second);
    buf[first.len + second.len] = 0;
    return buf[0 .. first.len + second.len :0];
}

const logger = std.log.scoped(.serialosc);
const Osc = @import("osc.zig").Osc;
const std = @import("std");
const lo = @import("ziglo");
const xev = @import("xev");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("lua_util.zig");
const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
