const Clock = @This();

c: xev.Completion = .{},
t: xev.Timer,
threads: std.ArrayList(Thread),
link: *lk.Link,
state: *lk.SessionState,
link_quantum: f64 = 4,
midi: struct {
    last: u64,
    durations: [8]u64 = .{0} ** 8,
    head: u3 = 0,
},
source: Source = .internal,
beat: f64 = 0,
tempo: f64 = 120,
now: u64 = 0,
last: u64 = 0,
is_playing: bool = true,

const Source = enum { internal, link, midi };
const Thread = struct {
    handle: ?i32 = null,
    data: union(enum) {
        sleep: u64,
        sync: struct {
            beat: f64,
            sync_beat: f64,
            offset: f64,
        },
    } = .{ .sleep = 0 },

    fn bang(self: *Thread, clock: *Clock, l: *Lua) bool {
        _ = l.rawGetIndex(ziglua.registry_index, self.handle.?);
        const thread = l.toThread(-1) catch unreachable;
        return clock.doResume(self, l, thread, false);
    }
};

const Which = enum(ziglua.Integer) { sleep, sync };

fn getSyncBeat(beat: f64, sync_beat: f64, offset: f64) f64 {
    var next: f64 = (std.math.floor((beat + std.math.floatEps(f64)) / sync_beat) + 1) * sync_beat;
    next += offset;
    while (next < (beat + std.math.floatEps(f64))) next += sync_beat;
    return next;
}

fn rescheduleSyncEvents(self: *Clock) void {
    for (self.threads.items) |*thread| {
        if (thread.handle == null) continue;
        switch (thread.data) {
            .sleep => continue,
            .sync => |*d| d.beat = getSyncBeat(self.beat, d.sync_beat, d.offset),
        }
    }
}

fn updateBeats(self: *Clock) void {
    switch (self.source) {
        .internal => {
            if (!self.is_playing) return;
            const delta_ns = self.now - self.last;
            const minutes_per_beat = 1.0 / self.tempo;
            const ns_per_beat = minutes_per_beat * std.time.ns_per_min;
            self.beat += @as(f64, @floatFromInt(delta_ns)) / ns_per_beat;
        },
        .link => {
            const last = self.beat;
            {
                self.state.captureFromApplicationThread(self.link);
                defer self.state.commitFromApplicationThread(self.link);
                const time = self.link.clockMicros();
                self.tempo = self.state.tempo();
                self.beat = self.state.beatAtTime(time, self.link_quantum);
                self.is_playing = self.state.isPlaying();
            }
            if (last > self.beat) self.rescheduleSyncEvents();
        },
        .midi => {
            const midi_ppqn = 48;
            var sum: u64 = 0;
            for (&self.midi.durations) |dur| sum += dur;
            const tick_ns = @divFloor(sum, 8);
            const ns_per_beat: f64 = @floatFromInt(midi_ppqn * tick_ns);
            self.beat += @as(f64, @floatFromInt(self.now - self.last)) / ns_per_beat;
            self.tempo = std.time.ns_per_min / ns_per_beat;
        },
    }
}

fn sort(clock: *Clock) void {
    var active_idx: usize = 0;
    for (clock.threads.items) |thread| {
        if (thread.handle != null) {
            clock.threads.items[active_idx] = thread;
            active_idx += 1;
        }
    }
    clock.threads.items.len = active_idx;
}

fn tick(clock: ?*Clock, loop: *xev.Loop, c: *xev.Completion, r: xev.Timer.RunError!void) xev.CallbackAction {
    _ = r catch {
        logger.err("error running clock timer!", .{});
        return .rearm;
    };
    const wheel: *Wheel = @fieldParentPtr("loop", loop);
    const l = Wheel.getLua(loop);
    const self = clock.?;
    self.last = self.now;
    self.now = wheel.timer.read();
    self.updateBeats();
    var any_stopped = false;
    for (self.threads.items) |*thread| {
        if (thread.handle == null) {
            logger.err("canceled clock appeared in list!", .{});
            continue;
        }
        any_stopped = any_stopped or switch (thread.data) {
            .sleep => |s| if (self.now >= s) thread.bang(self, l) else false,
            .sync => |s| if (self.beat >= s.beat) thread.bang(self, l) else false,
        };
    }
    if (any_stopped) self.sort();
    self.t.run(loop, c, 1, Clock, self, tick);
    return .disarm;
}

const MidiClockMsg = enum(u8) {
    clock = 0xf8,
    start = 0xfa,
    stop = 0xfc,
    @"continue" = 0xfb,
};

const string_map = std.StaticStringMap(MidiClockMsg).initComptime(.{
    .{ "clock", .clock },
    .{ "start", .start },
    .{ "stop", .stop },
    .{ "continue", .@"continue" },
});

fn midiMsg(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock);
    lu.checkNumArgs(l, 1);
    const msg = l.checkString(1);
    const clock_msg = string_map.get(msg) orelse return 0;
    const wheel = lu.getWheel(l);
    if (clock.source != .midi) {
        if (clock_msg == .clock) {
            const now = wheel.timer.read();
            clock.midi.durations[clock.midi.head] = now - clock.midi.last;
            clock.midi.head +%= 1;
        }
        return 0;
    }
    switch (clock_msg) {
        .clock, .start => {
            const now = wheel.timer.read();
            clock.midi.durations[clock.midi.head] = now - clock.midi.last;
            clock.midi.head +%= 1;
            if (clock_msg == .start) clock.is_playing = true;
        },
        .stop => clock.is_playing = false,
        .@"continue" => clock.is_playing = true,
    }
    return 0;
}

const fields: [5][]const u8 = .{
    "source",
    "tempo",
    "beat",
    "link_quantum",
    "is_playing",
};

fn index(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock);
    switch (l.typeOf(2)) {
        .string => {
            const key = l.toString(2) catch unreachable;
            inline for (fields) |field| {
                if (std.mem.eql(u8, field, key)) {
                    l.pushAny(@field(clock, field)) catch unreachable;
                    return 1;
                }
            }

            if (std.mem.eql(u8, key, "time")) {
                const wheel = lu.getWheel(l);
                const nanoseconds: f64 = @floatFromInt(wheel.timer.read());
                l.pushNumber(nanoseconds / std.time.ns_per_s);
                return 1;
            }
        },
        else => {},
    }
    l.pushValue(2);
    _ = l.rawGetTable(1);
    return 1;
}

fn newIndex(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock);
    switch (l.typeOf(2)) {
        .string => {
            const key = l.toString(2) catch unreachable;
            if (std.mem.eql(u8, key, "is_playing")) {
                clock.is_playing = l.toBoolean(3);
                switch (clock.source) {
                    .link => {
                        clock.state.captureFromApplicationThread(clock.link);
                        defer clock.state.commitFromApplicationThread(clock.link);
                        const now = clock.link.clockMicros();
                        clock.state.setIsPlaying(l.toBoolean(3), now);
                    },
                    else => {},
                }
                return 0;
            }
            if (std.mem.eql(u8, key, "tempo")) {
                const tempo = l.checkNumber(3);
                l.argCheck(tempo > std.math.floatEps(f64), 3, "tempo must be positive");
                clock.tempo = tempo;
                switch (clock.source) {
                    .link => {
                        clock.state.captureFromApplicationThread(clock.link);
                        defer clock.state.commitFromApplicationThread(clock.link);
                        const now = clock.link.clockMicros();
                        clock.state.setTempo(clock.tempo, now);
                    },
                    else => {},
                }
                return 0;
            }

            if (std.mem.eql(u8, key, "beat")) {
                const beat = l.checkNumber(3);
                clock.beat = beat;
                clock.rescheduleSyncEvents();
                switch (clock.source) {
                    .link => {
                        clock.state.captureFromApplicationThread(clock.link);
                        defer clock.state.commitFromApplicationThread(clock.link);
                        const now = clock.link.clockMicros();
                        clock.state.requestBeatAtTime(clock.beat, now, clock.link_quantum);
                    },
                    else => {},
                }
                return 0;
            }

            if (std.mem.eql(u8, key, "link_quantum")) {
                const quantum = l.checkNumber(3);
                l.argCheck(quantum > std.math.floatEps(f64), 3, "link_quantum must be positive");
                clock.link_quantum = quantum;
                return 0;
            }

            if (std.mem.eql(u8, key, "time")) {
                l.raiseErrorStr("time is read-only", .{});
            }

            if (std.mem.eql(u8, key, "source")) {
                if (l.typeOf(3) == .string) {
                    const val = l.toString(3) catch unreachable;
                    const info = @typeInfo(Source);
                    inline for (info.Enum.fields) |tag| {
                        if (std.mem.eql(u8, val, tag.name)) {
                            clock.source = @enumFromInt(tag.value);
                            clock.link.enable(clock.source == .link);
                            return 0;
                        }
                    }
                }
                l.typeError(3, "'link', 'midi' or 'internal'");
            }
        },
        else => {},
    }
    l.pushValue(2);
    l.pushValue(3);
    l.rawSetTable(1);
    return 0;
}

/// called from bang and run
fn doResume(clock: *Clock, self: *Thread, parent: *Lua, child: *Lua, is_start: bool) bool {
    var res: i32 = undefined;
    const status = child.resumeThread(parent, if (is_start) child.getTop() - 1 else 0, &res) catch {
        const msg = child.toStringEx(-1);
        child.traceback(parent, msg, 1);
        child.xMove(parent, 1);
        parent.raiseError();
        return true;
    }; // returns on coroutine.yield() as well our thing... pretend it's `sleep(0)`
    switch (status) {
        .ok => {
            parent.unref(ziglua.registry_index, self.handle.?);
            self.handle = null;
            return true;
        },
        .yield => {
            self.data = blk: {
                if (res == 0) break :blk .{ .sleep = clock.now };
                if (!child.isInteger(-res)) break :blk .{ .sleep = clock.now };
                const which = std.meta.intToEnum(Which, child.toInteger(-res) catch unreachable) catch break :blk .{ .sleep = clock.now };
                switch (which) {
                    .sleep => {
                        if (res == 1) break :blk .{ .sleep = clock.now };
                        switch (child.typeOf(-res + 1)) {
                            .number => {
                                const sleep_time_secs = child.toNumber(-res + 1) catch unreachable;
                                const sleep_time_ns: u64 = @intFromFloat(sleep_time_secs * std.time.ns_per_s);
                                break :blk .{ .sleep = clock.now + sleep_time_ns };
                            },
                            else => break :blk .{ .sleep = clock.now },
                        }
                    },
                    .sync => {
                        if (res == 1) break :blk .{ .sync = .{
                            .beat = getSyncBeat(clock.beat, 1, 0),
                            .sync_beat = 1,
                            .offset = 0,
                        } };
                        switch (child.typeOf(-res + 1)) {
                            .number => {
                                const sync_beat = child.toNumber(-res + 1) catch unreachable;
                                const offset: f64 = offset: {
                                    if (res == 2) break :offset 0;
                                    break :offset switch (child.typeOf(-res + 2)) {
                                        .number => child.toNumber(-res + 2) catch unreachable,
                                        else => 0,
                                    };
                                };
                                break :blk .{ .sync = .{
                                    .beat = getSyncBeat(clock.beat, sync_beat, offset),
                                    .sync_beat = sync_beat,
                                    .offset = offset,
                                } };
                            },
                            else => break :blk .{ .sync = .{
                                .beat = getSyncBeat(clock.beat, 1, 0),
                                .sync_beat = 1,
                                .offset = 0,
                            } },
                        }
                    },
                }
            };
        },
    }
    child.pop(res);
    return false;
}

/// creates and runs a coroutine
fn run(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock);
    lu.checkCallable(l, 1);
    l.pop(1);
    const top = l.getTop();
    const thread = l.newThread();
    l.insert(1);
    l.xMove(thread, top);
    l.createTable(0, 2);
    l.rotate(-2, 1);
    l.pushValue(-1);
    const handle = l.ref(ziglua.registry_index) catch l.raiseErrorStr("error registering clock!", .{});
    l.setField(-2, "coro");
    l.pushInteger(handle);
    l.setField(-2, "id");
    const t = clock.threads.addOne() catch l.raiseErrorStr("out of memory!", .{});
    t.handle = handle;
    const res = clock.doResume(t, l, thread, true);
    if (res) clock.sort();
    return 1;
}

/// cancels a clock
fn cancel(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock);
    const handle = switch (l.typeOf(1)) {
        .number => l.checkInteger(1),
        .table => if (l.getField(1, "id") == .number) l.toInteger(-1) catch {
            l.argError(1, "id or clock");
        } else l.argError(1, "id or clock"),
        else => l.argError(1, "id or clock"),
    };
    const id: i32 = @intCast(handle);
    for (clock.threads.items) |*t| {
        if (t.handle) |h| if (h == id) {
            l.unref(ziglua.registry_index, h);
            t.handle = null;
            clock.sort();
            if (l.typeOf(1) == .table) {
                l.pushNil();
                l.setField(1, "id");
                if (l.getField(1, "coro") == .thread) {
                    const thread = l.toThread(-1) catch unreachable;
                    if (thread.isYieldable()) thread.closeThread(l) catch unreachable;
                }
                l.pushNil();
                l.setField(1, "coro");
            }
            return 0;
        };
    }
    l.argError(1, "unable to cancel clock—not found!");
}

fn schedule(comptime which: Which) fn (*Lua) i32 {
    return struct {
        fn f(l: *Lua) i32 {
            if (!l.isYieldable()) l.raiseErrorStr(switch (which) {
                .sleep => "cannot schedule sleep from outside of a clock",
                .sync => "cannot schedule sync from outside of a clock",
            }, .{});
            const top = l.getTop();
            l.pushInteger(@intFromEnum(which));
            l.insert(1);
            l.yield(top + 1);
        }
    }.f;
}

fn registerSeamstress(l: *Lua, clock: *Clock) !void {
    const top = l.getTop();
    defer (std.debug.assert(top == l.getTop()));
    lu.getSeamstress(l); // seamstress
    _ = l.pushStringZ("clock"); // clock
    l.newTable(); // t
    _ = l.pushStringZ("run"); // run
    l.pushLightUserdata(clock);
    l.pushClosure(ziglua.wrap(run), 1); // f
    l.setTable(-3); // t.run = f
    _ = l.pushStringZ("cancel"); // cancel
    l.pushLightUserdata(clock);
    l.pushClosure(ziglua.wrap(cancel), 1); // f
    l.setTable(-3); // t.cancel = f
    _ = l.pushStringZ("sleep"); // sleep
    l.pushFunction(ziglua.wrap(schedule(.sleep))); // f
    l.setTable(-3); // t.sleep = f
    _ = l.pushStringZ("sync"); // sync
    l.pushFunction(ziglua.wrap(schedule(.sync))); // f
    l.setTable(-3); // t.sync = f
    _ = l.pushStringZ("midi"); // midi
    l.pushLightUserdata(clock);
    l.pushClosure(ziglua.wrap(midiMsg), 1); // f
    l.setTable(-3); // t.midi = f
    l.newTable(); // mt
    _ = l.pushStringZ("__index"); // __index
    l.pushLightUserdata(clock);
    l.pushClosure(ziglua.wrap(index), 1); // f
    l.setTable(-3); // mt.__index = f
    _ = l.pushStringZ("__newindex"); // __newindex
    l.pushLightUserdata(clock);
    l.pushClosure(ziglua.wrap(newIndex), 1); // f
    l.setTable(-3); // mt.__newindex = f
    l.setMetatable(-2); // setmetatable(t, mt)
    l.setTable(-3); // seamstress.clock = t
    l.pop(1);
}

fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    const self = try allocator.create(Clock);
    self.* = .{
        .threads = try std.ArrayList(Thread).initCapacity(allocator, 256),
        .link = lk.Link.create(120) orelse return error.LinkCreationFailed,
        .state = lk.SessionState.create() orelse return error.LinkCreationFailed,
        .t = try xev.Timer.init(),
        .midi = .{ .last = 0 },
    };
    @memset(self.threads.items, .{});
    m.self = self;
    try registerSeamstress(l, self);
}

fn launch(m: *const Module, _: *Lua, wheel: *Wheel) anyerror!void {
    const self: *Clock = @ptrCast(@alignCast(m.self.?));
    self.t.run(&wheel.loop, &self.c, 1, Clock, self, tick);
    self.link.enableStartStopSync(true);
    self.link.enable(false);
    self.now = wheel.timer.read();
    self.midi.last = wheel.timer.read();
}

fn deinit(m: *Module, _: *Lua, allocator: std.mem.Allocator, cleanup: Cleanup) void {
    const self: *Clock = @ptrCast(@alignCast(m.self orelse return));
    self.link.destroy();
    if (cleanup != .full) return;
    self.state.destroy();
    self.threads.deinit();
    allocator.destroy(self);
    m.self = null;
}

pub fn module() Module {
    return .{ .vtable = &.{
        .init_fn = init,
        .deinit_fn = deinit,
        .launch_fn = launch,
    } };
}

const logger = std.log.scoped(.clock);

const Module = @import("../module.zig");
const Wheel = @import("../wheel.zig");
const Spindle = @import("../spindle.zig");
const Seamstress = @import("../seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const std = @import("std");
const xev = @import("xev");
const lk = @import("link");
const lu = @import("../lua_util.zig");
