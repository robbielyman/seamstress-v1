// zig files double as namespaces / struct types
const Seamstress = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
lua: *Lua,
lua_files_path: []const u8,
buffered_writer: *BufferedWriter,

/// creates lua environment and event loop
pub fn init(alloc_ptr: *const std.mem.Allocator, buffered_writer: *BufferedWriter, lua_files_path: []const u8) !Seamstress {
    var seamstress: Seamstress = .{
        .loop = undefined,
        .pool = xev.ThreadPool.init(.{ .max_threads = 16 }),
        .lua = try Lua.init(alloc_ptr),
        .lua_files_path = lua_files_path,
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

fn setup(self: *Seamstress, filename: ?[:0]const u8) !void {
    const allocator = self.lua.allocator();
    // set luarocks environment variables
    try setEnv(allocator);
    // open standard lua libraries
    self.lua.openLibs();
    // add our package searcher
    try addPackageSearcher(self.lua);
    self.addMetatable(filename);
    // populates "seamstress" as a lua global and leaves it on the stack
    self.lua.requireF("seamstress", ziglua.wrap(register), true);
    self.lua.pop(1); // pop seamstress from the stack
    self.doFile("core/seamstress.lua") catch {
        const msg = self.lua.toString(-1) catch unreachable;
        std.debug.panic("{s}", .{msg});
    };
}

/// pub so that modules.zig can access it
pub fn register(_: *Lua) i32 {}

/// I expect that Lua will need libc to access environment variables
extern "c" fn setenv([*:0]const u8, [*:0]const u8, c_int) c_int;

/// uses `luarocks path` to set environment variables so seamstress can find luarocks
fn setEnv(allocator: std.mem.Allocator) !void {
    const child = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "luarocks", "path" },
    }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    // free accumulated output
    defer allocator.free(child.stderr);
    defer allocator.free(child.stdout);
    const cmd = child.stdout;
    // the output is three lines, each of which is an environment variable invocation, i.e.
    // export VARIABLE="value"
    // we want to call setenv on it, for which we need to extract just VARIABLE and value (without quotes)
    var iterator = std.mem.tokenizeScalar(u8, cmd, '\n');
    while (iterator.next()) |line| {
        var buf: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const ally = fba.allocator();
        const command = std.mem.trimLeft(u8, line, "export ");
        const equals = std.mem.indexOfScalar(u8, command, '=') orelse continue;
        const env_var = try ally.dupeZ(u8, command[0..equals]);
        const env_val = try ally.dupeZ(u8, command[equals + 2 .. command.len - 1]);
        if (setenv(env_var.ptr, env_val.ptr, 1) == -1) return switch (std.posix.errno(-1)) {
            .INVAL => error.NameInvalid,
            .NOMEM => error.OutOfMemory,
            else => error.Unexpected,
        };
    }
}

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
