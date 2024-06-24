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
};

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
            .sync => |*d| d.beat = getSyncBeat(self.beat, d.sync, d.offset),
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
        // happens via Lua instead
        .midi => {},
    }
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
    for (self.threads.items) |*thread| {
        if (thread.handle == null) continue;
        switch (thread.data) {
            .sleep => |s| if (self.now >= s) thread.bang(l),
            .sync => |s| if (self.beat >= s.beat) thread.bang(l),
        }
    }
    self.t.run(loop, c, 1, Clock, self, tick);
    return .disarm;
}

fn init(m: *Module, l: *Lua, allocator: std.mem.Allocator) anyerror!void {
    const self = try allocator.create(Clock);
    self.* = .{
        .threads = try std.ArrayList(Thread).initCapacity(allocator, 256),
        .link = try lk.Link.create(120) orelse return error.LinkCreationFailed,
        .state = try lk.SessionState.create() orelse return error.LinkCreationFailed,
        .t = try xev.Timer.init(),
    };
    @memset(self.threads.items, .{});
    m.self = self;
    registerSeamstress(l, self);
}

fn launch(m: *const Module, _: *Lua, wheel: *Wheel) anyerror!void {
    const self: *Clock = @ptrCast(@alignCast(m.self.?));
    self.t.run(&wheel.loop, &self.c, 1, Clock, self, tick);
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
/////////
fn updateBeats(self: *Clock) void {
    switch (self.source) {
        .internal => {
            if (!self.is_playing) return;
            const delta_ns = self.now - self.last;
            const beat_time = 1.0 / self.tempo;
            const ns_per_beat = beat_time * std.time.ns_per_min;
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
        .midi => {},
    }
}

/// responds to clock-related midi messages
// users should ... not use this
// @function clock_midi_msg
fn midiMsg(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    lu.checkNumArgs(l, 1);
    const msg = l.checkInteger(1);
    // let's just ignore anything outside of 0-255
    if (msg < 0 or msg > 255) return 0;
    const byte: u8 = @intCast(msg);
    if (clock.source != .midi) {
        if (byte == 0xf8) {
            const now = clock.timer.read();
            clock.midi.durations[clock.midi.head] = now - clock.midi.last;
            clock.midi.head +%= 1;
        }
        return 0;
    }
    switch (byte) {
        0xfa => {
            const now = clock.timer.read();
            clock.midi.durations[clock.midi.head] = now - clock.midi.last;
            clock.midi.head +%= 1;
        },
        0xfc => clock.stop(),
        0xfb => clock.start(),
        0xf8 => {
            const now = clock.timer.read();
            clock.midi.durations[clock.midi.head] = now - clock.midi.last;
            clock.midi.head +%= 1;
        },
        else => {},
    }
    return 0;
}

/// returns the current tempo
// users should use `clock.get_tempo` instead
// @see clock.get_tempo
// @function clock_get_tempo
fn getTempo(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    l.pushNumber(clock.tempo);
    return 1;
}

/// returns the current beat
// users should use `clock.get_beats` instead
// @return beats
// @see clock.get_beats
// @function clock_get_beats
fn getBeats(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    l.pushNumber(clock.beat);
    return 1;
}

/// sets the clock tempo (provided the current source supports it)
// users should use the clock param instead
// @tparam number bpm
// @function clock_set_tempo
fn setTempo(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    lu.checkNumArgs(l, 1);
    const bpm = l.checkNumber(1);
    switch (clock.source) {
        .internal => clock.tempo = bpm,
        .link => {
            clock.state.captureFromApplicationThread(clock.link);
            defer clock.state.commitFromApplicationThread(clock.link);
            const now = clock.link.clockMicros();
            clock.state.setTempo(bpm, now);
        },
        .midi => {},
    }
}

/// sets the Link clock quantum
// users should use the clock param instead
// @tparam number quantum (in beats)
// @function clock_link_set_quantum
fn setLinkQuantum(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    lu.checkNumArgs(l, 1);
    const quantum = l.checkNumber(1);
    clock.link_quantum = quantum;
    return 0;
}

/// cancels coroutine.
// users should use `clock.cancel` instead
// @tparam idx id of coroutine to cancel (1-256)
// @see clock.cancel
// @function clock_cancel
fn cancel(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    lu.checkNumArgs(l, 1);
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 256, 1, "invalid clock id; expected 1-256");
    clock.threads[@intCast(id - 1)].active = false;
    return 0;
}

/// gets the current time in seconds.
// @function get_time
fn getTime(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    const nanoseconds: f64 = @floatFromInt(clock.timer.read());
    l.pushNumber(nanoseconds / std.time.ns_per_s);
    return 1;
}

/// sleeps the given clock for the provided time
// users should use `clock.sleep` instead.
// @tparam int id (1-256)
// @tparam number time time to sleep for
// @see clock.sleep
// @function clock_schedule_sleep
fn scheduleSleep(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    const top = l.getTop();
    if (top < 2) l.raiseErrorStr("clock_schedule_sleep requires at least two arguments!", .{});
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 256, 1, "invalid clock id; expected 1-256");
    const time = l.checkNumber(2);
    const delta: u64 = @intFromFloat(time * std.time.ns_per_s);
    const idx: u8 = @intCast(id - 1);
    clock.threads[idx] = .{
        .active = true,
        .data = .{ .sleep = clock.now + delta },
        .id = idx,
    };
    // nothing to return
    return l.getTop() - 2;
}

/// syncs the given clock to the provided beat
// users should use `clock.sync` instead.
// @tparam int id (1-256)
// @tparam number beat beat division to sync to
// @tparam[opt] number offset offset in beats
// @see clock.sync
// @function clock_schedule_sync
fn scheduleSync(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    const top = l.getTop();
    if (top < 2) l.raiseErrorStr("clock_schedule_sync requires at least two arguments!", .{});
    const id = l.checkInteger(1);
    l.argCheck(1 <= id and id <= 256, 1, "invalid clock id; expected 1-256");
    const sync_beat = l.checkNumber(2);
    const offset: f64 = if (top >= 3) l.checkNumber(3) else 0;
    const idx: u8 = @intCast(id - 1);
    clock.threads[idx] = .{
        .active = true,
        .data = .{ .sync = .{
            .beat = getSyncBeat(clock.beat, sync_beat, offset),
            .sync_beat = sync_beat,
            .offset = offset,
        } },
        .id = idx,
    };
    return if (top >= 3) top - 3 else top - 2;
}

/// starts the link clock
// users should use the clock.param instead
// @function clock_link_start
fn linkStart(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    clock.state.captureFromApplicationThread(clock.link);
    defer clock.state.commitFromApplicationThread(clock.link);
    const now = clock.link.clockMicros();
    clock.state.setIsPlayingAndRequestBeatAtTime(true, now, 0.0, clock.link_quantum);
}

/// stops the link clock
// users should use the clock.param instead
// @function clock_link_stop
fn linkStop(l: *Lua) i32 {
    const clock = lu.closureGetContext(l, Clock) orelse return 0;
    clock.state.captureFromApplicationThread(clock.link);
    defer clock.state.commitFromApplicationThread(clock.link);
    const now = clock.link.clockMicros();
    clock.state.setIsPlaying(false, now);
}

const logger = std.log.scoped(.clock);

const Module = @import("../module.zig");
const Wheel = @import("../wheel.zig");
const Spindle = @import("../spindle.zig");
const Seamstress = @import("../seamstress.zig");
const Cleanup = Seamstress.Cleanup;
const Lua = @import("ziglua").Lua;
const std = @import("std");
const xev = @import("xev");
const lk = @import("link");
const lu = @import("../lua_util.zig");
