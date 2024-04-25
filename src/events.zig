const Events = @This();
const logger = std.log.scoped(.events);

queue: Queue(Node) = undefined,
// we set this ourselves
quit: bool = false,
// nodes for quitting
quit_node: Node = .{
    .handler = handlerFromClosure(Events, quitImpl, "quit_node"),
},
// and panicking
panic_node: Node = .{
    .handler = handlerFromClosure(Events, panicImpl, "panic_node"),
},
// set when panicking
err: ?Error = null,

pub const Node = struct {
    next: ?*@This() = null,
    handler: *const fn (*@This(), l: *Lua) void,

    fn handle(self: *Node, l: *Lua) void {
        self.handler(self, l);
    }
};

// posts an event to the queue
pub fn submit(self: *Events, node: *Node) void {
    self.queue.push(node);
}

// frees memory in the queue
pub fn close(self: *Events) void {
    // necessary so the event loop exits
    self.quit = true;
}

// initializes the event queue
// since we require a stable pointer, make this a self-init function
pub fn init(self: *Events) void {
    self.* = .{};
    self.queue.init();
}

// the main event loop; the main thread blocks here until exiting
pub fn loop(self: *Events) void {
    const vm: *Spindle = @fieldParentPtr("events", self);
    const l = vm.lvm;
    while (!self.quit) {
        // we try to handle all available events at once
        while (self.queue.pop()) |node| {
            node.handle(l);
            if (self.quit) break;
        } else {
            // back off for a bit
            std.time.sleep(std.time.ns_per_us * 50);
        }
    }
}

// drains the event queue
pub fn processAll(self: *Events) void {
    const vm: *Spindle = @fieldParentPtr("events", self);
    const l = vm.lvm;
    while (self.queue.pop()) |node| {
        node.handle(l);
    }
}

// used by our quit node to quit
fn quitImpl(self: *Events, _: *Lua) void {
    const spindle: *Spindle = @fieldParentPtr("events", self);
    const seamstress: *Seamstress = @fieldParentPtr("vm", spindle);
    seamstress.deinit();
    self.quit = true;
}

// used by our panic node to panic
fn panicImpl(self: *Events, _: *Lua) void {
    const spindle: *Spindle = @fieldParentPtr("events", self);
    const seamstress: *Seamstress = @fieldParentPtr("vm", spindle);
    seamstress.panic(self.err.?);
    self.quit = true;
}

/// helper function for constructing a node handler from a closure
/// `Parent` has a field named `node_field_name` of type `Node`
pub fn handlerFromClosure(
    comptime Parent: type,
    comptime closure: fn (*Parent, *Lua) void,
    comptime node_field_name: []const u8,
) fn (*Node, *Lua) void {
    const inner = struct {
        fn handler(node: *Node, l: *Lua) void {
            const parent: *Parent = @fieldParentPtr(node_field_name, node);
            @call(.always_inline, closure, .{ parent, l });
        }
    };
    return inner.handler;
}

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const Spindle = @import("spindle.zig");
const Error = Seamstress.Error;
const Lua = @import("ziglua").Lua;

const Queue = @import("queue.zig").Queue;
