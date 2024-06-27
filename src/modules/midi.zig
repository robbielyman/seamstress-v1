const Midi = @This();

fn registerSeamstress(self: *Midi, l: *Lua) void {
    const top = l.getTop();
    defer std.debug.assert(top == l.getTop());
    lu.getSeamstress(l); // seamstress
    _ = l.pushStringZ("midi"); // midi
    l.newTable(); // t
    l.newTable(); // mt
    _ = l.pushStringZ("__index"); // __index
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(index), 1); // f
    l.setTable(-3); // mt.__index = f
    l.setMetatable(-2); // setmetatable(t, mt)
    _ = l.pushStringZ("rescan"); // rescan
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(rescan), 1); // f
    l.setTable(-3); // t.rescan = f
    _ = l.pushStringZ("connectOutput"); // connectOutput
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(connectOutput), 1); // f
    l.setTable(-3); // t.connectOutput = f
    _ = l.pushStringZ("connectInput"); // connectInput
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(connectInput), 1); // f
    l.setTable(-3); // t.connectInput = f
    _ = l.pushStringZ("disconnectInput"); // disconnectInput
    l.pushLightUserdata(self);
    l.pushClosure(ziglua.wrap(disconnectInput), 1); // f
    l.setTable(-3); // t.disconnectInput = f
    _ = l.pushStringZ("messages"); // messages
    l.pushFunction(ziglua.wrap(msgIterator)); // f
    l.setTable(-3); // t.messages = f
    _ = l.pushStringZ("encode"); // encode
    l.pushFunction(ziglua.wrap(eventsToBytes)); // f
    l.setTable(-3); // t.encode = f
    _ = l.pushStringZ("encodeAll"); // encodeAll
    l.pushFunction(ziglua.wrap(arrayOfEventsToBytes)); // f
    l.setTable(-3); // t.encodeAll = f
    l.setTable(-3); // seamstress.midi = t
    l.pop(1);
}

fn connectOutput(l: *Lua) i32 {
    const self = lu.closureGetContext(l, Midi);
    const out = out: {
        if (l.typeOf(1) == .number) {
            const idx: u32 = @intCast((l.toInteger(1) catch unreachable) - 1);
            for (self.outs.items) |*o| if (o.port == .number and o.port.number == idx) break :out o;
            if (idx >= self.outs.items[0].output.getPortCount()) l.raiseErrorStr("no such port!", .{});
            const out = self.outs.addOne() catch panic("out of memory!", .{});
            out.* = .{
                .output = midi.Out.createDefault() orelse l.raiseErrorStr("unable to create MIDI device!", .{}),
                .port = .{ .number = idx },
                .name = undefined,
                .refs = 0,
            };
            out.name = out.output.getPortNameAlloc(l.allocator(), idx) catch panic("out of memory!", .{});
            break :out out;
        }
        const string = l.checkString(1);
        for (self.outs.items) |*o| if (std.mem.eql(u8, string, o.name)) break :out o;
        for (self.outs_list) |li| {
            if (std.mem.eql(u8, li.name, string)) {
                const out = self.outs.addOne() catch panic("out of memory!", .{});
                out.* = .{
                    .output = midi.Out.createDefault() orelse l.raiseErrorStr("unable to create MIDI device!", .{}),
                    .port = .{ .number = @intCast(li.port) },
                    .name = l.allocator().dupeZ(u8, string) catch panic("out of memory!", .{}),
                    .refs = 0,
                };
                break :out out;
            }
        }
        l.raiseErrorStr("no such port!", .{});
    };
    out.refs += 1;
    l.newTable(); // t
    _ = l.pushStringZ("name"); // name
    l.pushValue(1); // string
    l.setTable(-3); // t.name = string
    l.newTable(); // mt
    l.pushLightUserdata(out);
    l.setFuncs(metamethods, 1);
    _ = l.pushStringZ("__index"); // __index
    l.pushValue(-2); // mt
    l.setTable(-3); // mt.__index = mt
    _ = l.pushStringZ("__gc"); // __gc
    l.pushLightUserdata(out); // upvalue 1
    l.pushLightUserdata(self); // upvalue 2
    l.pushClosure(ziglua.wrap(gc), 2); // f
    l.setTable(-3); // mt.__gc = f
    l.setMetatable(-2); // setmetatable(t, mt)
    return 1;
}

const metamethods: []const ziglua.FnReg = &.{
    .{ .name = "send", .func = ziglua.wrap(send) },
    .{ .name = "sendAll", .func = ziglua.wrap(sendAll) },
    .{ .name = "note_off", .func = ziglua.wrap(sendKind(.{ .kind = .note_off, .channel = 0 })) },
    .{ .name = "note_on", .func = ziglua.wrap(sendKind(.{ .kind = .note_on, .channel = 0 })) },
    .{ .name = "aftertouch", .func = ziglua.wrap(sendKind(.{ .kind = .aftertouch, .channel = 0 })) },
    .{ .name = "control_change", .func = ziglua.wrap(sendKind(.{ .kind = .control_change, .channel = 0 })) },
    .{ .name = "program_change", .func = ziglua.wrap(sendKind(.{ .kind = .program_change, .channel = 0 })) },
    .{ .name = "channel_pressure", .func = ziglua.wrap(sendKind(.{ .kind = .channel_pressure, .channel = 0 })) },
    .{ .name = "pitch_wheel", .func = ziglua.wrap(sendKind(.{ .kind = .pitch_wheel, .channel = 0 })) },
    .{ .name = "sysex", .func = ziglua.wrap(sendKind(Status.sysex_begin)) },
    .{ .name = "quarter_frame", .func = ziglua.wrap(sendKind(Status.quarter_frame)) },
    .{ .name = "song_position", .func = ziglua.wrap(sendKind(Status.song_position)) },
    .{ .name = "song_select", .func = ziglua.wrap(sendKind(Status.song_select)) },
    .{ .name = "tune_request", .func = ziglua.wrap(sendKind(Status.tune_request)) },
    .{ .name = "10ms_tick", .func = ziglua.wrap(sendKind(Status.@"10ms_tick")) },
    .{ .name = "start", .func = ziglua.wrap(sendKind(Status.start)) },
    .{ .name = "stop", .func = ziglua.wrap(sendKind(Status.stop)) },
    .{ .name = "continue", .func = ziglua.wrap(sendKind(Status.@"continue")) },
    .{ .name = "active_sense", .func = ziglua.wrap(sendKind(Status.active_sense)) },
    .{ .name = "reset", .func = ziglua.wrap(sendKind(Status.reset)) },
    .{ .name = "clock", .func = ziglua.wrap(sendKind(Status.clock)) },
};

fn gc(l: *Lua) i32 {
    const out = lu.closureGetContext(l, Out);
    const j = Lua.upvalueIndex(2);
    const self = l.toUserdata(Midi, j) catch unreachable;
    out.refs -= 1;
    if (out.refs == 0) {
        out.output.closePort();
        l.allocator().free(out.name);
        var idx: usize = 0;
        for (self.outs.items) |o| {
            if (o.refs > 0) {
                self.outs.items[idx] = o;
                idx += 1;
            }
        }
        self.outs.items.len = idx;
    }
    return 0;
}

fn disconnectInput(l: *Lua) i32 {
    const self = lu.closureGetContext(l, Midi);
    const in, const which = in: {
        if (l.typeOf(1) == .number) {
            const idx: u32 = @intCast((l.toInteger(1) catch unreachable) - 1);
            for (self.ins.items, 0..) |*i, w| if (i.port == .number and i.port.number == idx) break :in .{ i, w };
        }
        const string = l.checkString(1);
        for (self.ins.items, 0..) |*i, w| if (std.mem.eql(u8, i.name, string)) break :in .{ i, w };
        l.raiseErrorStr("no such port!", .{});
    };
    if (in.port == .virtual) l.raiseErrorStr("attempt to close seamstress's virtual ports!", .{});
    in.input.closePort();
    if (in.sysex_handle) |h| l.unref(ziglua.registry_index, h);
    l.allocator().free(in.name);
    _ = self.ins.orderedRemove(which);
    return 0;
}

fn connectInput(l: *Lua) i32 {
    const self = lu.closureGetContext(l, Midi);
    if (l.typeOf(1) == .number) {
        const idx: u32 = @intCast((l.toInteger(1) catch unreachable) - 1);
        for (self.ins.items) |i| // already connected
            if (i.port == .number and i.port.number == idx) return 0;
        if (idx >= self.ins.items[0].input.getPortCount()) l.raiseErrorStr("no such port!", .{});
        const in = self.ins.addOne() catch panic("out of memory!", .{});
        in.* = .{
            .input = midi.In.createDefault() orelse l.raiseErrorStr("unable to create MIDI device!", .{}),
            .port = .{ .number = idx },
            .name = undefined,
        };
        in.name = in.input.getPortNameAlloc(l.allocator(), idx) catch panic("out of memory!", .{});
        in.input.setCallback(callback, in);
        in.input.ignoreTypes(false, false, true);
        return 0;
    }
    const string = l.checkString(1);
    for (self.ins.items) |i| // already connected
        if (std.mem.eql(u8, string, i.name)) return 0;
    for (self.ins_list) |li| {
        if (std.mem.eql(u8, li.name, string)) {
            const in = self.ins.addOne() catch panic("out of memory!", .{});
            in.* = .{
                .input = midi.In.createDefault() orelse l.raiseErrorStr("unable to create MIDI device!", .{}),
                .port = .{ .number = @intCast(li.port) },
                .name = l.allocator().dupeZ(u8, string) catch panic("out of memory!", .{}),
            };
            in.input.setCallback(callback, in);
            in.input.ignoreTypes(false, false, true);
            return 0;
        }
    }
    l.raiseErrorStr("no such port!", .{});
}

fn rescan(l: *Lua) i32 {
    const self = lu.closureGetContext(l, Midi);
    const wheel = lu.getWheel(l);
    const now = wheel.timer.read();
    self.last = now;
    const allocator = l.allocator();
    const ins, const outs = self.scan(allocator) catch return 0;
    for (self.ins_list) |li| allocator.free(li.name);
    allocator.free(self.ins_list);
    for (self.outs_list) |ou| allocator.free(ou.name);
    allocator.free(self.outs_list);
    self.ins_list = ins;
    self.outs_list = outs;
    return 0;
}

fn index(l: *Lua) i32 {
    const self = lu.closureGetContext(l, Midi);
    if (!std.mem.eql(u8, "list", l.checkString(2))) return 0;
    const wheel = lu.getWheel(l);
    const now = wheel.timer.read();
    if (now - self.last > 5 * std.time.ns_per_s) blk: {
        self.last = now;
        const allocator = l.allocator();
        const ins, const outs = self.scan(allocator) catch break :blk;
        for (self.ins_list) |li| allocator.free(li.name);
        allocator.free(self.ins_list);
        for (self.outs_list) |ou| allocator.free(ou.name);
        allocator.free(self.outs_list);
        self.ins_list = ins;
        self.outs_list = outs;
    }
    l.createTable(0, 2); // t
    _ = l.pushStringZ("inputs"); // inputs
    l.createTable(@intCast(self.ins_list.len), 0); // s
    for (0..self.ins_list.len) |i| {
        l.pushInteger(@intCast(i + 1)); // i
        _ = l.pushStringZ(self.ins_list[i].name); // string
        l.setTable(-3); // s[i] = string
    }
    l.setTable(-3); // t.inputs = s
    _ = l.pushStringZ("outputs"); // inputs
    l.createTable(@intCast(self.outs_list.len), 0); // s
    for (0..self.outs_list.len) |i| {
        l.pushInteger(@intCast(i + 1)); // i
        _ = l.pushStringZ(self.outs_list[i].name); // string
        l.setTable(-3); // s[i] = string
    }
    l.setTable(-3); // t.outputs = s
    return 1; // return t
}

ins: std.ArrayList(In),
outs: std.ArrayList(Out),
ins_list: []Listing,
outs_list: []Listing,
c: xev.Completion = .{},
timer: xev.Timer,
last: u64,

const Listing = struct {
    name: [:0]const u8,
    port: usize,
};

const Port = union(enum) {
    number: u32,
    virtual,
};

const In = struct {
    port: Port,
    input: *midi.In,
    name: [:0]const u8,
    buf: RingBuffer(u8, 4 * 1024) = .{},
    sysex_handle: ?i32 = null,
};

const Out = struct {
    port: Port,
    output: *midi.Out,
    name: [:0]const u8,
    refs: usize = 0,
};

const Kind = enum(u4) {
    note_off = 0x8,
    note_on = 0x9,
    aftertouch = 0xa,
    control_change = 0xb,
    program_change = 0xc,
    channel_pressure = 0xd,
    pitch_wheel = 0xe,
    other = 0xf,
};

const Status = packed struct(u8) {
    channel: u4,
    kind: Kind,

    pub const sysex_begin: Status = .{ .kind = .other, .channel = 0 };
    pub const quarter_frame: Status = .{ .kind = .other, .channel = 1 };
    pub const song_position: Status = .{ .kind = .other, .channel = 2 };
    pub const song_select: Status = .{ .kind = .other, .channel = 3 };
    pub const tune_request: Status = .{ .kind = .other, .channel = 6 };
    pub const sysex_end: Status = .{ .kind = .other, .channel = 7 };
    pub const clock: Status = .{ .kind = .other, .channel = 8 };
    pub const @"10ms_tick": Status = .{ .kind = .other, .channel = 9 };
    pub const start: Status = .{ .kind = .other, .channel = 10 };
    pub const @"continue": Status = .{ .kind = .other, .channel = 11 };
    pub const stop: Status = .{ .kind = .other, .channel = 12 };
    pub const active_sense: Status = .{ .kind = .other, .channel = 14 };
    pub const reset: Status = .{ .kind = .other, .channel = 15 };
};

fn name(status: Status) [:0]const u8 {
    const decls = @typeInfo(Status).Struct.decls;
    if (status.kind != .other) return @tagName(status.kind);
    inline for (decls) |decl| {
        if (@as(u8, @bitCast(@field(Status, decl.name))) == @as(u8, @bitCast(status))) return decl.name;
    }
    return "unknown";
}

test "Status" {
    const status: Status = .{
        .kind = .note_off,
        .channel = 0xe,
    };
    try std.testing.expectEqual(0x8e, @as(u8, @bitCast(status)));
}

const status_byte_map = std.StaticStringMap(Status).initComptime(.{
    .{ "note_off", .{ .kind = .note_off, .channel = 0 } },
    .{ "note_on", .{ .kind = .note_on, .channel = 0 } },
    .{ "aftertouch", .{ .kind = .aftertouch, .channel = 0 } },
    .{ "control_change", .{ .kind = .control_change, .channel = 0 } },
    .{ "program_change", .{ .kind = .program_change, .channel = 0 } },
    .{ "channel_pressure", .{ .kind = .channel_pressure, .channel = 0 } },
    .{ "pitch_wheel", .{ .kind = .pitch_wheel, .channel = 0 } },
    .{ "sysex", Status.sysex_begin },
    .{ "quarter_frame", Status.quarter_frame },
    .{ "song_position", Status.song_position },
    .{ "song_select", Status.song_select },
    .{ "tune_request", Status.tune_request },
    .{ "10ms_tick", Status.@"10ms_tick" },
    .{ "start", Status.start },
    .{ "continue", Status.@"continue" },
    .{ "stop", Status.stop },
    .{ "active_sense", Status.active_sense },
    .{ "reset", Status.reset },
    .{ "clock", Status.clock },
});

fn scan(self: *Midi, allocator: std.mem.Allocator) ![2][]Listing {
    const ins_count = self.ins.items[0].input.getPortCount();
    var ins_list = try std.ArrayList(Listing).initCapacity(allocator, ins_count);
    errdefer {
        for (ins_list.items) |listing| {
            allocator.free(listing.name);
        }
        ins_list.deinit();
    }
    for (0..ins_count) |i| {
        const port_name = try self.ins.items[0].input.getPortNameAlloc(allocator, i);
        if (std.mem.startsWith(u8, port_name, "from seamstress")) {
            allocator.free(port_name);
            continue;
        }
        try ins_list.append(.{ .name = port_name, .port = i });
    }
    const outs_count = self.outs.items[0].output.getPortCount();
    var outs_list = try std.ArrayList(Listing).initCapacity(allocator, outs_count);
    errdefer {
        for (outs_list.items) |listing| {
            allocator.free(listing.name);
        }
        outs_list.deinit();
    }
    for (0..outs_count) |i| {
        const port_name = try self.outs.items[0].output.getPortNameAlloc(allocator, i);
        if (std.mem.startsWith(u8, port_name, "to seamstress")) {
            allocator.free(port_name);
            continue;
        }
        try outs_list.append(.{ .name = port_name, .port = @intCast(i) });
    }
    return .{ try ins_list.toOwnedSlice(), try outs_list.toOwnedSlice() };
}

fn sendAll(l: *Lua) i32 {
    const out = lu.closureGetContext(l, Out);
    const bytes = if (l.typeOf(1) == .table) blk: {
        l.pushFunction(ziglua.wrap(arrayOfEventsToBytes));
        l.pushValue(1);
        l.call(1, 1);
        break :blk l.toString(-1) catch unreachable;
    } else l.checkString(1);
    const dev: *midi.Dev = @ptrCast(@alignCast(out.output));
    out.output.sendMessage(bytes) catch |err| l.raiseErrorStr("error sending messages: %s, %s", .{ @errorName(err).ptr, dev.msg.? });
    return 0;
}

fn sendKind(comptime status: Status) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            const args = l.getTop();
            const out = lu.closureGetContext(l, Out);
            l.pushLightUserdata(out);
            l.pushClosure(ziglua.wrap(send), 1);
            l.pushFunction(ziglua.wrap(eventsToBytes));
            l.createTable(args + 1, 0);
            l.pushInteger(1);
            _ = l.pushStringZ(name(status));
            l.setTable(-3);
            var i: i32 = 1;
            while (i <= args) : (i += 1) {
                l.pushInteger(i + 1);
                l.pushValue(i);
                l.setTable(-3);
            }
            l.call(1, 1);
            l.call(1, 0);
            return 0;
        }
    }.f;
}

fn send(l: *Lua) i32 {
    const out = lu.closureGetContext(l, Out);
    const bytes = if (l.typeOf(1) == .table) blk: {
        l.pushFunction(ziglua.wrap(eventsToBytes));
        l.pushValue(1);
        l.call(1, 1);
        break :blk l.toString(-1) catch unreachable;
    } else l.checkString(1);
    const dev: *midi.Dev = @ptrCast(@alignCast(out.output));
    out.output.sendMessage(bytes) catch |err| l.raiseErrorStr("error sending message: %s, %s", .{ @errorName(err).ptr, dev.msg.? });
    logger.debug("sent: {any}", .{bytes});
    return 0;
}

fn arrayOfEventsToBytes(l: *Lua) i32 {
    l.checkType(1, .table);
    l.len(1);
    const len = l.toInteger(-1) catch unreachable;
    var buf: ziglua.Buffer = undefined;
    buf.init(l);
    var i: ziglua.Integer = 1;
    while (i <= len) : (i += 1) {
        l.pushFunction(ziglua.wrap(eventsToBytes));
        _ = l.getIndex(1, i);
        l.call(1, 1);
        buf.addValue();
    }
    buf.pushResult();
    return 1;
}

fn eventsToBytes(l: *Lua) i32 {
    l.checkType(1, .table);
    l.argCheck(l.getIndex(1, 1) == .string, 1, "message kind expected!");
    var status = status_byte_map.get(l.toString(-1) catch unreachable) orelse l.argError(1, "unknown message kind!");
    l.pop(1);
    if (status.kind != .other) {
        _ = l.getIndex(1, 2);
        l.argCheck(l.isInteger(-1), 1, "channel should be an integer!");
        status.channel = std.math.cast(u4, (l.toInteger(-1) catch unreachable) - 1) orelse l.argError(1, "channel should be 1-16");
        l.pop(1);
        var buf: ziglua.Buffer = undefined;
        buf.init(l);
        buf.addChar(@bitCast(status));
        switch (status.kind) {
            .note_on, .note_off, .aftertouch, .control_change => {
                _ = l.getIndex(1, 3);
                l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
                const first = std.math.cast(u7, l.toInteger(-1) catch unreachable) orelse
                    l.argError(1, "MIDI data should be 0-127");
                l.pop(1);
                _ = l.getIndex(1, 4);
                l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
                const second = std.math.cast(u7, l.toInteger(-1) catch unreachable) orelse
                    l.argError(1, "MIDI data should be 0-127");
                l.pop(1);
                buf.addChar(first);
                buf.addChar(second);
            },
            .pitch_wheel => {
                _ = l.getIndex(1, 3);
                l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
                const short = std.math.cast(u14, l.toInteger(-1) catch unreachable) orelse
                    l.argError(1, "pitch wheel data should be 0-16383");
                l.pop(1);
                const first: u7 = @intCast(short >> 7);
                const second: u7 = @truncate(short);
                buf.addChar(first);
                buf.addChar(second);
            },
            .program_change, .channel_pressure => {
                _ = l.getIndex(1, 3);
                l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
                const byte = std.math.cast(u7, l.toInteger(-1) catch unreachable) orelse
                    l.argError(1, "MIDI data should be 0-127");
                l.pop(1);
                buf.addChar(byte);
            },
            .other => unreachable,
        }
        buf.pushResult();
        return 1;
    }
    var buf: ziglua.Buffer = undefined;
    buf.init(l);
    buf.addChar(@bitCast(status));
    switch (status.channel) {
        0 => {
            l.argCheck(l.getIndex(1, 2) == .string, 1, "MIDI sysex data should be a string!");
            buf.addValue();
            buf.addChar(@bitCast(Status.sysex_end));
        },
        1, 3 => {
            _ = l.getIndex(1, 2);
            l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
            const byte = std.math.cast(u7, l.toInteger(-1) catch unreachable) orelse
                l.argError(1, "MIDI data should be 0-127");
            l.pop(1);
            buf.addChar(byte);
        },
        2 => {
            _ = l.getIndex(1, 2);
            l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
            const first = std.math.cast(u7, l.toInteger(-1) catch unreachable) orelse
                l.argError(1, "MIDI data should be 0-127");
            l.pop(1);
            buf.addChar(first);
            _ = l.getIndex(1, 2);
            l.argCheck(l.isInteger(-1), 1, "MIDI data should be integers!");
            const second = std.math.cast(u7, l.toInteger(-1) catch unreachable) orelse
                l.argError(1, "MIDI data should be 0-127");
            l.pop(1);
            buf.addChar(second);
        },
        else => {},
    }
    buf.pushResult();
    return 1;
}

fn bytesToEvents(l: *Lua, in: *In) void {
    const top = l.getTop();
    defer (std.debug.assert(l.getTop() == top));
    const len = in.buf.len();
    if (len == 0) return;
    const buf = l.allocator().alloc(u8, len) catch panic("out of memory!", .{});
    defer l.allocator().free(buf);
    const size = in.buf.read(buf);
    var idx: usize = 0;
    while (idx < size) : (idx += 1) {
        if (in.sysex_handle) |h| {
            if (buf[idx] != @as(u8, @bitCast(Status.sysex_end))) continue;
            lu.preparePublish(l, &.{ "midi", "sysex" });
            _ = l.pushStringZ(in.name);
            _ = l.rawGetIndex(ziglua.registry_index, h);
            _ = l.pushString(buf[0..idx]);
            l.concat(2);
            l.call(3, 0);
            l.unref(ziglua.registry_index, h);
            in.sysex_handle = null;
            continue;
        }
        std.debug.assert(buf[idx] > 0x7f);
        const status: Status = @bitCast(buf[idx]);
        if (@as(u8, @bitCast(status)) != 0xf0 and status.kind != .note_on) {
            lu.preparePublish(l, &.{ "midi", name(status) });
            _ = l.pushStringZ(in.name);
        }
        switch (status.kind) {
            .note_on => {
                lu.preparePublish(l, &.{ "midi", if (buf[idx + 2] != 0) "note_on" else "note_off" });
                _ = l.pushStringZ(in.name);
                l.pushInteger(@as(u8, status.channel) + 1);
                l.pushInteger(buf[idx + 1]);
                l.pushInteger(if (buf[idx + 2] == 0) 64 else 0);
                l.call(5, 0);
                idx += 2;
            },
            .note_off, .aftertouch, .control_change => {
                l.pushInteger(@as(u8, status.channel) + 1);
                l.pushInteger(buf[idx + 1]);
                l.pushInteger(buf[idx + 2]);
                l.call(5, 0);
                idx += 2;
            },
            .program_change, .channel_pressure => {
                l.pushInteger(@as(u8, status.channel) + 1);
                l.pushInteger(buf[idx + 1]);
                l.call(4, 0);
                idx += 1;
            },
            .pitch_wheel => {
                l.pushInteger(@as(u8, status.channel) + 1);
                var data: u14 = @as(u14, buf[idx + 1]) << 7;
                data += buf[idx + 2];
                l.pushInteger(data);
                l.call(4, 0);
                idx += 2;
            },
            .other => switch (status.channel) {
                // sysex_begin
                0 => {
                    if (std.mem.indexOfScalarPos(u8, buf[0..size], idx, 0xf7)) |next| {
                        lu.preparePublish(l, &.{ "midi", "sysex" });
                        _ = l.pushStringZ(in.name);
                        _ = l.pushString(buf[idx..next]);
                        l.call(3, 0);
                        idx = next;
                    } else {
                        _ = l.pushString(buf[idx..size]);
                        in.sysex_handle = l.ref(ziglua.registry_index) catch panic("unable to save incomplete message!", .{});
                        idx = size;
                    }
                },
                // quarter_frame, song_select
                1, 3 => {
                    l.pushInteger(buf[idx + 1]);
                    l.call(3, 0);
                    idx += 1;
                },
                2 => {
                    l.pushInteger(buf[idx + 1]);
                    l.pushInteger(buf[idx + 2]);
                    l.call(4, 0);
                    idx += 2;
                },
                else => l.call(2, 0),
            },
        }
    }
}

fn pushMsgs(l: *Lua) i32 {
    const i = Lua.upvalueIndex(1);
    const j = Lua.upvalueIndex(2);
    const bytes = l.toString(i) catch unreachable;
    const idx: usize = @intCast(l.toInteger(j) catch unreachable);
    if (idx >= bytes.len) return 0;
    if (bytes[idx] < 0x80) l.raiseErrorStr("MIDI message contained no status byte!", .{});
    const status: Status = @bitCast(bytes[idx]);
    l.newTable();
    if (status.kind != .other and status.kind != .note_on) {
        _ = l.pushStringZ(@tagName(status.kind));
        l.setIndex(-2, 1);
        l.pushInteger(@as(u8, status.channel) + 1);
        l.setIndex(-2, 2);
        switch (status.kind) {
            .note_on, .other => unreachable,
            .note_off, .aftertouch, .control_change => {
                if (idx + 2 >= bytes.len) l.raiseErrorStr("MIDI message incomplete!", .{});
                l.pushInteger(bytes[idx + 1]);
                l.setIndex(-2, 3);
                l.pushInteger(bytes[idx + 2]);
                l.setIndex(-2, 4);
                l.pushInteger(@intCast(idx + 3));
                l.replace(j);
                return 1;
            },
            .program_change, .channel_pressure => {
                if (idx + 1 >= bytes.len) l.raiseErrorStr("MIDI message incomplete!", .{});
                l.pushInteger(bytes[idx + 1]);
                l.setIndex(-2, 3);
                l.pushInteger(@intCast(idx + 2));
                l.replace(j);
                return 1;
            },
            .pitch_wheel => {
                if (idx + 2 >= bytes.len) l.raiseErrorStr("MIDI message incomplete!", .{});
                var data: u14 = @as(u14, (bytes[idx + 1])) << 7;
                data += bytes[idx + 2];
                l.pushInteger(data);
                l.setIndex(-2, 3);
                l.pushInteger(@intCast(idx + 2));
                l.replace(j);
                return 1;
            },
        }
    }
    if (status.kind == .note_on) {
        if (idx + 2 >= bytes.len) l.raiseErrorStr("MIDI message incomplete!", .{});
        _ = l.pushStringZ(if (bytes[idx + 2] == 0) "note_off" else "note_on");
        l.setIndex(-2, 1);
        l.pushInteger(@as(u8, status.channel) + 1);
        l.setIndex(-2, 2);
        l.pushInteger(bytes[idx + 1]);
        l.setIndex(-2, 3);
        l.pushInteger(if (bytes[idx + 2] == 0) 64 else bytes[idx + 2]);
        l.setIndex(-2, 4);
        l.pushInteger(@intCast(idx + 3));
        l.replace(j);
        return 1;
    }
    switch (status.channel) {
        0 => {
            if (std.mem.indexOfScalarPos(u8, bytes, idx, 0xf7)) |next| {
                _ = l.pushStringZ("sysex");
                l.setIndex(-2, 1);
                _ = l.pushString(bytes[idx..next]);
                l.setIndex(-2, 2);
                l.pushInteger(@intCast(next + 1));
                l.replace(j);
                return 1;
            }
            l.raiseErrorStr("MIDI message incomplete!", .{});
        },
        1, 3 => {
            if (idx + 1 >= bytes.len) l.raiseErrorStr("MIDI message incomplete!", .{});
            _ = l.pushStringZ(name(status));
            l.setIndex(-2, 1);
            l.pushInteger(bytes[idx + 1]);
            l.setIndex(-2, 2);
            l.pushInteger(@intCast(idx + 2));
            l.replace(j);
            return 1;
        },
        2 => {
            if (idx + 2 >= bytes.len) l.raiseErrorStr("MIDI message incomplete!", .{});
            _ = l.pushStringZ(name(status));
            l.setIndex(-2, 1);
            l.pushInteger(bytes[idx + 1]);
            l.setIndex(-2, 2);
            l.pushInteger(bytes[idx + 2]);
            l.setIndex(-2, 3);
            l.pushInteger(@intCast(idx + 3));
            l.replace(j);
            return 1;
        },
        else => {
            _ = l.pushStringZ(name(status));
            l.setIndex(-2, 1);
            l.pushInteger(@intCast(idx + 1));
            l.replace(j);
            return 1;
        },
    }
}

fn msgIterator(l: *Lua) i32 {
    _ = l.checkString(1);
    l.pushValue(1);
    l.pushInteger(0);
    l.pushClosure(ziglua.wrap(pushMsgs), 2);
    return 1;
}

fn checkInput(ud: ?*Midi, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    const self = ud.?;
    _ = r catch return .rearm;
    const l = Wheel.getLua(loop);
    for (self.ins.items) |*in| bytesToEvents(l, in);
    self.timer.run(loop, c, 1, Midi, self, checkInput);
    return .disarm;
}

fn callback(_: f64, msg: []const u8, ctx: ?*anyopaque) void {
    const in: *In = @ptrCast(@alignCast(ctx.?));
    const len = in.buf.write(msg);
    if (len != msg.len) panic("ring buffer overflow!", .{});
}

fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    const self = try allocator.create(Midi);
    m.self = self;
    self.* = .{
        .ins = try std.ArrayList(In).initCapacity(allocator, 8),
        .outs = try std.ArrayList(Out).initCapacity(allocator, 8),
        .timer = try xev.Timer.init(),
        .ins_list = undefined,
        .outs_list = undefined,
        .last = lu.getWheel(l).timer.read(),
    };
    for (0..2) |i| {
        const in = try self.ins.addOne();
        const out = try self.outs.addOne();
        in.* = .{
            .name = if (i == 0) "to seamstress 1" else "to seamstress 2",
            .input = midi.In.createDefault() orelse return error.OutOfMemory,
            .port = .virtual,
        };
        in.input.openVirtualPort(in.name);
        out.* = .{
            .name = if (i == 0) "from seamstress 1" else "from seamstress 2",
            .output = midi.Out.createDefault() orelse return error.OutOfMemory,
            .refs = 1,
            .port = .virtual,
        };
        out.output.openVirtualPort(out.name);
    }
    const ins, const outs = try self.scan(allocator);
    self.ins_list = ins;
    self.outs_list = outs;
    self.registerSeamstress(l);
}

fn launch(m: *const Module, _: *Lua, wheel: *Wheel) anyerror!void {
    const self: *Midi = @ptrCast(@alignCast(m.self.?));
    self.timer.run(&wheel.loop, &self.c, 1, Midi, self, checkInput);
    for (self.ins.items) |*i| {
        i.input.setCallback(callback, i);
        i.input.ignoreTypes(false, false, true);
    }
}

fn deinit(m: *Module, _: *Lua, allocator: std.mem.Allocator, cleanup: Seamstress.Cleanup) void {
    const self: *Midi = @ptrCast(@alignCast(m.self orelse return));
    for (self.ins.items) |in| {
        in.input.closePort();
        if (!std.mem.startsWith(u8, in.name, "to seamstress")) allocator.free(in.name);
    }
    for (self.outs.items) |out| {
        out.output.closePort();
        if (!std.mem.startsWith(u8, out.name, "from seamstress")) allocator.free(out.name);
    }
    if (cleanup != .full) return;
    for (self.ins.items) |in| in.input.destroy();
    for (self.outs.items) |out| out.output.destroy();
    self.ins.deinit();
    self.outs.deinit();
    allocator.destroy(self);
    m.self = null;
}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .launch_fn = launch,
        .deinit_fn = deinit,
    } };
}

const Module = @import("../module.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const Seamstress = @import("../seamstress.zig");
const Wheel = @import("../wheel.zig");
const xev = @import("xev");
const midi = @import("midi");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const lu = @import("../lua_util.zig");
const panic = std.debug.panic;
const logger = std.log.scoped(.midi);
