/// adapted from libxev's queue_mpsc.zig: https://github.com/mitchellh/libxev
const std = @import("std");
const atomic = std.atomic;

/// single consumer, multi-producer, bring your own elements,
/// elements must have a field `next` of type `?*T`.
/// ironically, the `next` field works backwards to how I expected:
/// as you can see in `push()`, we add to the head and consume from the tail,
/// and the `next` field of the old head becomes the new one.
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        head: *T,
        tail: *T,
        stub: T,

        // requires a stable pointer: checking whether an element is the pointer to `stub`
        // is how we see whether the queue is empty
        pub fn init(self: *Self) void {
            self.head = &self.stub;
            self.tail = &self.stub;
            self.stub.next = null;
        }

        /// pushes an item onto the queue.
        /// called by producers
        pub fn push(self: *Self, node: *T) void {
            self.pushList(node, node);
        }

        /// pushes a linked list of items onto the queue
        /// called by producers
        pub fn pushList(self: *Self, first: *T, last: *T) void {
            @atomicStore(?*T, &last.next, null, .unordered);
            const prev = @atomicRmw(*T, &self.head, .Xchg, last, .acq_rel);
            @atomicStore(?*T, &prev.next, first, .release);
        }

        /// pushes a slice of items onto the queue by first linking them together in order
        /// called by producers
        pub fn pushSlice(self: *Self, slice: []T) void {
            if (slice.len == 0) return;
            const first = &slice[0];
            const last = &slice[slice.len - 1];
            for (0..slice.len - 1) |i| {
                @atomicStore(?*T, &slice[i].next, &slice[i + 1], .unordered);
            }
            self.pushList(first, last);
        }

        /// returns true if the queue is empty
        /// called only by the consumer
        pub fn isEmpty(self: *Self) bool {
            const tail = @atomicLoad(*T, &self.tail, .unordered);
            const next = @atomicLoad(?*T, &tail.next, .acquire);
            const head = @atomicLoad(*T, &self.head, .acquire);

            return tail == &self.stub and next == null and tail == head;
        }

        /// polls the queue for an item and returns one if it's available.
        /// returns `error.Retry` if the queue is not ready to be pulled from
        /// (because a producer is currently interacting with it)
        /// and `null` if the queue is empty
        pub fn poll(self: *Self) error{Retry}!?*T {
            // grab the tail and its next element
            var tail = @atomicLoad(*T, &self.tail, .unordered);
            var maybe_next = @atomicLoad(?*T, &tail.next, .acquire);

            // ok first of all, is the tail a stub?
            if (tail == &self.stub) {
                // if yes, but the thing following it is not
                if (maybe_next) |next| {
                    // let's make that the tail
                    @atomicStore(*T, &self.tail, next, .unordered);
                    tail = next;
                    // and grab _its_ next element
                    maybe_next = @atomicLoad(?*T, &tail.next, .acquire);
                } else {
                    const head = @atomicLoad(*T, &self.head, .acquire);
                    // are we empty?
                    if (tail == head) return null;
                    // ah, we're in a retry state
                    return error.Retry;
                }
            }

            // ok now, let's look at the next element
            if (maybe_next) |next| {
                // let's make it the new tail
                @atomicStore(*T, &self.tail, next, .unordered);
                // and return the previous tail
                return tail;
            }

            // so the next item was null
            const head = @atomicLoad(*T, &self.head, .acquire);
            // are we in a weird state?
            // this should happen when a producer is currently assigning to tail.next
            if (head != tail) return error.Retry;

            // hmmm, so head is tail and next was null
            // let's push a stub and see what happens after that
            self.push(&self.stub);

            maybe_next = @atomicLoad(?*T, &tail.next, .acquire);
            if (maybe_next) |next| {
                // aha, we got something!
                @atomicStore(*T, &self.tail, next, .unordered);
                return tail;
            }

            // nope, still weird state
            return error.Retry;
        }

        /// pops an item from the queue if there is one, busy-waiting if `poll` gives a retry error
        pub fn pop(self: *Self) ?*T {
            while (true) {
                return self.poll() catch continue;
            }
        }

        /// gets the tail if the queue is nonempty, dropping past stubs
        pub fn getTail(self: *Self) ?*T {
            const tail = @atomicLoad(*T, &self.tail, .unordered);
            const maybe_next = @atomicLoad(?*T, &tail.next, .acquire);

            if (tail == &self.stub) {
                const next = maybe_next orelse return null;
                @atomicStore(*T, &self.tail, next, .unordered);
            }
            return tail;
        }

        /// gets the next element in the queue, dropping past stubs
        pub fn getNext(self: *Self, prev: *T) ?*T {
            var maybe_next = @atomicLoad(?*T, &prev.next, .acquire);
            if (maybe_next) |next| {
                if (next == &self.stub) maybe_next = @atomicLoad(?*T, &next.next, .acquire);
            }
            return maybe_next;
        }
    };
}

test "pushSlice" {
    const T = struct {
        val: u8,
        next: ?*@This() = null,
    };
    const Q = Queue(T);

    const producer = struct {
        fn go(allocator: std.mem.Allocator, queue: *Q, cond: *std.Thread.Condition, mtx: *std.Thread.Mutex) !void {
            const slice = try allocator.alloc(T, 256);
            defer allocator.free(slice);
            for (0..256) |i| {
                slice[i] = .{ .val = @intCast(i) };
            }
            queue.pushSlice(slice);
            mtx.lock();
            defer mtx.unlock();
            cond.wait(mtx);
        }
    };

    var mtx: std.Thread.Mutex = .{};
    var cond: std.Thread.Condition = .{};
    const allocator = std.testing.allocator;

    var queue: Q = undefined;
    queue.init();
    try std.testing.expect(queue.isEmpty());
    const pid = try std.Thread.spawn(.{}, producer.go, .{ allocator, &queue, &cond, &mtx });
    defer pid.join();
    for (0..256) |val| {
        const node = while (true)
            break queue.pop() orelse continue;
        try std.testing.expectEqual(@as(u8, @intCast(val)), node.val);
    }
    try std.testing.expect(queue.isEmpty());
    cond.signal();
}
