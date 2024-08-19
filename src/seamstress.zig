// zig files double as namespaces / struct types
const Seamstress = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
lua: *Lua,
buffered_writer: *BufferedWriter,

/// creates lua environment and event loop
pub fn init(alloc_ptr: *const std.mem.Allocator, buffered_writer: *BufferedWriter) !Seamstress {
    var seamstress: Seamstress = .{
        .loop = undefined,
        .pool = xev.ThreadPool.init(.{ .max_threads = 16 }),
        .lua = try Lua.init(alloc_ptr),
        .buffered_writer = buffered_writer,
    };
    seamstress.loop = try xev.Loop.init(.{ .thread_pool = &seamstress.pool });
    return seamstress;
}

pub fn run(self: *Seamstress, filename: ?[:0]const u8) !void {
    // we want a zig stack trace
    _ = self.lua.atPanic(ziglua.wrap(struct {
        fn panic(l: *Lua) i32 {
            const error_msg = l.toStringEx(-1);
            l.pop(1);
            // add a lua stack trace
            l.traceback(l, error_msg, 1);
            const with_stack_trace = l.toString(-1) catch unreachable;
            l.pop(1);
            // and panic!
            @call(.always_inline, std.debug.panic, .{ "lua crashed: {s}", .{with_stack_trace} });
            return 0;
        }
    }.panic));
    // prepare the lua environment
    try self.setup(filename);
    defer {
        // prints to the terminal
        sayGoodbye();
        switch (builtin.mode) {
            .Debug, .ReleaseSafe => {
                self.loop.deinit();
                self.lua.close();
            },
            .ReleaseFast, .ReleaseSmall => std.process.cleanExit(),
        }
    }
    try self.loop.run(.until_done);
}

// pub because it is referenced in main
pub fn panicCleanup(self: *Seamstress) void {
    @setCold(true);
    defer self.buffered_writer.flush() catch {};
}

/// single source of truth about seamstress version
pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha",
    .build = "240809",
};

fn setup(self: *Seamstress, _: ?[:0]const u8) !void {
    // open standard lua libraries
    self.lua.openLibs();
    // add our package searcher
    try addPackageSearcher(self.lua);
    // populates "seamstress" as a lua global and leaves it on the stack
    self.lua.requireF("seamstress", ziglua.wrap(register), true);
    self.lua.pop(1); // pop seamstress from the stack
    // self.doFile("core/seamstress.lua") catch {
    // const msg = self.lua.toString(-1) catch unreachable;
    // std.debug.panic("{s}", .{msg});
    // };
}

/// pub so that modules.zig can access it
pub fn register(l: *Lua) i32 {
    l.newTable();
    return 1;
}

/// adds a "package searcher" to the Lua environment that handles calls to requiring seamstress modules
fn addPackageSearcher(lua: *Lua) !void {
    _ = try lua.getGlobal("package");
    _ = lua.getField(-1, "searchers");
    lua.pushFunction(ziglua.wrap(struct {
        fn searcher(l: *Lua) i32 {
            const name = l.checkString(1);
            if (modules.list.get(name)) |func| {
                l.pushFunction(func);
                return 1;
            }
            return 0;
        }
    }.searcher));
    lua.rawSetIndex(-2, @intCast(lua.rawLen(-2) + 1)); // add our searcher to the end
    lua.pop(2); // pop `package` and `package.searchers`
}

/// prints "goodbye" to stdout unless called from a test
fn sayGoodbye() void {
    if (builtin.is_test) return;
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();
    stdout.print("goodbye\n", .{}) catch return;
    bw.flush() catch return;
}

const builtin = @import("builtin");
const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);
const xev = @import("xev");
const modules = @import("modules.zig");

test "lifecycle" {
    var seamstress = try Seamstress.init(&std.testing.allocator, undefined, undefined);
    try seamstress.run(null);
}
