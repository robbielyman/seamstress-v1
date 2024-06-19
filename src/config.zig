/// loads the seamstress config.lua file, placing its contents under seamstress.config
pub fn configure(seamstress: *Seamstress) void {
    const l = seamstress.l;
    defer if (interpolated) |str| seamstress.allocator.free(str);
    l.load(ziglua.wrap(loader), seamstress, "=configure", .text) catch {
        const err = l.toStringEx(-1);
        panic("{s}", .{err});
    };
    l.call(0, 1);
    l.call(0, 0);
    done = false;
}

fn loader(_: *Lua, ctx: *anyopaque) ?[]const u8 {
    if (done) return null;
    const seamstress: *Seamstress = @ptrCast(@alignCast(ctx));
    done = true;

    const home = std.process.getEnvVarOwned(seamstress.allocator, "SEAMSTRESS_HOME") catch blk: {
        const home = std.process.getEnvVarOwned(seamstress.allocator, "HOME") catch |err| panic("error getting $HOME: {s}", .{@errorName(err)});
        defer seamstress.allocator.free(home);
        break :blk std.fs.path.join(seamstress.allocator, &.{ home, "seamstress" }) catch panic("out of memory!", .{});
    };
    defer seamstress.allocator.free(home);
    const filename: ?[]u8 = std.process.getEnvVarOwned(seamstress.allocator, "SEAMSTRESS_CONFIG_FILENAME") catch null;
    defer if (filename) |f| seamstress.allocator.free(f);
    const cfg = std.fs.path.join(seamstress.allocator, &.{ home, filename orelse "config.lua" }) catch panic("out of memory!", .{});
    defer seamstress.allocator.free(cfg);
    interpolated = std.fmt.allocPrint(seamstress.allocator, script, .{cfg}) catch panic("out of memory!", .{});
    return interpolated;
}

var interpolated: ?[]const u8 = null;
var done = false;

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const panic = std.debug.panic;
const lu = @import("lua_util.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

const script =
    \\return function()
    \\  local not_new = {{}}
    \\  for key, _ in pairs(_G) do
    \\    table.insert(not_new, key)
    \\  end
    \\  local ok, err = pcall(dofile, '{s}')
    \\  if not ok then
    \\    if err:find("No such file or directory") then return end
    \\    error(err)
    \\  end
    \\  for key, value in pairs(_G) do
    \\    local found = false
    \\    for _, other in ipairs(not_new) do
    \\      if key == other then
    \\        found = true
    \\        break
    \\      end
    \\    end
    \\    if found == false then
    \\      seamstress.config[key] = value
    \\      _G[key] = nil
    \\    end
    \\  end
    \\end
;
