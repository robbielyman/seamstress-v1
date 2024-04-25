/// metros module

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

// sets up the metros
fn init(m: *Module, vm: *Spindle) Error!void {
    const self = try vm.allocator.create(Metros);
    self.* = .{
        .vm = vm,
        .pool = try std.heap.MemoryPoolExtra(Metros.Event, .{}).initPreheated(vm.allocator, 36 * 16),
    };
    for (&self.metros, 0..) |*metro, i| {
        metro.* = .{
            .timer = std.time.Timer.start() catch return error.LaunchFailed,
            .id = @intCast(i),
            .parent = self,
        };
    }
    m.self = self;
    lu.registerSeamstress(vm, "metro_start", metroStart, self);
    lu.registerSeamstress(vm, "metro_stop", metroStop, self);
    lu.registerSeamstress(vm, "metro_set_time", metroSetTime, self);
}

// tears down metros
fn deinit(m: *const Module, vm: *Spindle, cleanup: Cleanup) void {
    const self: *Metros = @ptrCast(@alignCast(m.self orelse return));
    for (&self.metros) |*metro| {
        @atomicStore(bool, &metro.running, false, .release);
        switch (cleanup) {
            .full => if (metro.thread) |pid| pid.join(),
            .clean, .panic => if (metro.thread) |pid| pid.detach(),
        }
    }
    if (cleanup != .full) return;
    self.pool.deinit();
    vm.allocator.destroy(self);
}

fn launch(_: *const Module, _: *Spindle) Error!void {}

const Metros = struct {
    const max_num_metros = 36;
    vm: *Spindle,
    pool: std.heap.MemoryPoolExtra(Event, .{}),
    metros: [max_num_metros]Metro = undefined,

    const Metro = struct {
        timer: std.time.Timer,
        running: bool = false,
        seconds: f64 = 1.0,
        count: i64 = -1,
        stage: i64 = 0,
        delta: u64 = std.time.ns_per_s,
        time: u64 = 0,
        thread: ?std.Thread = null,
        id: u8,
        parent: *Metros,

        fn loop(self: *Metro) void {
            @atomicStore(bool, &self.running, true, .release);
            self.time = self.timer.read();
            while (true) {
                self.time += @atomicLoad(u64, &self.delta, .acquire);
                const wait_time = self.time -| self.timer.read();
                if (wait_time > 0) std.time.sleep(wait_time);
                if (!@atomicLoad(bool, &self.running, .acquire)) break;

                const stage = @atomicRmw(i64, &self.stage, .Add, 1, .acquire);
                const ev = self.parent.pool.create() catch {
                    lu.panic(self.parent.vm, error.OutOfMemory);
                    return;
                };
                ev.* = .{ .metro = self, .stage = stage };
                const count = @atomicLoad(i64, &self.count, .acquire);
                if (stage + 1 >= count and count > 0)
                    @atomicStore(bool, &self.running, false, .release);
                self.parent.vm.events.submit(&ev.node);
            }
        }

        fn init(self: *Metro, delta: u64, count: i64) !void {
            @atomicStore(u64, &self.delta, delta, .unordered);
            @atomicStore(i64, &self.count, count, .unordered);
            self.thread = try std.Thread.spawn(.{}, loop, .{self});
        }

        fn stop(self: *Metro) void {
            @atomicStore(bool, &self.running, false, .release);
            if (self.thread) |pid| pid.detach();
            self.thread = null;
        }

        fn reset(self: *Metro, stage: i64) void {
            @atomicStore(i64, &self.stage, if (stage > 0) stage else 0, .release);
        }
    };

    const Event = struct {
        metro: *Metro,
        stage: i64,
        node: Events.Node = .{
            .handler = Events.handlerFromClosure(Event, bang, "node"),
        },

        fn bang(self: *Event, l: *Lua) void {
            defer self.metro.parent.pool.destroy(self);
            lu.getMethod(l, "metro", "event");
            l.pushInteger(self.metro.id + 1);
            l.pushInteger(self.stage);
            lu.doCall(l, 2, 0);
        }
    };
};

/// sets repetition time for a metro.
// users can use the `time` field on a metro instead.
// @tparam integer idx metro id (1-36)
// @tparam number period new period in seconds
// @function metro_set_time
fn metroSetTime(l: *Lua) i32 {
    lu.checkNumArgs(l, 2);
    const metros = lu.closureGetContext(l, Metros) orelse return 0;
    const idx = l.checkInteger(1);
    l.argCheck(1 <= idx and idx <= 36, 1, "invalid index; max count of metros is 36");
    const seconds = l.checkNumber(2);
    const metro = &metros.metros[@intCast(idx - 1)];
    if (seconds > 0.0) {
        metro.seconds = seconds;
    }
    const delta: u64 = @intFromFloat(metro.seconds * std.time.ns_per_s);
    // do this atomically in case the metro is running
    @atomicStore(u64, &metro.delta, delta, .release);
    return 0;
}

/// stops a metro.
// users should use `metro:stop` instead
// @tparam integer idx metro id (1-36)
// @see metro:stop
// @function metro_stop
fn metroStop(l: *Lua) i32 {
    lu.checkNumArgs(l, 1);
    const metros = lu.closureGetContext(l, Metros) orelse return 0;
    const idx = l.checkInteger(1);
    l.argCheck(1 <= idx and idx <= 36, 1, "invalid index; max count of metros is 36");
    // stop it
    metros.metros[@intCast(idx - 1)].stop();
    // nothing to return
    return 0;
}

/// starts a new metro.
// users should use `metro:start` instead
// @tparam integer idx metro id (1-36)
// @tparam number seconds time at which to repeat
// @tparam integer count stage at which to stop
// @tparam integer stage stage at which to start
// @see metro:start
// @function metro_start
fn metroStart(l: *Lua) i32 {
    lu.checkNumArgs(l, 4);
    const metros = lu.closureGetContext(l, Metros) orelse return 0;
    const idx = l.checkInteger(1);
    const seconds = l.checkNumber(2);
    const count: i64 = count: {
        if (l.isInteger(3)) break :count l.checkInteger(3);
        break :count @intFromFloat(l.checkNumber(3));
    };
    const stage: i64 = stage: {
        if (l.isInteger(4)) break :stage l.checkInteger(4) - 1;
        break :stage @intFromFloat(l.checkNumber(4) - 1);
    };
    l.argCheck(1 <= idx and idx <= 36, 1, "invalid index; max count of metros is 36");
    const metro = &metros.metros[@intCast(idx - 1)];
    // stop the metro if it was running
    metro.stop();
    if (seconds > 0.0) metro.seconds = seconds;
    const delta: u64 = @intFromFloat(metro.seconds * std.time.ns_per_s);
    // set the stage
    metro.reset(stage);
    // start the metro
    metro.init(delta, count) catch l.raiseErrorStr("error spawning thread!", .{});
    // nothing to return
    return 0;
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
const Cleanup = Seamstress.Cleanup;
const Spindle = @import("spindle.zig");
const Events = @import("events.zig");
const Module = @import("module.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("lua_util.zig");
const std = @import("std");
