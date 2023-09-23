const c = @cImport(@cInclude("pthread.h"));
const builtin = @import("builtin");

pub fn set_priority(priority: u8) void {
    const priority_struct: c.sched_param = switch (comptime builtin.os.tag) {
        .linux => .{
            .sched_priority = priority,
        },
        .macos => .{
            .sched_priority = priority,
            .__opaque = undefined,
        },
        else => return,
    };
    _ = c.pthread_setschedparam(c.pthread_self(), c.SCHED_FIFO, &priority_struct);
}
