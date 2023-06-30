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
        dev_type: midi.Dev_t,
    },
    MIDI: struct {
        id: u32,
        timestamp: f64,
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

const Queue = struct {
    const Node = struct {
        // node
        next: ?*Node,
        prev: ?*Node,
        ev: *Data,
    };
    read_head: ?*Node,
    read_tail: ?*Node,
    read_size: usize,
    write_head: ?*Node,
    write_tail: ?*Node,
    write_size: usize,
    lock: std.Thread.Mutex,
    cond: std.Thread.Condition,
    inline fn get_new(self: *Queue) *Node {
        var node = self.write_head orelse {
            @panic("no nodes free!");
        };
        self.write_head = node.next;
        node.next = null;
        node.prev = null;
        if (self.write_size == 1) self.write_tail = null;
        self.write_size -= 1;
        return node;
    }
    inline fn return_to_pool(self: *Queue, node: *Node) void {
        if (self.write_tail) |n| {
            self.write_tail = node;
            n.next = node;
            node.prev = n;
        } else {
            std.debug.assert(self.write_size == 0);
            self.write_head = node;
            self.write_tail = node;
        }
        self.write_size += 1;
    }
    fn push(self: *Queue, data: Data) void {
        var new_node = self.get_new();
        new_node.ev.* = data;
        if (self.read_tail) |n| {
            self.read_tail = new_node;
            n.next = new_node;
            new_node.prev = n;
        } else {
            std.debug.assert(self.read_size == 0);
            self.read_tail = new_node;
            self.read_head = new_node;
        }
        self.read_size += 1;
    }
    fn pop(self: *Queue) ?*Data {
        if (self.read_head) |n| {
            const ev = n.ev;
            self.read_head = n.next;
            n.next = null;
            self.return_to_pool(n);
            if (self.read_size == 1) self.read_tail = null;
            self.read_size -= 1;
            return ev;
        } else {
            std.debug.assert(self.read_size == 0);
            return null;
        }
    }
    fn deinit(self: *Queue) void {
        var node = self.write_head;
        while (node) |n| {
            node = n.next;
            allocator.destroy(n.ev);
            allocator.destroy(n);
        }
    }
};

var queue: Queue = undefined;

var quit: bool = false;

pub fn init(alloc_ptr: std.mem.Allocator) !void {
    allocator = alloc_ptr;
    queue = Queue{
        // queue
        .read_head = null,
        .read_tail = null,
        .read_size = 0,
        .write_head = null,
        .write_tail = null,
        .write_size = 0,
        .cond = .{},
        .lock = .{},
    };
    var i: u16 = 0;
    while (i < 5000) : (i += 1) {
        var node = try allocator.create(Queue.Node);
        var data = try allocator.create(Data);
        data.* = undefined;
        node.* = Queue.Node{ .ev = data, .next = null, .prev = null };
        queue.return_to_pool(node);
    }
}

pub fn loop() !void {
    while (!quit) {
        queue.lock.lock();
        while (queue.read_size == 0) {
            if (quit) break;
            queue.cond.wait(&queue.lock);
            continue;
        }
        const ev = queue.pop();
        queue.lock.unlock();
        if (ev != null) try handle(ev.?);
    }
}

pub fn free(event: *Data) void {
    switch (event.*) {
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
    queue.lock.lock();
    queue.push(event);
    queue.cond.signal();
    queue.lock.unlock();
}

pub fn handle_pending() !void {
    var event: ?*Data = null;
    var done = false;
    while (!done) {
        queue.lock.lock();
        if (queue.read_size > 0) {
            event = queue.pop();
        } else {
            done = true;
        }
        queue.lock.unlock();
        if (event != null) try handle(event.?);
        event = null;
    }
}

pub fn deinit() void {
    free_pending();
    queue.deinit();
}

fn free_pending() void {
    var event: ?*Data = null;
    var done = false;
    while (!done) {
        if (queue.read_size > 0) {
            event = queue.pop();
        } else {
            done = true;
        }
        if (event) |ev| free(ev);
        event = null;
    }
}

fn handle(event: *Data) !void {
    switch (event.*) {
        .Quit => quit = true,
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
        .Screen_Check => {
            screen.check();
            screen.pending -= 1;
        },
        .Screen_Resized => |e| try spindle.screen_resized(e.w, e.h, e.window),
        .Metro => |e| {
            try spindle.metro_event(e.id, e.stage);
            metros.set_hot(e.id);
        },
        .MIDI_Add => |e| try spindle.midi_add(e.dev),
        .MIDI_Remove => |e| try spindle.midi_remove(e.dev_type, e.id),
        .MIDI => |e| try spindle.midi_event(e.id, e.timestamp, e.message),
        .Clock_Resume => |e| try spindle.resume_clock(e.id),
        .Clock_Transport => |e| try spindle.clock_transport(e.transport),
    }
    free(event);
}
