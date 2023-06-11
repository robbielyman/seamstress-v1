const std = @import("std");
const spindle = @import("spindle.zig");
const osc = @import("osc.zig");
const monome = @import("monome.zig");
const screen = @import("screen.zig");
const c = std.c;

pub const Event = enum(u4) {
    // list of event types
    Quit,
    Exec_Code_Line,
    OSC,
    Reset_LVM,
    Monome_Add,
    Monome_Remove,
    Grid_Key,
    Grid_Tilt,
    Arc_Encoder,
    Arc_Key,
    Screen_Key,
    Screen_Check,
    Metro,
    MIDI,
};

pub const Data = union(Event) {
    Quit: void,
    Exec_Code_Line: event_exec_code_line,
    OSC: event_osc,
    Reset_LVM: void,
    Monome_Add: event_monome_add,
    Monome_Remove: event_monome_remove,
    Grid_Key: event_grid_key,
    Grid_Tilt: event_grid_tilt,
    Arc_Encoder: event_arc_delta,
    Arc_Key: event_arc_key,
    Screen_Key: event_screen_key,
    Screen_Check: void,
    Metro: event_metro,
    MIDI: event_midi,
    // event data struct
};

const event_exec_code_line = struct { line: [:0]const u8 = undefined };

const event_osc = struct {
    from_host: [:0]const u8 = undefined,
    from_port: [:0]const u8 = undefined,
    path: [:0]const u8 = undefined,
    msg: []osc.Lo_Arg = undefined,
};

const event_monome_add = struct {
    dev: *monome.Device = undefined,
    // device
};

const event_monome_remove = struct { id: usize = undefined };

const event_grid_key = struct { id: usize = undefined, x: u32 = undefined, y: u32 = undefined, state: i2 = undefined };

const event_grid_tilt = struct { id: usize = undefined, sensor: u32 = undefined, x: i32 = undefined, y: i32 = undefined, z: i32 = undefined };

const event_arc_delta = struct { id: usize = undefined, ring: u32 = undefined, delta: i32 = undefined };

const event_arc_key = struct { id: usize = undefined, ring: u32 = undefined, state: i2 = undefined };

const event_screen_key = struct { scancode: i32 = undefined };

const event_screen_check = struct {};

const event_metro = struct { id: u8 = undefined, stage: i64 = undefined };

const event_midi = struct { source: i32 = undefined, timestamp: u64 = undefined, words: []const u32 = undefined };

var allocator: std.mem.Allocator = undefined;

const Event_Node = struct {
    // node in linked list
    next: ?*Event_Node,
    prev: ?*Event_Node,
    ev: *Data,
};

const Event_Queue = struct { head: ?*Event_Node, tail: ?*Event_Node, size: usize, lock: std.Thread.Mutex, cond: std.Thread.Condition };

var queue = Event_Queue{
    // event queue
    .head = null,
    .tail = null,
    .size = 0,
    .lock = .{},
    .cond = .{},
};

var quit: bool = false;
var pool: []?Data = undefined;

pub fn init(alloc_ptr: std.mem.Allocator) !void {
    allocator = alloc_ptr;
}

test "init" {
    try init(std.testing.allocator);
}

pub fn loop() !void {
    defer allocator.free(pool);
    //  var event = try new(Event.Exec_Code_Line);
    //  var line = try allocator.allocSentinel(u8, 6, 0);
    //  std.mem.copyForwards(u8, line, "init()");
    //  event.Exec_Code_Line.line = line;
    //  try post(event);

    while (!quit) {
        queue.lock.lock();
        while (queue.size == 0) {
            if (quit) break;
            queue.cond.wait(&queue.lock);
            continue;
        }
        const ev = remove_from_head();
        queue.lock.unlock();
        if (ev != null) try handle(ev.?);
    }
}

pub fn new(event_type: Event) !*Data {
    var event = try allocator.create(Data);
    event.* = switch (event_type) {
        Event.Quit => Data{ .Quit = {} },
        Event.Exec_Code_Line => Data{ .Exec_Code_Line = event_exec_code_line{} },
        Event.Reset_LVM => Data{ .Reset_LVM = {} },
        Event.OSC => Data{ .OSC = event_osc{} },
        Event.Monome_Add => Data{ .Monome_Add = event_monome_add{} },
        Event.Monome_Remove => Data{ .Monome_Remove = event_monome_remove{} },
        Event.Grid_Key => Data{ .Grid_Key = event_grid_key{} },
        Event.Grid_Tilt => Data{ .Grid_Tilt = event_grid_tilt{} },
        Event.Arc_Encoder => Data{ .Arc_Encoder = event_arc_delta{} },
        Event.Arc_Key => Data{ .Arc_Key = event_arc_key{} },
        Event.Screen_Key => Data{ .Screen_Key = event_screen_key{} },
        Event.Screen_Check => Data{ .Screen_Check = {} },
        Event.Metro => Data{ .Metro = event_metro{} },
        Event.MIDI => Data{ .MIDI = event_midi{} },
    };
    return event;
}

pub fn free(event: *Data) void {
    switch (event.*) {
        Event.OSC => |e| {
            allocator.free(e.path);
            allocator.free(e.from_host);
            allocator.free(e.from_port);
            allocator.free(e.msg);
        },
        Event.Exec_Code_Line => |e| {
            allocator.free(e.line);
        },
        Event.MIDI => |e| {
            allocator.free(e.words);
        },
        else => {},
    }
    allocator.destroy(event);
}

pub fn post(event: *Data) !void {
    queue.lock.lock();
    try add_to_tail(event);
    queue.cond.signal();
    queue.lock.unlock();
}

pub fn handle_pending() !void {
    var event: ?*Data = null;
    var done = false;
    while (!done) {
        queue.lock.lock();
        if (queue.size > 0) {
            event = remove_from_head();
        } else {
            done = true;
        }
        queue.lock.unlock();
        if (event != null) try handle(event.?);
        event = null;
    }
}

pub fn free_pending() void {
    var event: ?*Data = null;
    var done = false;
    while (!done) {
        if (queue.size > 0) {
            event = remove_from_head();
        } else {
            done = true;
        }
        if (event) |ev| free(ev);
        event = null;
    }
}

fn add_to_tail(event: *Data) !void {
    var new_node = try allocator.create(Event_Node);
    new_node.* = Event_Node{ .ev = event, .next = null, .prev = null };
    var node = queue.head;
    while (node != null and node.?.next != null) {
        node = node.?.next;
    }
    if (node == null) {
        std.debug.assert(queue.size == 0);
        queue.head = new_node;
    } else {
        node.?.next = new_node;
        new_node.prev = node.?;
    }
    queue.tail = new_node;
    queue.size += 1;
}

fn remove_from_head() ?*Data {
    if (queue.head == null) return null;
    var node = queue.head.?;
    queue.head = node.next;
    defer allocator.destroy(node);
    const ev = node.ev;
    queue.size -= 1;
    return ev;
}

test "push and pop" {
    try init(std.testing.allocator);
    var i: u16 = 0;
    while (i < 100) : (i += 1) {
        var event = try new(Event.Monome_Remove);
        event.Monome_Remove.id = i;
        try add_to_tail(event);
    }
    i = 0;
    var node = queue.head;
    while (node != null) : (node = node.?.next) {
        try std.testing.expect(node.?.ev.Monome_Remove.id == i);
        i += 1;
    }
    i = 0;
    while (i < 100) : (i += 1) {
        var event = remove_from_head();
        free(event.?);
    }
}

fn handle(event: *Data) !void {
    switch (event.*) {
        Event.Quit => {
            quit = true;
        },
        Event.Exec_Code_Line => {
            try spindle.exec_code_line(event.Exec_Code_Line.line);
        },
        Event.OSC => {
            try spindle.osc_event(event.OSC.from_host, event.OSC.from_port, event.OSC.path, event.OSC.msg);
        },
        Event.Reset_LVM => {
            try spindle.reset_lua();
        },
        Event.Monome_Add => {
            try spindle.monome_add(event.Monome_Add.dev);
        },
        Event.Monome_Remove => {
            try spindle.monome_remove(event.Monome_Remove.id);
        },
        Event.Grid_Key => {
            try spindle.grid_key(event.Grid_Key.id, event.Grid_Key.x, event.Grid_Key.y, event.Grid_Key.state);
        },
        Event.Grid_Tilt => {
            try spindle.grid_tilt(event.Grid_Tilt.id, event.Grid_Tilt.sensor, event.Grid_Tilt.x, event.Grid_Tilt.y, event.Grid_Tilt.z);
        },
        Event.Arc_Encoder => {
            try spindle.arc_delta(event.Arc_Encoder.id, event.Arc_Encoder.ring, event.Arc_Encoder.delta);
        },
        Event.Arc_Key => {
            try spindle.arc_key(event.Arc_Key.id, event.Arc_Key.ring, event.Arc_Key.state);
        },
        Event.Screen_Key => {
            try spindle.screen_key(event.Screen_Key.scancode);
        },
        Event.Screen_Check => {
            try screen.check();
        },
        Event.Metro => {
            try spindle.metro_event(event.Metro.id, event.Metro.stage);
        },
        Event.MIDI => {},
    }
    free(event);
}