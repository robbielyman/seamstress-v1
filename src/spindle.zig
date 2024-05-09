/// zig->lua and lua->zig interface
// @author ryleelyman
// @module seamstress
const std = @import("std");
const args = @import("args.zig");
const osc = @import("serialosc.zig");
const events = @import("events.zig");
const monome = @import("monome.zig");
const midi = @import("midi.zig");
const clock = @import("clock.zig");
const screen = @import("screen.zig");
const metro = @import("metros.zig");
const ziglua = @import("ziglua");
const input = @import("input.zig");
const c = input.c;

const Lua = ziglua.Lua;
var lvm: *Lua = undefined;
const logger = std.log.scoped(.spindle);
var stdout = std.io.getStdOut().writer();
var timer: std.time.Timer = undefined;

pub fn init(prefix: []const u8, config: []const u8, time: std.time.Timer, version: std.SemanticVersion) !void {
    interpreter_alloc = fallback_allocator.get();
    save_buf = std.ArrayList(u8).init(interpreter_alloc);
    children = std.ArrayList(std.process.Child).init(interpreter_alloc);
    timer = time;
    logger.info("starting lua vm", .{});
    lvm = try Lua.init(&std.heap.raw_c_allocator);

    lvm.openLibs();

    lvm.newTable();

    register_seamstress("reset_lvm", ziglua.wrap(reset_lvm));

    register_seamstress("osc_send", ziglua.wrap(osc_send));
    register_seamstress("osc_register", ziglua.wrap(osc_register));
    register_seamstress("osc_delete", ziglua.wrap(osc_delete));

    register_seamstress("child_process", ziglua.wrap(child_process));

    register_seamstress("grid_set_led", ziglua.wrap(grid_set_led));
    register_seamstress("grid_all_led", ziglua.wrap(grid_all_led));
    register_seamstress("grid_rows", ziglua.wrap(grid_rows));
    register_seamstress("grid_cols", ziglua.wrap(grid_cols));
    register_seamstress("grid_set_rotation", ziglua.wrap(grid_set_rotation));
    register_seamstress("grid_tilt_enable", ziglua.wrap(grid_tilt_enable));
    register_seamstress("grid_tilt_disable", ziglua.wrap(grid_tilt_disable));

    register_seamstress("arc_set_led", ziglua.wrap(arc_set_led));
    register_seamstress("arc_all_led", ziglua.wrap(arc_all_led));

    register_seamstress("monome_refresh", ziglua.wrap(monome_refresh));
    register_seamstress("monome_intensity", ziglua.wrap(monome_intensity));

    register_seamstress("screen_refresh", ziglua.wrap(screen_refresh));
    register_seamstress("screen_pixel", ziglua.wrap(screen_pixel));
    register_seamstress("screen_pixel_rel", ziglua.wrap(screen_pixel_rel));
    register_seamstress("screen_line", ziglua.wrap(screen_line));
    register_seamstress("screen_line_rel", ziglua.wrap(screen_line_rel));
    register_seamstress("screen_curve", ziglua.wrap(screen_curve));
    register_seamstress("screen_rect", ziglua.wrap(screen_rect));
    register_seamstress("screen_rect_fill", ziglua.wrap(screen_rect_fill));
    register_seamstress("screen_text", ziglua.wrap(screen_text));
    register_seamstress("screen_text_center", ziglua.wrap(screen_text_center));
    register_seamstress("screen_text_right", ziglua.wrap(screen_text_right));
    register_seamstress("screen_color", ziglua.wrap(screen_color));
    register_seamstress("screen_clear", ziglua.wrap(screen_clear));
    register_seamstress("screen_set", ziglua.wrap(screen_set));
    register_seamstress("screen_show", ziglua.wrap(screen_show));
    register_seamstress("screen_arc", ziglua.wrap(screen_arc));
    register_seamstress("screen_circle", ziglua.wrap(screen_circle));
    register_seamstress("screen_circle_fill", ziglua.wrap(screen_circle_fill));
    register_seamstress("screen_triangle", ziglua.wrap(screen_triangle));
    register_seamstress("screen_quad", ziglua.wrap(screen_quad));
    register_seamstress("screen_geometry", ziglua.wrap(screen_geometry));
    register_seamstress("screen_new_texture", ziglua.wrap(screen_new_texture));
    register_seamstress("screen_new_texture_from_file", ziglua.wrap(screen_new_texture_from_file));
    register_seamstress("screen_texture_dimensions", ziglua.wrap(screen_texture_dimensions));
    register_seamstress("screen_render_texture", ziglua.wrap(screen_render_texture));
    register_seamstress("screen_render_texture_extended", ziglua.wrap(screen_render_texture_extended));
    register_seamstress("screen_move", ziglua.wrap(screen_move));
    register_seamstress("screen_move_rel", ziglua.wrap(screen_move_rel));
    register_seamstress("screen_get_text_size", ziglua.wrap(screen_get_text_size));
    register_seamstress("screen_set_size", ziglua.wrap(screen_set_size));
    register_seamstress("screen_set_fullscreen", ziglua.wrap(screen_set_fullscreen));
    register_seamstress("screen_set_position", ziglua.wrap(screen_set_position));

    register_seamstress("metro_start", ziglua.wrap(metro_start));
    register_seamstress("metro_stop", ziglua.wrap(metro_stop));
    register_seamstress("metro_set_time", ziglua.wrap(metro_set_time));

    register_seamstress("midi_write", ziglua.wrap(midi_write));

    register_seamstress("clock_get_tempo", ziglua.wrap(clock_get_tempo));
    register_seamstress("clock_get_beats", ziglua.wrap(clock_get_beats));
    register_seamstress("clock_set_source", ziglua.wrap(clock_set_source));
    register_seamstress("clock_link_set_tempo", ziglua.wrap(clock_link_set_tempo));
    register_seamstress("clock_link_start", ziglua.wrap(clock_link_start));
    register_seamstress("clock_link_stop", ziglua.wrap(clock_link_stop));
    register_seamstress("clock_link_set_quantum", ziglua.wrap(clock_link_set_quantum));
    register_seamstress("clock_internal_set_tempo", ziglua.wrap(clock_internal_set_tempo));
    register_seamstress("clock_internal_start", ziglua.wrap(clock_internal_start));
    register_seamstress("clock_internal_stop", ziglua.wrap(clock_internal_stop));
    register_seamstress("clock_schedule_sleep", ziglua.wrap(clock_schedule_sleep));
    register_seamstress("clock_schedule_sync", ziglua.wrap(clock_schedule_sync));
    register_seamstress("clock_cancel", ziglua.wrap(clock_cancel));
    register_seamstress("get_time", ziglua.wrap(get_time));

    register_seamstress("quit_lvm", ziglua.wrap(quit_lvm));

    register_seamstress("print", ziglua.wrap(lua_print));

    _ = lvm.pushString(args.local_port);
    lvm.setField(-2, "local_port");
    _ = lvm.pushString(args.remote_port);
    lvm.setField(-2, "remote_port");
    var buffer: [8 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var alloc = fba.allocator();
    {
        const prefixZ = try alloc.dupeZ(u8, prefix);
        defer alloc.free(prefixZ);
        _ = lvm.pushString(prefixZ);
        lvm.setField(-2, "prefix");
    }

    {
        lvm.createTable(3, 0);
        lvm.pushInteger(@intCast(version.major));
        lvm.setIndex(-2, 1);
        lvm.pushInteger(@intCast(version.minor));
        lvm.setIndex(-2, 2);
        lvm.pushInteger(@intCast(version.patch));
        lvm.setIndex(-2, 3);
        lvm.setField(-2, "version");
    }
    lvm.setGlobal("_seamstress");
    {
        const cwd = std.process.getCwdAlloc(alloc) catch @panic("OOM!");
        defer alloc.free(cwd);
        const lua_cwd = alloc.dupeZ(u8, cwd) catch @panic("OOM!");
        defer alloc.free(lua_cwd);
        _ = lvm.pushString(lua_cwd);
        lvm.setGlobal("_pwd");
    }
    const cmd = try std.fmt.allocPrint(alloc, "dofile(\"{s}\")\n", .{config});
    defer alloc.free(cmd);
    try run_code(cmd);
    try run_code("require('core/seamstress')");
}

fn register_seamstress(name: [:0]const u8, f: ziglua.CFn) void {
    lvm.pushFunction(f);
    lvm.setField(-2, name);
}

pub fn deinit() void {
    defer {
        logger.info("shutting down lua vm", .{});
        lvm.deinit();
        save_buf.deinit();
    }
    logger.info("calling cleanup", .{});
    _ = lvm.getGlobal("_seamstress") catch unreachable;
    _ = lvm.getField(-1, "cleanup");
    lvm.remove(-2);
    docall(lvm, 0, 0) catch unreachable;
    for (children.items) |*child| {
        _ = child.kill() catch unreachable;
    }
    children.deinit();
}

pub fn startup(script: []const u8, buffer: []u8) !?[:0]const u8 {
    var a = std.heap.stackFallback(1024, std.heap.raw_c_allocator);
    const allocator = a.get();
    const script_string = allocator.dupeZ(u8, script) catch @panic("OOM!");
    defer allocator.free(script_string);
    _ = lvm.pushString(script_string);
    _ = try lvm.getGlobal("_startup");
    lvm.insert(1);
    const base = lvm.getTop() - 1;
    lvm.pushFunction(ziglua.wrap(message_handler));
    lvm.insert(base);
    lvm.protectedCall(1, 1, base) catch |err| {
        lvm.remove(base);
        _ = lua_print(lvm);
        return err;
    };
    lvm.remove(base);
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const ret = lvm.toString(-1) catch null;
    if (ret) |r| return try fba.allocator().dupeZ(u8, r) else return null;
}

/// resets seamstress.
// @function reset_lvm
fn reset_lvm(l: *Lua) i32 {
    check_num_args(l, 0);
    const event = .{ .Reset = {} };
    events.post(event);
    return 0;
}

var children: std.ArrayList(std.process.Child) = undefined;

/// starts child process
// @param command a string for the command to start
// @param args an array of strings for the command line arguments
// @function child_process
fn child_process(l: *Lua) i32 {
    const num_args = l.getTop();
    if (num_args < 1) return 0;
    const command = l.checkString(1);
    if (num_args < 2) {
        var child = std.process.Child.init(&.{command}, std.heap.raw_c_allocator);
        child.spawn() catch |err| {
            l.raiseErrorStr("child_process %s failed with errror %s!", .{ command.ptr, @errorName(err).ptr });
        };
        children.append(child) catch @panic("OOM!");
        return 0;
    }
    l.checkType(2, .table);
    const len: usize = @intCast(l.rawLen(2));
    const child_args = std.heap.raw_c_allocator.alloc([:0]const u8, len + 1) catch @panic("OOM!");
    defer std.heap.raw_c_allocator.free(child_args);
    child_args[0] = command;
    for (1..len + 1) |i| {
        _ = l.rawGetIndex(2, @intCast(i));
        child_args[i] = l.toString(-1) catch l.raiseErrorStr("child_process argument not convertible to a string!", .{});
    }
    var child = std.process.Child.init(child_args, std.heap.raw_c_allocator);
    child.spawn() catch |err| {
        l.raiseErrorStr("child_process %s failed with error %s!", .{ command.ptr, @errorName(err).ptr });
    };
    children.append(child) catch @panic("OOM!");
    return 0;
}

/// registers a new OSC handler.
// users should use `osc.register` instead
// @param path a string representing an OSC path `/like/this`
// @param types (optional) a string representing the arg types that the function expects
// @see osc.register
// @function osc_register
fn osc_register(l: *Lua) i32 {
    const num_args = l.getTop();
    if (num_args < 1) return 0;
    const path = l.checkString(1);
    const types: ?[:0]const u8 = if (num_args < 2) null else l.checkString(2);
    const nr = osc.add_method(path, types);
    l.pushInteger(@intCast(nr));
    return 1;
}

/// unregisters OSC handlers matching the given path (and typespec if provided)
// users should use `osc.delete` instead
// @param path a string representing an OSC path `/like/this`
// @param types (optional) a string representing the arg types that the function expects
// @function osc_delete
fn osc_delete(l: *Lua) i32 {
    const num_args = l.getTop();
    defer l.setTop(0);
    if (num_args < 1) return 0;
    const path = l.checkString(1);
    const types: ?[:0]const u8 = if (num_args < 2) null else l.checkString(2);
    osc.delete_method(path, types);
    return 0;
}

/// sends OSC to specified address.
// users should use `osc.send` instead.
// @param address a table of the form `{host, port}`, both strings
// @param path a string representing an OSC path `/like/this`
// @param args an array whose data will be passed to OSC as arguments
// @see osc.send
// @usage osc.send({"localhost", "7777"}, "/send/stuff", {"a", 0, 0.5, nil, true})
// @function osc_send
fn osc_send(l: *Lua) i32 {
    var host: ?[:0]const u8 = null;
    var port: ?[:0]const u8 = null;
    var path: ?[:0]const u8 = null;
    const num_args = l.getTop();
    if (num_args < 2) return 0;
    l.checkType(1, ziglua.LuaType.table);
    if (l.rawLen(1) != 2) {
        l.argError(1, "address should be a table in the form {host, port}");
    }

    l.pushNumber(1);
    _ = l.getTable(1);
    if (l.isString(-1)) {
        host = l.toString(-1) catch unreachable;
    } else {
        l.argError(1, "address should be a table in the form {host, port}");
    }
    l.pop(1);

    l.pushNumber(2);
    _ = l.getTable(1);
    if (l.isString(-1)) {
        port = l.toString(-1) catch unreachable;
    } else {
        l.argError(1, "address should be a table in the form {host, port}");
    }
    l.pop(1);

    l.checkType(2, ziglua.LuaType.string);
    path = l.toString(2) catch unreachable;

    var sfb = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfb.get();
    l.checkType(3, ziglua.LuaType.table);
    const len = l.rawLen(3);
    var msg = allocator.alloc(osc.Lo_Arg, len) catch @panic("OOM!");
    defer allocator.free(msg);
    var i: usize = 1;
    while (i <= len) : (i += 1) {
        l.pushInteger(@intCast(i));
        _ = l.getTable(3);
        msg[i - 1] = switch (l.typeOf(-1)) {
            .nil => .{ .Lo_Nil = false },
            .boolean => blk: {
                if (l.toBoolean(-1)) {
                    break :blk .{ .Lo_True = true };
                } else {
                    break :blk .{ .Lo_False = false };
                }
            },
            .number => blk: {
                if (l.toInteger(-1)) |number| {
                    break :blk .{ .Lo_Int64 = number };
                } else |_| {
                    break :blk .{ .Lo_Double = l.toNumber(-1) catch unreachable };
                }
            },
            .string => blk: {
                const str = allocator.dupeZ(u8, l.toString(-1) catch unreachable) catch @panic("OOM!");
                break :blk .{ .Lo_String = str };
            },
            else => {
                l.raiseErrorStr("invalid osc argument type %s", .{l.typeName(l.typeOf(-1)).ptr});
                return 0;
            },
        };
        l.pop(1);
    }
    defer {
        for (msg) |m| {
            if (m == .Lo_String) allocator.free(m.Lo_String);
        }
    }
    osc.send(host.?, port.?, path.?, msg);
    l.setTop(0);
    return 0;
}

/// sets grid led.
// users should use `grid:led` instead.
// @param md opaque pointer to monome device
// @param x x-coordinate for led (1-indexed)
// @param y y-coordinate for led (1-indexed)
// @param val brightness for led (0-15)
// @see grid:led
// @function grid_set_led
fn grid_set_led(l: *Lua) i32 {
    check_num_args(l, 4);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const x: u8 = @intFromFloat(l.checkNumber(2) - 1);
    const y: u8 = @intFromFloat(l.checkNumber(3) - 1);
    const val: u8 = @intFromFloat(l.checkNumber(4));
    md.grid_set_led(x, y, val);
    l.setTop(0);
    return 0;
}

/// sets all grid leds.
// users should use `grid:all` instead.
// @param md opaque pointer to monome device
// @param val brightness for led (0-15)
// @see grid:all
// @function grid_all_led
fn grid_all_led(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const val: u8 = @intFromFloat(l.checkNumber(2));
    md.grid_all_led(val);
    l.setTop(0);
    return 0;
}

/// reports number of rows of grid device.
// @param md opaque pointer to monome device
// @return number of rows
// @function grid_rows
fn grid_rows(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    l.setTop(0);
    l.pushInteger(md.rows);
    return 1;
}

/// reports number of columns of grid device.
// @param md opaque pointer to monome device
// @return number of columns
// @function grid_cols
fn grid_cols(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    l.setTop(0);
    l.pushInteger(md.cols);
    return 1;
}

/// sets grid rotation.
// users should use `grid:rotation` instead
// @param md opaque pointer to monome device
// @param rotation value to rotate
// @see grid:rotation
// @function grid_set_rotation
fn grid_set_rotation(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const rotation: u16 = @intFromFloat(l.checkNumber(2));
    md.set_rotation(rotation);
    l.setTop(0);
    return 0;
}

/// enable tilt data.
// users should use `grid:tilt` instead
// @param md opaque pointer to monome device
// @param sensor tilt sensor to enable
// @see grid:tilt
// @function grid_tilt_enable
fn grid_tilt_enable(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const sensor: u8 = @intFromFloat(l.checkNumber(2) - 1);
    md.tilt_set(sensor, 1);
    return 0;
}

/// disable tilt data.
// users should use `grid:tilt` instead
// @param md opaque pointer to monome device
// @param sensor tilt sensor to disable
// @see grid:tilt
// @function grid_tilt_disable
fn grid_tilt_disable(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const sensor: u8 = @intFromFloat(l.checkNumber(2) - 1);
    md.tilt_set(sensor, 0);
    return 0;
}

/// sets arc led.
// users should use `arc:led` instead
// @param md opaque pointer to monome device
// @param ring arc ring (1-based)
// @param led arc led (1-based)
// @param val led brightness (0-15)
// @see arc:led
// @function arc_set_led
fn arc_set_led(l: *Lua) i32 {
    check_num_args(l, 4);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const ring: u8 = @intFromFloat(l.checkNumber(2) - 1);
    const led: i32 = @intFromFloat(l.checkNumber(3) - 1);
    const u8_led: i32 = @mod(led, 64);
    const val: u8 = @intFromFloat(l.checkNumber(4));
    md.arc_set_led(ring, @intCast(u8_led), val);
    l.setTop(0);
    return 0;
}

/// sets all arc leds.
// users should use `arc:all` instead
// @param md opaque pointser to monome device
// @param val led brightness (0-15)
// @see arc:all
// @function arc_all_led
fn arc_all_led(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const val: u8 = @intFromFloat(l.checkNumber(2));
    md.grid_all_led(val);
    l.setTop(0);
    return 0;
}

/// send dirty quads to monome device.
// users should use `grid:refresh` or `arc:refresh` instead
// @param md opaque pointer to monome device
// @see arc:refresh
// @see grid:refresh
// @function monome_refresh
fn monome_refresh(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    md.refresh();
    l.setTop(0);
    return 0;
}

/// sets maximum led brightness.
// users should use `grid:intensity` or `arc:intensity` instead
// @param md opaque pointer to monome device
// @param level maximum brightness level
// @see arc:intensity
// @see grid:intensity
// @function monome_intensity
fn monome_intensity(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const level: u8 = @intFromFloat(l.checkNumber(2));
    md.intensity(level);
    l.setTop(0);
    return 0;
}

/// refreshes the screen.
// users should use `screen.redraw` instead
// @see screen.refresh
// @function screen_refresh
fn screen_refresh(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.post(.{
        .Refresh = {},
    });
    return 0;
}

/// moves the current location on the screen.
// users should use `screen.move` instead
// @param x x-coordinate (1-based)
// @param y y-coordinate (1-based)
// @see screen.move
// @function screen_move
fn screen_move(l: *Lua) i32 {
    check_num_args(l, 2);
    const x = l.checkNumber(1);
    const y = l.checkNumber(2);
    screen.post(.{
        .Move = .{
            .rel = false,
            .x = @intFromFloat(x - 1),
            .y = @intFromFloat(y - 1),
        },
    });
    l.setTop(0);
    return 0;
}

/// moves the current location on the screen relative to the current location.
// users should use `screen.move_rel` instead
// @param x relative x-coordinate
// @param y relative y-coordinate
// @see screen.move_rel
// @function screen_move_rel
fn screen_move_rel(l: *Lua) i32 {
    check_num_args(l, 2);
    const x = l.checkNumber(1);
    const y = l.checkNumber(2);
    screen.post(.{
        .Move = .{
            .rel = true,
            .x = @intFromFloat(x),
            .y = @intFromFloat(y),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a single pixel.
// users should use `screen.pixel` instead
// @param x x-coordinate (1-based)
// @param y y-coordinate (1-based)
// @see screen.pixel
// @function screen_pixel
fn screen_pixel(l: *Lua) i32 {
    check_num_args(l, 2);
    const x = l.checkNumber(1);
    const y = l.checkNumber(2);
    screen.post(.{
        .Pixel = .{
            .x = @intFromFloat(x - 1),
            .y = @intFromFloat(y - 1),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a single pixel at the current location.
// users should use `screen.pixel_rel` instead
// @see screen.pixel_rel
// @function screen_pixel_rel
fn screen_pixel_rel(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.post(.{
        .PixelRel = {},
    });
    return 0;
}

/// draws a line.
// users should use `screen.line` instead
// @param bx terminal x-coordinate (1-based)
// @param by terminal y-coordinate (1-based)
// @see screen.line
// @function screen_line
fn screen_line(l: *Lua) i32 {
    check_num_args(l, 2);
    const bx = l.checkNumber(1);
    const by = l.checkNumber(2);
    screen.post(.{
        .Line = .{
            .rel = false,
            .x = @intFromFloat(bx - 1),
            .y = @intFromFloat(by - 1),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a line relative to the current location.
// users should use `screen.line_rel` instead
// @param bx terminal relative x-coordinate
// @param by terminal relative y-coordinate
// @see screen.line_rel
// @function screen_line_rel
fn screen_line_rel(l: *Lua) i32 {
    check_num_args(l, 2);
    const bx = l.checkNumber(1);
    const by = l.checkNumber(2);
    screen.post(.{
        .Line = .{
            .rel = true,
            .x = @intFromFloat(bx),
            .y = @intFromFloat(by),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a curve (cubic Bézier spline).
// users should use `screen.curve` instead
// @param x1 1rst handle x
// @param y1 1rst handle y
// @param x2 2nd handle x
// @param y2 2nd handle y
// @param x3 3rd destination x
// @param y3 3rd destination y
// @see screen.curve
// @function screen_curve
fn screen_curve(l: *Lua) i32 {
    check_num_args(l, 6);
    const x1 = l.checkNumber(1);
    const y1 = l.checkNumber(2);
    const x2 = l.checkNumber(3);
    const y2 = l.checkNumber(4);
    const x3 = l.checkNumber(5);
    const y3 = l.checkNumber(6);
    screen.post(.{
        .Curve = .{
            .x1 = x1,
            .x2 = x2,
            .x3 = x3,
            .y1 = y1,
            .y2 = y2,
            .y3 = y3,
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a rectangle.
// users should use `screen.rect` instead
// @param w width in pixels
// @param h height in pixels
// @see screen:rect
// @function screen_rect
fn screen_rect(l: *Lua) i32 {
    check_num_args(l, 2);
    const w = l.checkNumber(1);
    const h = l.checkNumber(2);
    screen.post(.{
        .Rect = .{
            .fill = false,
            .w = @intFromFloat(w),
            .h = @intFromFloat(h),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a filled rectangle.
// users should use `screen.rect` instead
// @param w width in pixels
// @param h height in pixels
// @see screen:rect
// @function screen_rect_fill
fn screen_rect_fill(l: *Lua) i32 {
    check_num_args(l, 2);
    const w = l.checkNumber(1);
    const h = l.checkNumber(2);
    screen.post(.{
        .Rect = .{
            .fill = true,
            .w = @intFromFloat(w),
            .h = @intFromFloat(h),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws text to the screen, left-aligned.
// users should use `screen.text` instead
// @param words text to draw to the screen
// @see screen.text
// @function screen_text
fn screen_text(l: *Lua) i32 {
    check_num_args(l, 1);
    const words = l.toString(1) catch unreachable;
    screen.post(.{
        .Text = .{
            .alignment = .Left,
            .words = std.heap.c_allocator.dupeZ(u8, words) catch @panic("OOM!"),
            .allocator = std.heap.c_allocator,
        },
    });
    l.setTop(0);
    return 0;
}

/// draws text to the screen, center-aligned.
// users should use `screen.text_center` instead
// @param words text to draw to the screen
// @see screen.text_center
// @function screen_text_center
fn screen_text_center(l: *Lua) i32 {
    check_num_args(l, 1);
    const words = l.toString(1) catch unreachable;
    screen.post(.{
        .Text = .{
            .alignment = .Center,
            .words = std.heap.c_allocator.dupeZ(u8, words) catch @panic("OOM!"),
            .allocator = std.heap.c_allocator,
        },
    });
    l.setTop(0);
    return 0;
}

/// draws text to the screen, right-aligned.
// users should use `screen.text_right` instead
// @param words text to draw to the screen
// @see screen.text
// @function screen_text_right
fn screen_text_right(l: *Lua) i32 {
    check_num_args(l, 1);
    const words = l.toString(1) catch unreachable;
    screen.post(.{
        .Text = .{
            .alignment = .Right,
            .words = std.heap.c_allocator.dupeZ(u8, words) catch @panic("OOM!"),
            .allocator = std.heap.c_allocator,
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a circle arc to the screen.
// users should use `screen.arc` instead
// @param radius radius of the circle in pixels
// @param theta_1 angle to start at (0-2*pi)
// @param theta_2 angle to finish at (0-2*pi)
// @see screen.arc
// @function screen_arc
fn screen_arc(l: *Lua) i32 {
    check_num_args(l, 3);
    const radius = l.checkNumber(1);
    const theta_1 = l.checkNumber(2);
    const theta_2 = l.checkNumber(3);
    if (theta_1 < 0 or theta_2 < theta_1 or std.math.tau < theta_2) {
        l.argError(2, "theta_1 and theta_2 must satisfy 0 <= theta_1 <= theta_2 <= 2*pi");
    }
    screen.post(.{
        .Arc = .{
            .radius = @intFromFloat(radius),
            .theta_1 = theta_1,
            .theta_2 = theta_2,
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a circle to the screen.
// users should use `screen.circle` instead
// @param radius radius of the circle in pixels
// @see screen.circle
// @function screen_circle
fn screen_circle(l: *Lua) i32 {
    check_num_args(l, 1);
    const radius = l.checkNumber(1);
    screen.post(.{
        .Circle = .{
            .fill = false,
            .radius = @intFromFloat(radius),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a filled-in circle to the screen.
// users should use `screen.circle_fill` instead
// @param radius radius of the circle in pixels
// @see screen.circle_fill
// @function screen_circle_fill
fn screen_circle_fill(l: *Lua) i32 {
    check_num_args(l, 1);
    const radius = l.checkNumber(1);
    screen.post(.{
        .Circle = .{
            .fill = true,
            .radius = @intFromFloat(radius),
        },
    });
    l.setTop(0);
    return 0;
}

/// draws a filled-in triangle.
// users should use `screen.triangle` instead
// @param ax x-coordinate
// @param ay y-coordinate
// @param bx x-coordinate
// @param by y-coordinate
// @param cx x-coordinate
// @param cy y-coordinate
// @see screen.triangle
// @function screen_triangle
fn screen_triangle(l: *Lua) i32 {
    check_num_args(l, 6);
    const allocator = std.heap.raw_c_allocator;
    const vertices = allocator.alloc(screen.Vertex, 3) catch @panic("OOM!");
    const indices = allocator.alloc(usize, 3) catch @panic("OOM!");
    for (vertices, 0..) |*vertex, i| {
        indices[i] = i;
        vertex.color = .{};
        vertex.position = .{
            .x = @floatCast(l.checkNumber(@intCast(2 * i + 1))),
            .y = @floatCast(l.checkNumber(@intCast(2 * i + 2))),
        };
        vertex.tex_coord = .{};
    }
    screen.post(.{
        .DefineGeometry = .{
            .allocator = allocator,
            .indices = indices,
            .texture = null,
            .vertices = vertices,
        },
    });
    return 0;
}

/// draws a filled-in quad.
// users should use `screen.quad` instead
// @param ax x-coordinate
// @param ay y-coordinate
// @param bx x-coordinate
// @param by y-coordinate
// @param cx x-coordinate
// @param cy y-coordinate
// @param dx x-coordinate
// @param dy y-coordinate
// @see screen.quad
// @function screen_quad
fn screen_quad(l: *Lua) i32 {
    check_num_args(l, 8);
    const allocator = std.heap.raw_c_allocator;
    const vertices = allocator.alloc(screen.Vertex, 4) catch @panic("OOM!");
    const indices: []const usize = &.{ 0, 1, 2, 2, 3, 0 };
    for (vertices, 0..) |*vertex, i| {
        vertex.color = .{};
        vertex.position = .{
            .x = @floatCast(l.checkNumber(@intCast(2 * i + 1))),
            .y = @floatCast(l.checkNumber(@intCast(2 * i + 2))),
        };
        vertex.tex_coord = .{};
    }
    screen.post(.{
        .DefineGeometry = .{
            .allocator = allocator,
            .indices = allocator.dupe(usize, indices) catch @panic("OOM!"),
            .texture = null,
            .vertices = vertices,
        },
    });
    return 0;
}

/// creates and returns a new texture
// users should use `screen.new_texture` instead
// @param width width in pixels
// @param height height in pixels
// @return texture number representing texture or nil
// @see screen.new_texture
// @function screen_new_texture
fn screen_new_texture(l: *Lua) i32 {
    check_num_args(l, 2);
    const width = l.checkNumber(1);
    const height = l.checkNumber(2);
    screen.post(.{
        .NewTexture = .{
            .width = @intFromFloat(width),
            .height = @intFromFloat(height),
        },
    });
    screen.lock.lock();
    screen.cond.wait(&screen.lock);
    defer screen.lock.unlock();
    if (screen.response) |r| {
        switch (r) {
            .TextSize, .TextureSize => logger.err("got wrong response type {s}!", .{@tagName(r)}),

            .Texture => |texture| l.pushInteger(@intCast(texture)),
        }
    }
    screen.response = null;
    return 1;
}

/// creates and returns a new texture from image file
// users should use `screen.new_texture` instead
// @param filename path to file
// @return texture number representing the texture or nil
// @see screen.new_texture_from_file
// @function screen_new_texture_from_file
fn screen_new_texture_from_file(l: *Lua) i32 {
    check_num_args(l, 1);
    const filename = l.checkString(1);
    const allocator = std.heap.raw_c_allocator;
    screen.post(.{
        .NewTextureFromFile = .{
            .allocator = allocator,
            .filename = allocator.dupeZ(u8, filename) catch @panic("OOM!"),
        },
    });
    screen.lock.lock();
    screen.cond.wait(&screen.lock);
    defer screen.lock.unlock();
    if (screen.response) |r| {
        switch (r) {
            .TextSize, .TextureSize => logger.err("got wrong response type {s}!", .{@tagName(r)}),
            .Texture => |texture| l.pushInteger(@intCast(texture)),
        }
    }
    screen.response = null;
    return 1;
}

/// returns the texture's dimensions
// @param texture opaque pointer to texture
// @return width width in pixels or nil
// @return height height in pixels or nil
// @function screen_texture_dimensions
fn screen_texture_dimensions(l: *Lua) i32 {
    check_num_args(l, 1);
    const texture: usize = @intCast(l.checkInteger(1));
    screen.post(.{
        .TextureSize = .{
            .texture = texture,
        },
    });
    screen.lock.lock();
    screen.cond.wait(&screen.lock);
    defer screen.lock.unlock();
    if (screen.response) |r| {
        switch (r) {
            .TextSize, .Texture => logger.err("got wrong response type {s}!", .{@tagName(r)}),
            .TextureSize => |size| {
                l.pushInteger(size.w);
                l.pushInteger(size.h);
            },
        }
    }
    screen.response = null;
    return 2;
}

/// renders texture at given coordinates
// users should use `screen.Texture.render` instead
// @param texture opaque pointer to texture
// @param x x-coordinate
// @param y y-coordinate
// @param zoom scale to draw at
// @function screen_render_texture
fn screen_render_texture(l: *Lua) i32 {
    check_num_args(l, 4);
    const texture = l.checkInteger(1);
    const x = l.checkNumber(2) - 1;
    const y = l.checkNumber(3) - 1;
    const zoom = l.checkNumber(4);
    screen.post(.{
        .RenderTexture = .{
            .x = @intFromFloat(x),
            .y = @intFromFloat(y),
            .zoom = zoom,
            .texture = @intCast(texture),
        },
    });
    return 0;
}
/// renders texture at given coordinates with rotation and flip
// users should use `screen.Texture.render_extended` instead
// @param texture opaque pointer to texture
// @param x x-coordinate
// @param y y-coordinate
// @param zoom scale to draw at
// @param theta angle in radians
// @param flip_h flip horizontally if true
// @param flip_v flip vertically if true
// @function screen_render_texture_extended
fn screen_render_texture_extended(l: *Lua) i32 {
    check_num_args(l, 7);
    const texture = l.checkInteger(1);
    const x = l.checkNumber(2) - 1;
    const y = l.checkNumber(3) - 1;
    const zoom = l.checkNumber(4);
    const theta = l.checkNumber(5);
    const deg = std.math.radiansToDegrees(theta);
    const flip_h = l.toBoolean(6);
    const flip_v = l.toBoolean(7);
    screen.post(.{
        .RenderTexture = .{
            .x = @intFromFloat(x),
            .y = @intFromFloat(y),
            .zoom = zoom,
            .texture = @intCast(texture),
            .flip_h = flip_h,
            .flip_v = flip_v,
            .deg = deg,
        },
    });
    return 0;
}

/// draws arbitrary vertex-defined geometry.
// users should use `screen.geometry` instead.
// @param vertices a list of lists {pos, col, tex_coord},
// where `pos = {x, y}` is a list of pixel coordinates,
// where `col = {r, g, b, a}` is a list of color data,
// and `tex_coord = {x, y}` (which is optional), is a list of texture coordinates
// @param indices (optional) a list of indices into the vertices list
// @param texture (optional) a texture to draw from
fn screen_geometry(l: *Lua) i32 {
    const allocator = std.heap.raw_c_allocator;
    const num_args = l.getTop();
    const texture = if (num_args >= 3) blk: {
        break :blk l.checkInteger(3);
    } else null;
    l.checkType(1, ziglua.LuaType.table);
    const len = l.rawLen(1);
    const verts = allocator.alloc(screen.Vertex, len) catch @panic("OOM!");
    for (verts, 0..) |*v, i| {
        const t = l.getIndex(1, @intCast(i + 1));
        if (t != .table) l.argError(1, "vertices should be a list of lists");
        const pos = process_pos(l);
        const col = process_col(l);
        const t_coord = process_t_coord(l);
        v.* = .{
            .position = pos,
            .color = col,
            .tex_coord = t_coord,
        };
    }
    const indices = if (num_args >= 2) blk: {
        l.checkType(2, ziglua.LuaType.table);
        const indlen = l.rawLen(2);
        const ind = allocator.alloc(usize, indlen) catch @panic("OOM!");
        for (ind, 0..) |*idx, i| {
            l.pushInteger(@intCast(i + 1));
            _ = l.getTable(2);
            const index = l.toInteger(-1) catch l.argError(2, "indices should be a list of integers");
            idx.* = @intCast(index - 1);
            l.pop(1);
        }
        break :blk ind;
    } else null;
    screen.post(.{
        .DefineGeometry = .{
            .allocator = allocator,
            .indices = indices,
            .texture = if (texture) |txt| @intCast(txt) else null,
            .vertices = verts,
        },
    });
    l.setTop(0);
    return 0;
}

fn process_pos(l: *Lua) screen.Vertex.Position {
    var t = l.getIndex(-1, 1);
    if (t != .table) l.argError(1, "position should be a list of the form {x, y}");
    t = l.getIndex(-1, 1);
    if (t != .number) l.argError(1, "position should be a list of numbers");
    const x = l.toNumber(-1) catch unreachable;
    l.pop(1);
    t = l.getIndex(-1, 2);
    if (t != .number) l.argError(1, "position should be a list of numbers");
    const y = l.toNumber(-1) catch unreachable;
    l.pop(1);
    l.pop(1);
    return .{ .x = @floatCast(x - 1), .y = @floatCast(y - 1) };
}

fn process_col(l: *Lua) screen.Vertex.Color {
    var t = l.getIndex(-1, 2);
    if (t != .table) l.argError(1, "color should be a list of the form {r, g, b, a?}");
    const len = l.rawLen(-1);
    if (len < 3) l.argError(1, "color needs at least three numbers");
    t = l.getIndex(-1, 1);
    if (t != .number) l.argError(1, "color should be a list of numbers");
    const r = l.toNumber(-1) catch unreachable;
    l.pop(1);
    t = l.getIndex(-1, 2);
    if (t != .number) l.argError(1, "color should be a list of numbers");
    const g = l.toNumber(-1) catch unreachable;
    l.pop(1);
    t = l.getIndex(-1, 3);
    if (t != .number) l.argError(1, "color should be a list of numbers");
    const b = l.toNumber(-1) catch unreachable;
    l.pop(1);
    const a = if (len >= 4) blk: {
        t = l.getIndex(-1, 4);
        if (t != .number) l.argError(1, "color should be a list of numbers");
        const aa = l.toNumber(-1) catch unreachable;
        l.pop(1);
        break :blk aa;
    } else 255;
    l.pop(1);
    return .{
        .r = @intFromFloat(@min(r, 255)),
        .g = @intFromFloat(@min(g, 255)),
        .b = @intFromFloat(@min(b, 255)),
        .a = @intFromFloat(@min(a, 255)),
    };
}

fn process_t_coord(l: *Lua) screen.Vertex.Position {
    const len = l.rawLen(-1);
    if (len < 3) return .{ .x = 0, .y = 0 };
    var t = l.getIndex(-1, 3);
    if (t != .table) l.argError(1, "tex_coord should be a list of the form {x, y}");
    t = l.getIndex(-1, 1);
    if (t != .number) l.argError(1, "tex_coord should be a list of numbers");
    const x = l.toNumber(-1) catch unreachable;
    l.pop(1);
    t = l.getIndex(-1, 2);
    if (t != .number) l.argError(1, "tex_coord should be a list of numbers");
    const y = l.toNumber(-1) catch unreachable;
    l.pop(1);
    l.pop(1);
    return .{
        .x = @floatCast(x),
        .y = @floatCast(y),
    };
}

/// sets screen color.
// users should use `screen.color` instead
// @param r red value (0-255)
// @param g green value (0-255)
// @param b blue value (0-255)
// @param a alpha value (0-255), defaults to 255
// @see screen:color
// @function screen_color
fn screen_color(l: *Lua) i32 {
    check_num_args(l, 4);
    const r: i32 = @intFromFloat(l.checkNumber(1));
    const g: i32 = @intFromFloat(l.checkNumber(2));
    const b: i32 = @intFromFloat(l.checkNumber(3));
    const a: i32 = @intFromFloat(l.checkNumber(4));
    screen.post(.{
        .Color = .{
            .r = @min(@max(0, r), 255),
            .g = @min(@max(0, g), 255),
            .b = @min(@max(0, b), 255),
            .a = @min(@max(0, a), 255),
        },
    });
    l.setTop(0);
    return 0;
}

/// clears the screen.
// users should use `screen.clear` instead
// @see screen.clear
// @function screen_clear
fn screen_clear(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.post(.{
        .Clear = {},
    });
    return 0;
}

/// sets which screen to draw to.
// @function screen_set
fn screen_set(l: *Lua) i32 {
    check_num_args(l, 1);
    const value: usize = @intCast(l.checkInteger(1));
    if (value - 1 > 1 or value - 1 < 0) return 0;
    screen.post(.{
        .Set = value - 1,
    });
    return 0;
}

/// unhides the params window
// @function screen_show
fn screen_show(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.post(.{
        .Show = 1,
    });
    return 0;
}

/// returns the size in pixels of the given text.
// users should use `screen.get_text_size` instead
// @see screen.get_text_size
// @function screen_get_text_size
fn screen_get_text_size(l: *Lua) i32 {
    check_num_args(l, 1);
    const str = l.toString(1) catch unreachable;
    const allocator = std.heap.c_allocator;
    const dup = allocator.dupeZ(u8, str) catch @panic("OOM!");
    screen.post(.{ .text_size = .{
        .words = dup,
        .allocator = allocator,
    } });
    screen.lock.lock();
    screen.cond.wait(&screen.lock);
    defer screen.lock.unlock();
    if (screen.response) |r| {
        switch (r) {
            .Texture, .TextureSize => logger.err("got wrong response type {s}!", .{@tagName(r)}),
            .TextSize => |size| {
                l.pushInteger(size.w);
                l.pushInteger(size.h);
            },
        }
    }
    screen.response = null;
    return 2;
}

/// sets the size of the current window.
// users should use `screen.set_size` instead
// @see screen.set_size
// @param width width in pixels
// @param height height in pixels
// @param zoom zoom factor
// @function screen_set_size
fn screen_set_size(l: *Lua) i32 {
    check_num_args(l, 3);
    const w: i32 = @intFromFloat(l.checkNumber(1));
    const h: i32 = @intFromFloat(l.checkNumber(2));
    const z: i32 = @intFromFloat(l.checkNumber(3));
    screen.post(.{
        .SetSize = .{
            .w = w,
            .h = h,
            .z = z,
        },
    });
    l.setTop(0);
    return 0;
}

/// sets the fullscreen state of the current window.
// users should use `screen.set_fullscreen` instead
// @see screen.set_fullscreen
// @param is_fullscreen boolean
// @function screen_set_fullscreen
fn screen_set_fullscreen(l: *Lua) i32 {
    check_num_args(l, 1);
    const is_fullscreen = l.toBoolean(1);
    screen.post(.{
        .Fullscreen = is_fullscreen,
    });
    l.setTop(0);
    return 0;
}

/// sets the position of the current window.
// users should use `screen.set_position` instead
// @see screen.set_position
// @param x x-position of upper-left corner
// @param y y-position of upper-left corner
// @function screen_set_position
fn screen_set_position(l: *Lua) i32 {
    check_num_args(l, 2);
    const x: i32 = @intFromFloat(l.checkNumber(1));
    const y: i32 = @intFromFloat(l.checkNumber(2));
    screen.post(.{
        .SetPosition = .{
            .x = x,
            .y = y,
        },
    });
    l.setTop(0);
    return 0;
}

/// starts a new metro.
// users should use `metro:start` instead
// @param idx metro id (1-36)
// @param seconds float time at which to repeat
// @param count stage at which to stop
// @param stage stage at which to start
// @see metro:start
// @function metro_start
fn metro_start(l: *Lua) i32 {
    check_num_args(l, 4);
    const idx: u8 = @intCast(l.checkInteger(1) - 1);
    const seconds = l.checkNumber(2);
    const count = l.checkNumber(3);
    const stage = l.checkNumber(4) - 1;
    l.setTop(0);
    metro.start(
        idx,
        seconds,
        @intFromFloat(count),
        @intFromFloat(stage),
    ) catch l.raiseErrorStr("unable to create thread!", .{});
    return 0;
}

/// stops a metro.
// users should use `metro:stop` instead
// @param idx metro id (1-36)
// @see metro:stop
// @function metro_stop
fn metro_stop(l: *Lua) i32 {
    check_num_args(l, 1);
    const idx: u8 = @intFromFloat(l.checkNumber(1) - 1);
    metro.stop(idx);
    l.setTop(0);
    return 0;
}

/// set repetition time for a metro.
// users can use the `time` field on a metro instead.
// @param idx metro id (1-36)
// @param seconds new period (float)
// @function metro_set_time
fn metro_set_time(l: *Lua) i32 {
    check_num_args(l, 2);
    const idx: u8 = @intFromFloat(l.checkNumber(1) - 1);
    const seconds = l.checkNumber(2);
    metro.set_period(idx, seconds);
    l.setTop(0);
    return 0;
}

/// outputs midi data to device.
// users should use `midi:send` instead
// @param dev opaque pointer to midi device
// @param bytes table of small integers to write
// @see midi:send
// @function midi_write
fn midi_write(l: *Lua) i32 {
    var sfba = std.heap.stackFallback(1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const dev = l.toUserdata(midi.Device, 1) catch unreachable;
    l.checkType(2, ziglua.LuaType.table);
    const len = l.rawLen(2);
    var i: c_longlong = 1;
    var msg = allocator.allocSentinel(u8, @intCast(len), 0) catch @panic("OOM!");
    defer allocator.free(msg);
    while (i <= len) : (i += 1) {
        l.pushInteger(i);
        _ = l.getTable(2);
        msg[@intCast(i - 1)] = @intFromFloat(l.toNumber(-1) catch {
            l.raiseErrorStr("expected integer argument to midi_write!", .{});
            return 0;
        });
    }
    dev.write(msg) catch |err| {
        switch (err) {
            error.NotFound => l.raiseErrorStr("no output device found for device %d", .{dev.id + 1}),
            error.WriteError => l.raiseErrorStr("error writing to device %d", .{dev.id + 1}),
            else => @panic("unexpected error in midi.write!"),
        }
        return 0;
    };
    l.setTop(0);
    return 0;
}

/// schedules coroutine for sleep.
// users should use `clock.sleep` instead
// @see clock.sleep
// @function clock_schedule_sleep
fn clock_schedule_sleep(l: *Lua) i32 {
    const top = l.getTop();
    if (top < 2) {
        l.raiseErrorStr("expected >= 2 arguments, got %d!\n", .{top});
        return 1;
    }
    const idx = l.checkNumber(1) - 1;
    const seconds = l.checkNumber(2);
    clock.schedule_sleep(@intFromFloat(idx), seconds);
    return top - 2;
}

/// schedules coroutine for sync.
// users should use `clock.sync` instead
// @see clock.sync
// @function clock_schedule_sync
fn clock_schedule_sync(l: *Lua) i32 {
    const top = l.getTop();
    if (top < 2) {
        l.raiseErrorStr("expected >= 2 arguments, got {d}!\n", .{top});
        return 1;
    }
    const idx = l.checkNumber(1) - 1;
    const beats = l.checkNumber(2);
    const offset = if (top >= 3) l.checkNumber(3) else 0;
    clock.schedule_sync(@intFromFloat(idx), beats, offset);
    return if (top >= 3) top - 3 else top - 2;
}

/// returns current tempo.
// users should use `clock.get_tempo` instead
// @return bpm
// @see clock.get_tempo
// @function clock_get_tempo
fn clock_get_tempo(l: *Lua) i32 {
    check_num_args(l, 0);
    const bpm = clock.get_tempo();
    l.pushNumber(bpm);
    return 1;
}

/// returns current beat since the clock was last reset.
// users should use `clock.get_beats` instead
// @return beats
// @see clock.get_beats
// @function clock_get_beats
fn clock_get_beats(l: *Lua) i32 {
    const beats = clock.get_beats();
    l.pushNumber(beats);
    return 1;
}

/// sets internal clock tempo.
// users should use the clock param instead
// @param bpm
// @function clock_internal_set_tempo
fn clock_internal_set_tempo(l: *Lua) i32 {
    check_num_args(l, 1);
    const bpm = l.checkNumber(1);
    clock.internal_set_tempo(bpm);
    return 0;
}

/// sets link clock tempo.
// users should use the clock param instead
// @param bpm
// @function clock_link_set_tempo
fn clock_link_set_tempo(l: *Lua) i32 {
    check_num_args(l, 1);
    const bpm = l.checkNumber(1);
    clock.link_set_tempo(bpm);
    return 0;
}

/// sets clock link quantum
// users should use the clock param instead
// @param quantum (in beats)
// @function clock_link_set_quantum
fn clock_link_set_quantum(l: *Lua) i32 {
    check_num_args(l, 1);
    const quantum = l.checkNumber(1);
    clock.set_quantum(quantum);
    return 0;
}

/// sets clock source.
// users should use the clock source param instead
// @param source
// @function clock_set_source
fn clock_set_source(l: *Lua) i32 {
    check_num_args(l, 1);
    const source = l.checkInteger(1);
    clock.set_source(@enumFromInt(source)) catch {
        l.raiseErrorStr("failed to start clock!", .{});
    };
    return 0;
}

/// starts internal clock.
// users should use the clock param instead
// @function clock_internal_start
fn clock_internal_start(l: *Lua) i32 {
    check_num_args(l, 0);
    clock.reset(0);
    clock.start();
    return 0;
}

/// starts link transport
// users should use `clock.link.start()` instead
// @function clock_link_start
fn clock_link_start(l: *Lua) i32 {
    check_num_args(l, 0);
    clock.link_start();
    return 0;
}

/// stops link transport
// users should use `clock.link.stop()` instead
// @function clock_link_start
fn clock_link_stop(l: *Lua) i32 {
    check_num_args(l, 0);
    clock.link_stop();
    return 0;
}

/// stops internal clock.
// users should use the clock param instead
// @function clock_internal_stop
fn clock_internal_stop(l: *Lua) i32 {
    check_num_args(l, 0);
    clock.stop();
    return 0;
}

/// cancels coroutine.
// users should use `clock.cancel` instead
// @param idx id of coroutine to cancel
// @see clock.cancel
// @function clock_cancel
fn clock_cancel(l: *Lua) i32 {
    check_num_args(l, 1);
    const idx = l.checkNumber(1) - 1;
    l.setTop(0);
    if (idx < 0 or idx > 100) return 0;
    clock.cancel(@intFromFloat(idx));
    return 0;
}

/// gets (fractional) time in seconds.
// @function get_time
fn get_time(l: *Lua) i32 {
    check_num_args(l, 0);
    const nanoseconds: f64 = @floatFromInt(timer.read());
    l.pushNumber(nanoseconds / std.time.ns_per_s);
    return 1;
}

/// quits seamstress
// @function quit_lvm
fn quit_lvm(l: *Lua) i32 {
    check_num_args(l, 0);
    events.post(.{
        .Quit = {},
    });
    l.setTop(0);
    return 0;
}

fn check_num_args(l: *Lua, n: i8) void {
    if (l.getTop() != n) {
        l.raiseErrorStr("error: requires %d arguments", .{n});
    }
}

inline fn push_lua_func(field: [:0]const u8, func: [:0]const u8) !void {
    _ = try lvm.getGlobal("_seamstress");
    _ = lvm.getField(-1, field);
    lvm.remove(-2);
    _ = lvm.getField(-1, func);
    lvm.remove(-2);
}

pub fn exec_code_line(line: [:0]const u8) !void {
    try handle_line(lvm, line);
}

pub fn osc_method(index: usize, msg: []const osc.Lo_Arg) !void {
    try push_lua_func("osc", "method");
    // no conversion from 1-indexing because we're already 1-indexed!
    lvm.pushInteger(@intCast(index));
    for (msg) |m| {
        switch (m) {
            .Lo_Int32 => |a| lvm.pushInteger(a),
            .Lo_Float => |a| lvm.pushNumber(a),
            .Lo_String => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Blob => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Int64 => |a| lvm.pushInteger(a),
            .Lo_Double => |a| lvm.pushNumber(a),
            .Lo_Symbol => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Midi => |a| {
                _ = lvm.pushString(&a);
            },
            .Lo_True => lvm.pushBoolean(true),
            .Lo_False => lvm.pushBoolean(false),
            .Lo_Nil => lvm.pushNil(),
            .Lo_Infinitum => lvm.pushNumber(std.math.inf(f64)),
        }
    }
    try docall(lvm, @intCast(msg.len + 1), 0);
}

pub fn osc_event(
    from_host: []const u8,
    from_port: []const u8,
    path: []const u8,
    msg: []osc.Lo_Arg,
) !void {
    var sfba = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    try push_lua_func("osc", "event");
    const path_copy = try allocator.dupeZ(u8, path);
    defer allocator.free(path_copy);
    _ = lvm.pushString(path_copy);
    lvm.createTable(@intCast(msg.len), 0);
    for (0..msg.len) |i| {
        switch (msg[i]) {
            .Lo_Int32 => |a| lvm.pushInteger(a),
            .Lo_Float => |a| lvm.pushNumber(a),
            .Lo_String => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Blob => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Int64 => |a| lvm.pushInteger(a),
            .Lo_Double => |a| lvm.pushNumber(a),
            .Lo_Symbol => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Midi => |a| _ = lvm.pushString(&a),
            .Lo_True => |a| {
                _ = a;
                lvm.pushBoolean(true);
            },
            .Lo_False => |a| {
                _ = a;
                lvm.pushBoolean(false);
            },
            .Lo_Nil => |a| {
                _ = a;
                lvm.pushNil();
            },
            .Lo_Infinitum => |a| {
                _ = a;
                lvm.pushNumber(std.math.inf(f64));
            },
        }
        lvm.rawSetIndex(-2, @intCast(i + 1));
    }

    lvm.createTable(2, 0);
    const host_copy = try allocator.dupeZ(u8, from_host);
    defer allocator.free(host_copy);
    _ = lvm.pushString(host_copy);
    lvm.rawSetIndex(-2, 1);
    const port_copy = try allocator.dupeZ(u8, from_port);
    defer allocator.free(port_copy);
    _ = lvm.pushString(port_copy);
    lvm.rawSetIndex(-2, 2);
    try docall(lvm, 3, 0);
}

pub fn monome_add(dev: *monome.Monome) !void {
    var sfba = std.heap.stackFallback(1024, std.heap.raw_c_allocator);
    const allocator = sfba.get();
    const id = dev.id;
    const port = dev.name orelse return error.Fail;
    const name = switch (dev.m_type) {
        .Grid => "monome grid",
        .Arc => "monome arc",
    };
    try push_lua_func("monome", "add");
    lvm.pushInteger(@intCast(id + 1));
    const port_copy = allocator.dupeZ(u8, port) catch @panic("OOM!");
    defer allocator.free(port_copy);
    _ = lvm.pushString(port_copy);
    _ = lvm.pushString(name);
    lvm.pushLightUserdata(dev);
    try docall(lvm, 4, 0);
}

pub fn monome_remove(id: usize) !void {
    try push_lua_func("monome", "remove");
    lvm.pushInteger(@intCast(id + 1));
    try docall(lvm, 1, 0);
}

pub fn grid_key(id: usize, x: i32, y: i32, state: i32) !void {
    try push_lua_func("grid", "key");
    lvm.pushInteger(@intCast(id + 1));
    lvm.pushInteger(x + 1);
    lvm.pushInteger(y + 1);
    lvm.pushInteger(state);
    try docall(lvm, 4, 0);
}

pub fn grid_tilt(id: usize, sensor: i32, x: i32, y: i32, z: i32) !void {
    try push_lua_func("grid", "tilt");
    lvm.pushInteger(@intCast(id + 1));
    lvm.pushInteger(sensor + 1);
    lvm.pushInteger(x + 1);
    lvm.pushInteger(y + 1);
    lvm.pushInteger(z + 1);
    try docall(lvm, 5, 0);
}

pub fn arc_delta(id: usize, ring: i32, delta: i32) !void {
    try push_lua_func("arc", "delta");
    lvm.pushInteger(@intCast(id + 1));
    lvm.pushInteger(ring + 1);
    lvm.pushInteger(delta);
    try docall(lvm, 3, 0);
}

pub fn arc_key(id: usize, ring: i32, state: i32) !void {
    try push_lua_func("arc", "delta");
    lvm.pushInteger(@intCast(id + 1));
    lvm.pushInteger(ring + 1);
    lvm.pushInteger(state);
    try docall(lvm, 3, 0);
}

pub fn screen_key(sym: i32, mod: u16, repeat: bool, state: bool, window: usize) !void {
    try push_lua_func("screen", "key");
    lvm.pushInteger(sym);
    lvm.pushInteger(mod);
    lvm.pushBoolean(repeat);
    lvm.pushInteger(if (state) 1 else 0);
    lvm.pushInteger(@intCast(window));
    try docall(lvm, 5, 0);
}

pub fn screen_mouse(x: f64, y: f64, window: usize) !void {
    try push_lua_func("screen", "mouse");
    lvm.pushNumber(x + 1);
    lvm.pushNumber(y + 1);
    lvm.pushInteger(@intCast(window));
    try docall(lvm, 3, 0);
}

pub fn screen_wheel(x: f64, y: f64, window: usize) !void {
    try push_lua_func("screen", "wheel");
    lvm.pushNumber(x);
    lvm.pushNumber(y);
    lvm.pushInteger(@intCast(window));
    try docall(lvm, 3, 0);
}

pub fn screen_click(x: f64, y: f64, state: bool, button: u8, window: usize) !void {
    try push_lua_func("screen", "click");
    lvm.pushNumber(x + 1);
    lvm.pushNumber(y + 1);
    lvm.pushInteger(if (state) 1 else 0);
    lvm.pushInteger(button);
    lvm.pushInteger(@intCast(window));
    try docall(lvm, 5, 0);
}

pub fn screen_resized(w: i32, h: i32, window: usize) !void {
    try push_lua_func("screen", "resized");
    lvm.pushInteger(w);
    lvm.pushInteger(h);
    lvm.pushInteger(@intCast(window));
    try docall(lvm, 3, 0);
}

pub fn redraw() !void {
    const t = lvm.getGlobal("redraw") catch return;
    if (t != .function) return;
    try docall(lvm, 0, 0);
}

pub fn metro_event(id: u8, stage: i64) !void {
    try push_lua_func("metro", "event");
    lvm.pushInteger(id + 1);
    lvm.pushInteger(stage);
    try docall(lvm, 2, 0);
}

pub fn midi_add(dev: *midi.Device) !void {
    const name = dev.name orelse return;
    try push_lua_func("midi", "add");
    _ = lvm.pushString(name);
    lvm.pushInteger(dev.id + 1);
    lvm.pushLightUserdata(dev);
    try docall(lvm, 3, 0);
}

pub fn midi_remove(id: u32) !void {
    try push_lua_func("midi", "remove");
    lvm.pushInteger(id + 1);
    try docall(lvm, 1, 0);
}

pub fn midi_event(id: u32, bytes: []const u8) !void {
    try push_lua_func("midi", "event");
    lvm.pushInteger(id + 1);
    lvm.createTable(@intCast(bytes.len), 0);
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        lvm.pushInteger(bytes[i]);
        lvm.rawSetIndex(-2, @intCast(i + 1));
    }
    try docall(lvm, 2, 0);
}

pub fn resume_clock(idx: u8) !void {
    try push_lua_func("clock", "resume");
    lvm.pushInteger(idx + 1);
    try docall(lvm, 1, 0);
}

pub fn clock_transport(ev_type: clock.Transport) !void {
    switch (ev_type) {
        clock.Transport.Start => try push_lua_func("transport", "start"),
        clock.Transport.Stop => try push_lua_func("transport", "stop"),
        clock.Transport.Reset => try push_lua_func("transport", "reset"),
    }
    try docall(lvm, 0, 0);
}

// -------------------------------------------------------
// lua interpreter

fn lua_print(l: *Lua) i32 {
    if (input.readline) {
        _ = c.rl_clear_visible_line();
    }
    const n = l.getTop();
    l.checkStackErr(2, "too many results to print");
    _ = l.getGlobal("_old_print") catch unreachable;
    l.insert(1);
    docall(l, n, 0) catch unreachable;
    if (input.readline) {
        _ = c.rl_clear_visible_line();
        _ = c.rl_set_prompt("> ");
        c.rl_already_prompted = 1;
        _ = c.rl_forced_update_display();
    } else {
        stdout.print("> ", .{}) catch unreachable;
    }
    return 0;
}

fn run_code(code: []const u8) !void {
    try dostring(lvm, code, "s_run_code");
}

fn dostring(l: *Lua, str: []const u8, name: [:0]const u8) !void {
    try l.loadBuffer(str, name, ziglua.Mode.text);
    try docall(l, 0, 0);
}

var fallback_allocator = std.heap.stackFallback(8 * 1024, std.heap.raw_c_allocator);
var interpreter_alloc: std.mem.Allocator = undefined;
var save_buf: std.ArrayList(u8) = undefined;

fn message_handler(l: *Lua) i32 {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const msg = l.toString(1) catch unreachable;
            l.pop(1);
            l.traceback(l, msg, 1);
        },
        else => {
            const msg = std.fmt.allocPrintZ(
                allocator,
                "(error object is a {s} value)",
                .{l.typeName(t)},
            ) catch @panic("OOM!");
            l.pop(1);
            l.traceback(l, msg, 1);
        },
    }
    return 1;
}

fn docall(l: *Lua, nargs: i32, nres: i32) !void {
    const base = l.getTop() - nargs;
    l.pushFunction(ziglua.wrap(message_handler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        _ = lua_print(l);
        return;
    };
    l.remove(base);
}

const PromptKind = enum { New, Continue };

fn prompt(comptime kind: PromptKind) !void {
    switch (kind) {
        .New => {
            if (input.readline) {
                _ = c.rl_clear_visible_line();
                _ = c.rl_set_prompt("> ");
                c.rl_already_prompted = 1;
                _ = c.rl_forced_update_display();
            } else {
                try stdout.print("> ", .{});
            }
        },
        .Continue => {
            if (input.readline) {
                _ = c.rl_clear_visible_line();
                _ = c.rl_set_prompt(">... ");
                c.rl_already_prompted = 1;
                _ = c.rl_forced_update_display();
            } else {
                try stdout.print(">... ", .{});
            }
        },
    }
}

fn handle_line(l: *Lua, line: [:0]const u8) !void {
    l.setTop(0);
    _ = l.pushString(line);
    if (save_buf.items.len > 0) {
        if (try statement(l)) {
            l.setTop(0);
            try prompt(.Continue);
            return;
        }
    } else {
        add_return(l) catch |err| {
            if (err == error.Syntax and try statement(l)) {
                l.setTop(0);
                try prompt(.Continue);
                return;
            }
        };
    }
    if (input.readline) {
        _ = c.rl_clear_visible_line();
    }
    try docall(l, 0, ziglua.mult_return);
    if (l.getTop() == 0) {
        try prompt(.New);
    } else {
        _ = lua_print(l);
    }
    l.setTop(0);
}

fn statement(l: *Lua) !bool {
    const line = try l.toString(1);
    if (save_buf.items.len > 0) {
        try save_buf.append('\n');
    }
    try save_buf.appendSlice(line);
    l.loadBuffer(save_buf.items, "=stdin", ziglua.Mode.text) catch |err| {
        if (err != error.Syntax) return err;
        const msg = try l.toString(-1);
        const eofmark = "<eof>";
        if (std.mem.endsWith(u8, msg, eofmark)) {
            l.pop(1);
            return true;
        } else {
            save_buf.clearRetainingCapacity();
            l.remove(-2);
            _ = message_handler(l);
            _ = lua_print(l);
            return false;
        }
    };
    save_buf.clearRetainingCapacity();
    l.remove(1);
    return false;
}

fn add_return(l: *Lua) !void {
    const line = try l.toString(-1);
    const retline = try std.fmt.allocPrint(interpreter_alloc, "return {s}", .{line});
    defer interpreter_alloc.free(retline);
    l.loadBuffer(retline, "=stdin", ziglua.Mode.text) catch |err| {
        l.pop(1);
        return err;
    };
    l.remove(-2);
}
