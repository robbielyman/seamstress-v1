// zig files double as namespaces / struct types
const Seamstress = @This();

loop: xev.Loop,
pool: xev.ThreadPool,
lua: *Lua,
cli: Cli,

/// creates lua environment and event loop
pub fn init(self: *Seamstress, alloc_ptr: *const std.mem.Allocator) !void {
    self.* = .{
        .loop = undefined,
        .pool = xev.ThreadPool.init(.{ .max_threads = 16 }),
        .lua = try Lua.init(alloc_ptr),
        .cli = try Cli.init(alloc_ptr.*),
    };
    self.loop = try xev.Loop.init(.{ .thread_pool = &self.pool });
}

pub fn run(self: *Seamstress) !void {
    // we want a zig stack trace
    _ = self.lua.atPanic(ziglua.wrap(struct {
        fn panic(l: *Lua) i32 { // function panic(error_msg)
            const error_msg = l.toStringEx(-1);
            l.pop(1);
            // add a lua stack trace
            l.traceback(l, error_msg, 1); // local with_stack_trace = debug.traceback(error_msg, 1)
            const with_stack_trace = l.toString(-1) catch unreachable;
            l.pop(1);
            // and panic!
            @call(.always_inline, std.debug.panic, .{ "lua crashed: {s}", .{with_stack_trace} });
            return 0; // never reached, since std.debug.panic has return type noreturn
        }
    }.panic));
    // prepare the lua environment
    try self.setup();
    var c: xev.Completion = .{};
    self.loop.timer(&c, 0, self, struct {
        fn f(ud: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, r: xev.Result) xev.CallbackAction {
            const s: *Seamstress = @ptrCast(@alignCast(ud.?));
            blk: {
                const args = std.process.argsAlloc(s.lua.allocator()) catch break :blk;
                defer std.process.argsFree(s.lua.allocator(), args);
                if (args.len < 2) break :blk;
                if (std.mem.eql(u8, "test", args[1])) break :blk;
                if (builtin.is_test) break :blk;
                s.lua.doFile(args[1]) catch {
                    lu.reportError(s.lua);
                };
            }
            lu.preparePublish(s.lua, &.{"init"});
            lu.doCall(s.lua, 1, 0) catch {
                lu.reportError(s.lua);
                return .disarm;
            };
            _ = r.timer catch return .disarm;
            return .disarm;
        }
    }.f);
    try self.loop.run(.until_done);
}

/// closes the event loop, lua instance, frees memory
pub fn deinit(self: *Seamstress) void {
    self.loop.deinit();
    self.lua.close();
    self.cli.deinit();
    self.* = undefined;
}

// pub because it is referenced in main
pub fn panicCleanup(s: *Seamstress) void {
    @setCold(true);
    _ = s.lua.getMetatableRegistry("seamstress");
    _ = s.lua.getField(-1, "__panic");
    lu.doCall(s.lua, 0, 0) catch {
        // write to stderr because there's no guarantee the logs will be flushed
        std.debug.print("{s}\n", .{s.lua.toString(-1) catch unreachable});
    };
}

/// single source of truth about seamstress version
pub const version: std.SemanticVersion = .{
    .major = 2,
    .minor = 0,
    .patch = 0,
    .pre = "prealpha",
    .build = "241005",
};

fn setup(self: *Seamstress) !void {
    const allocator = self.lua.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const is_test = is_test: {
        if (args.len < 2) break :is_test false;
        break :is_test std.mem.eql(u8, args[1], "test");
    };
    // open standard lua libraries
    self.lua.openLibs();
    // load the config file---unless we're running tests
    // the config file leaves a table on the stack
    if (!is_test and !builtin.is_test) try self.configure();
    // create the seamstress metatable
    try self.createMetatable();
    // add our package searcher
    try addPackageSearcher(self.lua);
    // populates "seamstress" as a lua global and leaves it on the stack
    self.lua.requireF("seamstress", ziglua.wrap(register), true);
    if (!builtin.is_test) if (is_test) {
        // adds an `init` handler that runs the seamstress tests
        lu.load(self.lua, "seamstress.test");
    } else {
        self.lua.rotate(-2, 1);
        // seamstress.config = the table returned by config
        self.lua.setField(-2, "config");
    };
    self.lua.pop(1); // pop seamstress from the stack
    // set up CLI interaction
    try self.cli.setup();
    self.lua.pushFunction(ziglua.wrap(clearRegistry));
    lu.addExitHandler(self.lua, .quit);
}

/// attempts to call `dofile` on $SEAMSTRESS_HOME/$SEAMSTRESS_CONFIG_FILENAME
/// and then scrapes any new globals added into a table, which is left on the stack
fn configure(seamstress: *Seamstress) !void {
    const script =
        \\return function()
        \\  local not_new = {}
        \\  for key, _ in pairs(_G) do
        \\    table.insert(not_new, key)
        \\  end
        \\  local config_file = os.getenv("SEAMSTRESS_HOME") ..
        \\    package.config:sub(1, 1) ..
        \\    os.getenv("SEAMSTRESS_CONFIG_FILENAME")
        \\  local ok, err = pcall(dofile, config_file)
        \\  if not ok then
        \\    if err:find("No such file or directory") then return {} end
        \\    error(err)
        \\  end
        \\  local ret = {}
        \\  for key, value in pairs(_G) do
        \\    local found = false
        \\    for _, other in ipairs(not_new) do
        \\      if key == other then
        \\        found = true
        \\        break
        \\      end
        \\    end
        \\    if found == false then
        \\      ret[key] = value
        \\      _G[key] = nil
        \\    end
        \\  end
        \\  return ret
        \\end
    ;
    try seamstress.lua.loadString(script);
    try lu.doCall(seamstress.lua, 0, 1);
    try lu.doCall(seamstress.lua, 0, 1);
}

fn createMetatable(seamstress: *Seamstress) !void {
    try seamstress.lua.newMetatable("seamstress"); // local mt = {}
    seamstress.lua.pushLightUserdata(seamstress); // ptr
    seamstress.lua.setField(-2, "__seamstress"); // mt.__seamstress = ptr
    const inner = struct {
        const Which = enum { panic, quit };

        fn postEventAndCallAllFunctionsInTable(comptime which: Which) fn (*Lua) i32 {
            return struct {
                fn f(l: *Lua) i32 {
                    lu.preparePublish(l, &.{switch (which) {
                        .panic => "panic",
                        .quit => "quit",
                    }});
                    lu.doCall(l, 1, 0) catch {
                        std.log.scoped(.seamstress).err("error in event handler: {s}", .{l.toString(-1) catch unreachable});
                        l.pop(1);
                    };
                    const i = Lua.upvalueIndex(1);
                    l.pushNil();
                    while (l.next(i)) {
                        if (lu.isCallable(l, -1)) {
                            lu.doCall(l, 0, 0) catch {
                                std.log.scoped(.seamstress).err("error in exit handler: {s}", .{l.toString(-1) catch unreachable});
                                l.pop(1);
                            };
                        } else {
                            l.pushValue(-2);
                            const key = l.toStringEx(-1);
                            const value = l.toStringEx(-2);
                            std.log.scoped(.seamstress).err("exit handler at key {s} is not callable; value: {s}", .{ key, value });
                            l.pop(2);
                        }
                    }
                    return 0;
                }
            }.f;
        }
    };

    seamstress.lua.newTable(); // {}
    seamstress.lua.pushClosure(ziglua.wrap(inner.postEventAndCallAllFunctionsInTable(.quit)), 1); // f (closes over {})
    seamstress.lua.setField(-2, "__quit"); // mt.__quit = f

    seamstress.lua.newTable(); // {}
    seamstress.lua.pushClosure(ziglua.wrap(inner.postEventAndCallAllFunctionsInTable(.panic)), 1); // f (closes over {})
    seamstress.lua.setField(-2, "__panic"); // mt.__panic = f

    seamstress.lua.pop(1); // pop mt
}

/// pub so that modules.zig can access it
pub fn register(l: *Lua) i32 {
    l.newTable();
    // TODO: fill this out more
    lu.load(l, "seamstress.event");
    l.setField(-2, "event");
    lu.load(l, "seamstress.async");
    l.setField(-2, "async");
    lu.load(l, "seamstress.Timer");
    l.setField(-2, "Timer");
    l.pushFunction(ziglua.wrap(struct {
        fn f(lua: *Lua) i32 {
            lu.quit(lua);
            return 0;
        }
    }.f));
    l.setField(-2, "quit");
    return 1;
}

/// adds a "package searcher" to the Lua environment that handles calls to requiring seamstress modules
fn addPackageSearcher(lua: *Lua) !void {
    // package.searchers[#package.searchers + 1] = f
    _ = try lua.getGlobal("package");
    _ = lua.getField(-1, "searchers");
    lua.pushFunction(ziglua.wrap(struct {
        fn searcher(l: *Lua) i32 { // where this is f
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

/// creates a copy of the registry table and then, for each entry in the copy table,
/// checks to see if the entry has a __cancel metamethod and calls that metamethod if so
fn clearRegistry(l: *Lua) i32 {
    l.newTable();
    const tbl = l.getTop();
    l.pushNil();
    const key = l.getTop();
    var index: ziglua.Integer = 1;
    while (l.next(ziglua.registry_index)) {
        defer l.setTop(key);
        switch (l.typeOf(-1)) {
            .userdata, .table => {
                _ = l.getMetaField(-1, "__cancel") catch continue;
                l.pop(1);
                l.setIndex(tbl, index);
                index += 1;
            },
            else => {},
        }
    }
    const len = index;
    index = 1;
    // @breakpoint();
    while (index < len) : (index += 1) {
        _ = l.getIndex(tbl, index);
        _ = l.getMetaField(-1, "__cancel") catch {};
        l.rotate(-2, 1);
        l.call(1, 0);
    }
    return 0;
}

const builtin = @import("builtin");
const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);
const xev = @import("xev");
const modules = @import("modules.zig");
const Cli = @import("cli.zig");
const lu = @import("lua_util.zig");

test "ref" {
    _ = modules;
}

test "lifecycle" {
    var seamstress: Seamstress = undefined;
    try seamstress.init(&std.testing.allocator);
    defer seamstress.deinit();

    var c: xev.Completion = .{};
    var failed: bool = false;
    seamstress.loop.timer(&c, 1, &failed, struct {
        fn f(ud: ?*anyopaque, loop: *xev.Loop, _: *xev.Completion, r: xev.Result) xev.CallbackAction {
            _ = r.timer catch unreachable;
            const boolean: *bool = @ptrCast(@alignCast(ud.?));
            const l = lu.getLua(loop);
            for (modules.list.values()) |@"fn"| {
                l.pushFunction(@"fn");
                lu.doCall(l, 0, 0) catch {
                    l.pop(1);
                    boolean.* = true;
                };
            }
            return .disarm;
        }
    }.f);
    var d: xev.Completion = .{};
    seamstress.loop.timer(&d, 1000, seamstress.lua, struct {
        fn f(ud: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, r: xev.Result) xev.CallbackAction {
            _ = r.timer catch unreachable;
            const l: *Lua = @ptrCast(@alignCast(ud.?));
            lu.quit(l);
            return .disarm;
        }
    }.f);
    try seamstress.run();
    try std.testing.expect(failed == false);
}
