const std = @import("std");
const spindle = @import("spindle.zig");
const osc = @import("serialosc.zig");
const monome = @import("monome.zig");
const screen = @import("screen.zig");
const clock = @import("clock.zig");
const metros = @import("metros.zig");
const midi = @import("midi.zig");

const logger = std.log.scoped(.events);

pub const Data = union(enum) {
    Quit: void,
    Reset: void,
    Exec_Code_Line: struct {
        line: [:0]const u8,
    },
    OSC: struct {
        from_host: [:0]const u8,
        from_port: [:0]const u8,
        path: [:0]const u8,
        msg: []osc.Lo_Arg,
    },
    Monome_Add: struct {
        dev: *monome.Monome,
    },
    Monome_Remove: struct {
        id: usize,
    },
    Grid_Key: struct {
        id: usize,
        x: i32,
        y: i32,
        state: i32,
    },
    Grid_Tilt: struct {
        id: usize,
        sensor: i32,
        x: i32,
        y: i32,
        z: i32,
    },
    Arc_Encoder: struct {
        id: usize,
        ring: i32,
        delta: i32,
    },
    Arc_Key: struct {
        id: usize,
        ring: i32,
        state: i32,
    },
    Screen_Key: struct {
        sym: i32,
        mod: u16,
        repeat: bool,
        state: bool,
        window: usize,
    },
    Screen_Mouse_Motion: struct {
        x: f64,
        y: f64,
        window: usize,
    },
    Screen_Mouse_Click: struct {
        x: f64,
        y: f64,
        state: bool,
        button: u8,
        window: usize,
    },
    Screen_Mouse_Wheel: struct {
        x: f64,
        y: f64,
        window: usize,
    },
    Screen_Check: void,
    Screen_Resized: struct {
        w: i32,
        h: i32,
        window: usize,
    },
    Metro: struct {
        id: u8,
        stage: i64,
    },
    MIDI_Add: struct {
        dev: *midi.Device,
    },
    MIDI_Remove: struct {
        id: u32,
    },
    MIDI: struct {
        id: u32,
        msg_num: u64,
        message: []const u8,
    },
    Clock_Resume: struct {
        id: u8,
    },
    Clock_Transport: struct {
        transport: clock.Transport,
    },
};

var allocator: std.mem.Allocator = undefined;

const Context = struct {
    cond: std.Thread.Condition,
    lock: std.Thread.Mutex,
};

fn prioritize(context: Context, a: Data, b: Data) std.math.Order {
    _ = context;
    switch (a) {
        .Clock_Resume, .Metro => {
            switch (b) {
                .Clock_Resume, .Metro => return .eq,
                else => return .lt,
            }
        },
        .Screen_Check => {
            switch (b) {
                .Screen_Check => return .eq,
                else => return .gt,
            }
        },
        .MIDI => |m| {
            switch (b) {
                .Clock_Resume, .Metro => return .gt,
                .Screen_Check => return .lt,
                .MIDI => |n| {
                    if (m.id != n.id) return .eq;
                    if (m.msg_num < n.msg_num) return .lt else return .gt;
                },
                else => return .eq,
            }
        },
        else => {
            switch (b) {
                .Clock_Resume, .Metro => return .gt,
                .Screen_Check => return .lt,
                else => return .eq,
            }
        },
    }
}

const Queue = std.PriorityQueue(Data, Context, prioritize);
var queue: Queue = undefined;

var quit = false;
var reset = false;

pub fn init(alloc_ptr: std.mem.Allocator) !void {
    reset = false;
    quit = false;
    allocator = alloc_ptr;
    queue = Queue.init(allocator, .{ .cond = .{}, .lock = .{} });
    try queue.ensureTotalCapacity(5000);
}

pub fn loop() !bool {
    while (!quit) {
        queue.context.lock.lock();
        while (queue.peek() == null) {
            if (quit) break;
            queue.context.cond.wait(&queue.context.lock);
            continue;
        }
        const ev = queue.removeOrNull();
        queue.context.lock.unlock();
        if (ev) |event| try handle(event);
    }
    return reset;
}

pub fn free(event: Data) void {
    switch (event) {
        .OSC => |e| {
            allocator.free(e.from_host);
            allocator.free(e.from_port);
            allocator.free(e.path);
            allocator.free(e.msg);
        },
        .Exec_Code_Line => |e| {
            allocator.free(e.line);
        },
        .MIDI => |e| {
            allocator.free(e.message);
        },
        else => {},
    }
}

pub fn post(event: Data) void {
    queue.context.lock.lock();
    queue.add(event) catch @panic("too many events!\n");
    queue.context.cond.signal();
    queue.context.lock.unlock();
}

pub fn handle_pending() !void {
    var event: ?Data = null;
    var done = false;
    while (!done) {
        queue.context.lock.lock();
        if (queue.count() > 0) {
            event = queue.removeOrNull();
        } else {
            done = true;
        }
        queue.context.lock.unlock();
        if (event) |ev| try handle(ev);
        event = null;
    }
}

pub fn deinit() void {
    free_pending();
    queue.deinit();
}

fn free_pending() void {
    var event: ?Data = null;
    var done = false;
    while (!done) {
        if (queue.count() > 0) {
            event = queue.remove();
        } else {
            done = true;
        }
        if (event) |ev| free(ev);
        event = null;
    }
}

fn handle(event: Data) !void {
    switch (event) {
        .Quit => quit = true,
        .Reset => {
            quit = true;
            reset = true;
        },
        .Exec_Code_Line => |e| try spindle.exec_code_line(e.line),
        .OSC => |e| try spindle.osc_event(e.from_host, e.from_port, e.path, e.msg),
        .Monome_Add => |e| try spindle.monome_add(e.dev),
        .Monome_Remove => |e| try spindle.monome_remove(e.id),
        .Grid_Key => |e| try spindle.grid_key(e.id, e.x, e.y, e.state),
        .Grid_Tilt => |e| try spindle.grid_tilt(e.id, e.sensor, e.x, e.y, e.z),
        .Arc_Encoder => |e| try spindle.arc_delta(e.id, e.ring, e.delta),
        .Arc_Key => |e| try spindle.arc_key(e.id, e.ring, e.state),
        .Screen_Key => |e| try spindle.screen_key(e.sym, e.mod, e.repeat, e.state, e.window),
        .Screen_Mouse_Motion => |e| try spindle.screen_mouse(e.x, e.y, e.window),
        .Screen_Mouse_Click => |e| try spindle.screen_click(e.x, e.y, e.state, e.button, e.window),
        .Screen_Mouse_Wheel => |e| try spindle.screen_wheel(e.x, e.y, e.window),
        .Screen_Check => {
            screen.check();
            screen.pending -= 1;
        },
        .Screen_Resized => |e| try spindle.screen_resized(e.w, e.h, e.window),
        .Metro => |e| {
            try spindle.metro_event(e.id, e.stage);
        },
        .MIDI_Add => |e| try spindle.midi_add(e.dev),
        .MIDI_Remove => |e| try spindle.midi_remove(e.id),
        .MIDI => |e| {
            switch (e.message[0]) {
                0xfa, 0xfb, 0xfc, 0xf8 => try clock.midi(e.message[0]),
                else => {},
            }
            try spindle.midi_event(e.id, e.message);
        },
        .Clock_Resume => |e| try spindle.resume_clock(e.id),
        .Clock_Transport => |e| try spindle.clock_transport(e.transport),
    }
    free(event);
}
