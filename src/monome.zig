/// struct-of-arrays for storing and interacting with monome arc or grid devices
const Monome = @This();

const num_devs = 8;

serialosc_address: *lo.Address,
local_address: *lo.Message,
devices: Devices = .{},
pool: std.heap.MemoryPoolExtra(Event, .{}),

// not sure struct-of-arrays actually buys us much, but it's fun
const Devices = struct {
    // we need to interact with this atomically
    // bc the OSC thread and the main thread need to agree on its value.
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
    add_rem_ev: [num_devs]AddRemoveEvent = undefined,
    dev_addr: [num_devs]?*lo.Address = .{null} ** num_devs,
    methods: [num_devs][5]?*lo.Method = .{.{null} ** 5} ** num_devs,
    dev_ctx: [num_devs]DevCtx = undefined,

    const DevCtx = struct {
        id: u3,
        monome: *Monome,
    };
};

// self-init since we're a field of another struct
pub fn init(self: *Monome) void {
    const ids: [8]u3 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (&self.devices.add_rem_ev, &self.devices.dev_ctx, ids) |*ev, *ctx, i| {
        ev.* = .{ .monome = self, .idx = i };
        ctx.* = .{ .monome = self, .id = i };
    }
}

pub fn addMethods(self: *Monome) void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    _ = osc.server.addMethod("/serialosc/add", "ssi", lo.wrap(handleAdd), self);
    _ = osc.server.addMethod("/serialosc/device", "ssi", lo.wrap(handleAdd), self);
    _ = osc.server.addMethod("/serialosc/remove", "ssi", lo.wrap(handleRemove), self);
}

// register lua functions
pub fn registerLua(self: *Monome, vm: *Spindle) void {
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
        lu.registerSeamstress(vm, field, f, self);
    }
}

// releases liblo-owned memory, destroys the memory pool
pub fn deinit(self: *Monome) void {
    for (&self.devices.dev_addr) |maybe_addr| if (maybe_addr) |addr| addr.free();
    self.serialosc_address.free();
    self.local_address.free();
    self.pool.deinit();
    self.* = undefined;
}

// the "inner" responder to a remove message.
fn remove(self: *Monome, port: i32) !void {
    const id: u3 = id: for (&self.devices.dev_addr, 0..) |addr, i| {
        if (addr) |a| {
            const port_str = std.mem.sliceTo(a.getPort() orelse continue, 0);
            var buf: std.BoundedArray(u8, 256) = .{};
            try std.fmt.format(buf.writer(), "{d}", .{port});
            if (std.mem.eql(u8, buf.buffer[0..buf.len], port_str)) break :id @intCast(i);
        }
    } else return error.NotFound;
    // remove method handlers on the OSC thread
    const osc: *Osc = @fieldParentPtr("monome", self);
    for (&self.devices.methods[id]) |method| {
        if (method) |m| _ = osc.server.deleteMethod(m);
    }
    // do this atomically so that the main and OSC threads agree
    @atomicStore(bool, &self.devices.connected[id], false, .release);
    // let's tell lua to remove this device
    osc.vm.events.submit(&self.devices.add_rem_ev[id].node);
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
        const port_str = std.mem.sliceTo(addr.getPort() orelse {
            addr.free();
            for (&self.devices.methods[num]) |method| {
                if (method) |m| _ = osc.server.deleteMethod(m);
            }
            self.devices.methods[num] = .{null} ** 5;
            break :reconnect;
        }, 0);
        const old_port = try std.fmt.parseInt(i32, port_str, 10);
        if (old_port != port) {
            addr.free();
            for (&self.devices.methods[num]) |method| {
                if (method) |m| _ = osc.server.deleteMethod(m);
            }
            self.devices.methods[num] = .{null} ** 5;
            break :reconnect;
        }
        self.devices.connected[num] = true;
        // we've already set up the device at this port, so let's tell lua to add it
        osc.vm.events.submit(&self.devices.add_rem_ev[num].node);
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
    // prepare the address string
    var buf: std.BoundedArray(u8, 256) = .{};
    try std.fmt.format(buf.writer(), "{d}\x00", .{port});
    const port_str = buf.buffer[0 .. buf.len - 1 :0];
    // set the address
    self.devices.dev_addr[num] = lo.Address.new("127.0.0.1", port_str);
    // set the device type: an arc is a device that calls itself an arc
    self.devices.m_type[num] = if (std.mem.indexOf(u8, m_type, "arc")) |_| .arc else .grid;
    // add method handlers
    switch (self.devices.m_type[num]) {
        .arc => {
            self.devices.quads[num] = .four;
            const delta = osc.server.addMethod(
                "*/enc/delta",
                "ii",
                lo.wrap(handler(.delta)),
                &self.devices.dev_ctx[num],
            );
            const key = osc.server.addMethod(
                "*/enc/key",
                "ii",
                lo.wrap(handler(.arc_key)),
                &self.devices.dev_ctx[num],
            );
            const size = osc.server.addMethod(
                "/sys/size",
                "ii",
                lo.wrap(handleSize),
                &self.devices.dev_ctx[num],
            );
            const rot = osc.server.addMethod(
                "/sys/rotation",
                "i",
                lo.wrap(handleRotation),
                &self.devices.dev_ctx[num],
            );
            const prefix = osc.server.addMethod(
                "/sys/prefix",
                "s",
                lo.wrap(handlePrefix),
                &self.devices.dev_ctx[num],
            );
            self.devices.methods[num] = .{ delta, key, size, rot, prefix };
        },
        .grid => {
            const key = osc.server.addMethod(
                "*/grid/key",
                "iii",
                lo.wrap(handler(.grid_key)),
                &self.devices.dev_ctx[num],
            );
            const tilt = osc.server.addMethod(
                "*/tilt",
                "iiii",
                lo.wrap(handler(.tilt)),
                &self.devices.dev_ctx[num],
            );
            const size = osc.server.addMethod(
                "/sys/size",
                "ii",
                lo.wrap(handleSize),
                &self.devices.dev_ctx[num],
            );
            const rot = osc.server.addMethod(
                "/sys/rotation",
                "i",
                lo.wrap(handleRotation),
                &self.devices.dev_ctx[num],
            );
            const prefix = osc.server.addMethod(
                "/sys/prefix",
                "s",
                lo.wrap(handlePrefix),
                &self.devices.dev_ctx[num],
            );
            self.devices.methods[num] = .{ key, tilt, size, rot, prefix };
        },
    }
    osc.resetDefaultHandler();
    try self.setPort(num);
    // we actually add the device from the `size` handler
    try self.getInfo(num);
    // do this atomically because the main and OSC threads need to agree
    @atomicStore(bool, &self.devices.connected[num], true, .release);
}

// sends /sys/info to serialosc
fn getInfo(self: *Monome, id: u3) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(
        self.devices.dev_addr[id] orelse return error.NoAddress,
        "/sys/info",
        self.local_address,
    ) catch return error.MessageSendFailed;
}

// sets the device's port to us
fn setPort(self: *Monome, id: u3) !void {
    const osc: *Osc = @fieldParentPtr("monome", self);
    osc.server.send(
        self.devices.dev_addr[id] orelse return error.NoAddress,
        "/sys/port",
        self.local_address,
    ) catch return error.MessageSendFailed;
}

const AddRemoveEvent = struct {
    monome: *Monome,
    idx: u3,
    node: Events.Node = .{
        .handler = Events.handlerFromClosure(AddRemoveEvent, addOrRemove, "node"),
    },

    fn addOrRemove(ev: *AddRemoveEvent, l: *Lua) void {
        // do this atomically because the main and OSC threads need to agree
        const is_add = @atomicLoad(bool, &ev.monome.devices.connected[ev.idx], .acquire);
        if (!is_add) {
            lu.getMethod(l, switch (ev.monome.devices.m_type[ev.idx]) {
                .grid => "grid",
                .arc => "arc",
            }, "remove");
            l.pushInteger(ev.idx);
            lu.doCall(l, 1, 0);
        } else {
            lu.getMethod(l, switch (ev.monome.devices.m_type[ev.idx]) {
                .grid => "grid",
                .arc => "arc",
            }, "add");
            // convert to 1-based
            l.pushInteger(ev.idx + 1);
            _ = l.pushString(std.mem.sliceTo(&ev.monome.devices.serial_buf[ev.idx], 0));
            _ = l.pushString(std.mem.sliceTo(&ev.monome.devices.name_buf[ev.idx], 0));
            lu.doCall(l, 3, 0);
        }
    }
};

// asks serialosc to list devices
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

// the handlers only need differ in which function they call, so let's create a function based on that
fn handler(
    comptime T: enum { grid_key, arc_key, delta, tilt },
) fn ([:0]const u8, []const u8, *lo.Message, ?*anyopaque) bool {
    return struct {
        // the actual handler
        fn f(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
            const d: *Devices.DevCtx = @ptrCast(@alignCast(ctx orelse return true));
            // fallthrough to other copies of this handler
            if (!matchAddress(d, msg.source())) return true;
            const osc: *Osc = @fieldParentPtr("monome", d.monome);
            // create an event
            const ev = d.monome.pool.create() catch {
                lu.panic(osc.vm, error.OutOfMemory);
                return false;
            };
            // make sure the message hangs around after we return
            msg.incRef();
            ev.* = .{
                .id = d.id,
                .msg = msg,
                .pool = &d.monome.pool,
                .node = .{
                    .handler = Events.handlerFromClosure(Event, switch (T) {
                        .arc_key => Event.arcKey,
                        .delta => Event.delta,
                        .grid_key => Event.gridKey,
                        .tilt => Event.tilt,
                    }, "node"),
                },
            };
            // submit to the queue
            osc.vm.events.submit(&ev.node);
            return false;
        }
    }.f;
}

// responds to /sys/prefix
fn handlePrefix(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const d: *Devices.DevCtx = @ptrCast(@alignCast(ctx orelse return true));
    // fallthrough to other copies of this handler
    if (!matchAddress(d, msg.source())) return true;
    const prefix = msg.getArg([:0]const u8, 0) catch return true;
    if (prefix.len >= 256) {
        logger.err("device prefix {s} too long!", .{prefix});
        return false;
    }
    @memset(&d.monome.devices.prefix_buf[d.id], 0);
    @memcpy(d.monome.devices.prefix_buf[d.id][0..prefix.len], prefix);
    return false;
}

// responds to /sys/rotation
fn handleRotation(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const d: *Devices.DevCtx = @ptrCast(@alignCast(ctx orelse return true));
    // fallthrough to other copies of this handler
    if (!matchAddress(d, msg.source())) return true;
    const degs = msg.getArg(i32, 0) catch return true;
    switch (degs) {
        0 => d.monome.devices.rotation[d.id] = .zero,
        90 => d.monome.devices.rotation[d.id] = .ninety,
        180 => d.monome.devices.rotation[d.id] = .one_eighty,
        270 => d.monome.devices.rotation[d.id] = .two_seventy,
        else => unreachable,
    }
    return false;
}

// responds to /sys/size; sends an `add` event to Lua
fn handleSize(_: [:0]const u8, _: []const u8, msg: *lo.Message, ctx: ?*anyopaque) bool {
    const d: *Devices.DevCtx = @ptrCast(@alignCast(ctx orelse return true));
    // fallthrough to other copies of this handler
    if (!matchAddress(d, msg.source())) return true;
    const rows = msg.getArg(i32, 0) catch return true;
    const cols = msg.getArg(i32, 1) catch return true;
    d.monome.devices.rows[d.id] = @min(@max(0, rows), 255);
    d.monome.devices.cols[d.id] = @min(@max(0, cols), 255);
    d.monome.devices.quads[d.id] = switch (@divExact(rows * cols, 64)) {
        1 => .one,
        2 => .two,
        4 => .four,
        else => unreachable,
    };
    const osc: *Osc = @fieldParentPtr("monome", d.monome);
    osc.vm.events.submit(&d.monome.devices.add_rem_ev[d.id].node);
    return false;
}

// matches an address's port number (as a string) against a stored one
fn matchAddress(ctx: *Devices.DevCtx, address: ?*lo.Address) bool {
    const self = ctx.monome.devices.dev_addr[ctx.id] orelse return false;
    const other = address orelse return false;
    const self_port_str = std.mem.sliceTo(self.getPort() orelse return false, 0);
    const other_port_str = std.mem.sliceTo(other.getPort() orelse return false, 0);
    return std.mem.eql(u8, self_port_str, other_port_str);
}

pub const Event = struct {
    id: u3,
    msg: *lo.Message,
    pool: *std.heap.MemoryPoolExtra(Event, .{}),
    node: Events.Node,

    // handles a grid key event
    fn gridKey(self: *Event, l: *Lua) void {
        defer {
            self.msg.free();
            self.pool.destroy(self);
        }
        // catch unreachable is valid: the message must be of type iii
        const x = self.msg.getArg(i32, 0) catch unreachable;
        const y = self.msg.getArg(i32, 1) catch unreachable;
        const z = self.msg.getArg(i32, 2) catch unreachable;
        lu.getMethod(l, "grid", "key");
        // convert from 0-indexed
        l.pushInteger(self.id + 1);
        l.pushInteger(x + 1);
        l.pushInteger(y + 1);
        // already 0 or 1
        l.pushInteger(z);
        lu.doCall(l, 4, 0);
    }

    // handles an arc delta event
    fn delta(self: *Event, l: *Lua) void {
        defer {
            self.msg.free();
            self.pool.destroy(self);
        }
        // catch unreachable is valid: the message must be of type iiii
        const n = self.msg.getArg(i32, 0) catch unreachable;
        const d = self.msg.getArg(i32, 1) catch unreachable;
        lu.getMethod(l, "arc", "delta");
        // convert from 0-indexed
        l.pushInteger(self.id + 1);
        l.pushInteger(n + 1);
        // correctly 0-indexed
        l.pushInteger(d);
        lu.doCall(l, 3, 0);
    }

    // handles a grid tilt event
    fn tilt(self: *Event, l: *Lua) void {
        defer {
            self.msg.free();
            self.pool.destroy(self);
        }
        // catch unreachable is valid: the message must be of type iiii
        const n = self.msg.getArg(i32, 0) catch unreachable;
        const x = self.msg.getArg(i32, 1) catch unreachable;
        const y = self.msg.getArg(i32, 2) catch unreachable;
        const z = self.msg.getArg(i32, 3) catch unreachable;
        lu.getMethod(l, "grid", "tilt");
        // convert from 0-indexed
        l.pushInteger(self.id + 1);
        l.pushInteger(n + 1);
        // correctly 0-indexed
        l.pushInteger(x);
        l.pushInteger(y);
        l.pushInteger(z);
        lu.doCall(l, 5, 0);
    }

    // handles an arc key event
    fn arcKey(self: *Event, l: *Lua) void {
        defer {
            self.msg.free();
            self.pool.destroy(self);
        }
        // catch unreachable is valid: the message must be of type ii
        const n = self.msg.getArg(i32, 0) catch unreachable;
        const z = self.msg.getArg(i32, 1) catch unreachable;
        lu.getMethod(l, "arc", "key");
        // convert from 0-indexed
        l.pushInteger(self.id + 1);
        l.pushInteger(n + 1);
        // correctly 0 or 1
        l.pushInteger(z);
        lu.doCall(l, 3, 0);
    }
};

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
    osc.server.send(monome.devices.dev_addr[num] orelse return 0, "/sys/rotation", msg) catch {
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
    osc.server.send(monome.devices.dev_addr[num] orelse return 0, path, msg) catch {
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
    osc.server.send(monome.devices.dev_addr[num] orelse return 0, path, msg) catch {
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
            osc.server.send(monome.devices.dev_addr[num] orelse return 0, path, msg) catch {
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
                osc.server.send(monome.devices.dev_addr[num] orelse return 0, path, msg) catch {
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
                osc.server.send(monome.devices.dev_addr[num] orelse return 0, path, msg) catch {
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
    for (0..4) |i| {
        if (!monome.devices.dirty[num][i]) continue;
        const msg = lo.Message.new() orelse {
            logger.err("error creating message!", .{});
            return 0;
        };
        defer msg.free();
        msg.add(.{@as(i32, @intCast(i))}) catch return 0;
        msg.addSlice(i32, &monome.devices.data[num][i]) catch return 0;
        osc.server.send(monome.devices.dev_addr[num] orelse return 0, path, msg) catch {
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

const o = @import("osc.zig");
const Osc = o.Osc;
const logger = o.logger;
const lo = @import("ziglo");
const std = @import("std");
const Events = @import("events.zig");
const Spindle = @import("spindle.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("lua_util.zig");
