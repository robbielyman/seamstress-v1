pub fn configure(seamstress: *Seamstress) void {
    const l = seamstress.vm.l;
    defer if (interpolated) |str| seamstress.allocator.free(str);
    l.load(ziglua.wrap(loader), seamstress, "=configure", .text) catch {
        const err = l.toStringEx(-1);
        panic("{s}", .{err});
    };
    l.call(0, 1);
    l.call(0, 0);
    const tui = lu.getConfig(l, "tui", bool);
    seamstress.modules.appendSlice(seamstress.allocator, &.{
        @import("osc.zig").module(),
        if (tui) @import("tui.zig").module() else @import("cli.zig").module(),
    }) catch panic("out of memory!", .{});
}

const std = @import("std");
const Seamstress = @import("seamstress.zig");
const panic = std.debug.panic;
const lu = @import("lua_util.zig");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

fn loader(_: *Lua, ctx: *anyopaque) ?[]const u8 {
    if (done) return null;
    const seamstress: *Seamstress = @ptrCast(@alignCast(ctx));
    done = true;
    const home = std.process.getEnvVarOwned(seamstress.allocator, "SEAMSTRESS_HOME") catch blk: {
        break :blk std.process.getEnvVarOwned(seamstress.allocator, "HOME") catch |err| panic("error getting $HOME: {s}", .{@errorName(err)});
    };
    defer seamstress.allocator.free(home);
    interpolated = std.fmt.allocPrint(seamstress.allocator, comptime script, .{home}) catch panic("out of memory!", .{});
    return interpolated;
}

var interpolated: ?[]const u8 = null;

var done = false;
const script =
    \\return function()
    \\  local not_new = {{}}
    \\  for key, _ in pairs(_G) do
    \\    table.insert(not_new, key)
    \\  end
    \\  local ok, err = pcall(dofile, '{s}/seamstress/config.lua')
    \\  if not ok then error(err) end
    \\  for key, value in pairs(_G) do
    \\    local found = false
    \\    for _, other in ipairs(not_new) do
    \\      if key == other then
    \\        found = true
    \\        break
    \\      end
    \\    end
    \\    if found == false then
    \\      _seamstress.config[key] = value
    \\      _G[key] = nil
    \\    end
    \\  end
    \\end
;
