pub fn register(comptime which: enum { osc, server, client, message }) fn (*Lua) i32 {
    return switch (which) {
        .osc => struct {
            fn f(l: *Lua) i32 {
                l.createTable(0, 3);
                lu.load(l, "seamstress.osc.Client") catch unreachable;
                l.setField(-2, "Client");
                lu.load(l, "seamstress.osc.Server") catch unreachable;
                l.setField(-2, "Server");
                lu.load(l, "seamstress.osc.Message") catch unreachable;
                l.setField(-2, "Message");
                return 1;
            }
        }.f,
        .server => @import("osc/server.zig").register,
        .client => @import("osc/client.zig").register,
        .message => @import("osc/message.zig").register,
    };
}

/// stack effect: pushes one object, the address, onto the stack
pub fn pushAddress(l: *Lua, comptime mode: enum { array, table, string }, addr: std.net.Address) void {
    var counter = std.io.countingWriter(std.io.null_writer);
    addr.format("", .{}, counter.writer()) catch unreachable;
    const size: usize = @intCast(counter.bytes_written);
    var buf: ziglua.Buffer = undefined;
    const slice = buf.initSize(l, @intCast(size));
    var fbs = std.io.fixedBufferStream(slice);
    addr.format("", .{}, fbs.writer()) catch unreachable;
    switch (mode) {
        .string => buf.pushResultSize(@intCast(size)),
        .array, .table => {
            const colon_idx = std.mem.indexOfScalar(u8, slice, ':').?;
            const port = std.fmt.parseInt(ziglua.Integer, slice[colon_idx + 1 .. size], 10) catch unreachable;
            buf.pushResultSize(colon_idx);
            l.createTable(2, 0);
            l.rotate(-2, 1);
            l.pushInteger(port);
            if (mode == .array) {
                l.setIndex(-3, 2);
                l.setIndex(-2, 1);
            } else {
                l.setField(-3, "port");
                l.setField(-2, "host");
            }
        },
    }
}

/// attempts to parse the argument at the given index into a std.net.Address
/// stack is unchanged at the end of this operation
/// behavior:
/// if typeOf(index) == .number, it is treated as the port number
/// if typeOf(index) == .string, it is parsed by zig
/// if typeOf(index) == .table, it should either be of the form {host, port} or { host = host, port = port }
pub fn parseAddress(l: *Lua, index: i32) !std.net.Address {
    const top = if (builtin.mode == .Debug) l.getTop();
    defer if (builtin.mode == .Debug) std.debug.assert(l.getTop() == top);
    return switch (l.typeOf(index)) {
        .number => port: {
            const integer = try l.toInteger(index);
            break :port std.net.Address.initIp4(.{ 127, 0, 0, 1 }, std.math.cast(u16, integer) orelse return error.BadPort);
        },
        .string => parse: {
            const path = l.toString(index) catch unreachable;
            break :parse std.net.Address.initUnix(path);
        },
        .table => table: {
            switch (l.getIndex(index, 1)) {
                .string => {
                    const path = l.toString(-1) catch unreachable;
                    l.pop(1);
                    _ = l.getIndex(index, 2);
                    defer l.pop(1);
                    const integer = try l.toInteger(-1);
                    break :table std.net.Address.parseIp(path, std.math.cast(u16, integer) orelse return error.BadPort);
                },
                .nil, .none => {
                    l.pop(1);
                    _ = l.getField(index, "host");
                    _ = l.getField(index, "port");
                    defer l.pop(2);
                    const host = try l.toString(-2);
                    const integer = try l.toInteger(-1);
                    break :table std.net.Address.parseIp(host, std.math.cast(u16, integer) orelse return error.BadPort);
                },
                else => break :table error.BadType,
            }
        },
        else => error.BadType,
    };
}

pub fn prepare(allocator: std.mem.Allocator, args: anytype) !z.Message.Builder {
    var builder = z.Message.Builder.init(allocator);
    errdefer builder.deinit();

    const info = @typeInfo(@TypeOf(args)).Struct;
    comptime std.debug.assert(info.is_tuple);

    inline for (info.fields, 0..) |field, i| {
        const field_info = @typeInfo(field.type);
        switch (field_info) {
            .Int, .ComptimeInt => try builder.append(.{ .i = args[i] }),
            .Float, .ComptimeFloat => try builder.append(.{ .f = args[i] }),
            .Pointer => try builder.append(.{ .s = args[i] }),
            .Bool => try builder.append(if (args[i]) .T else .F),
            .Null => try builder.append(.N),
            .EnumLiteral => try builder.append(.I),
            else => try builder.append(args[i]),
        }
    }

    return builder;
}

/// creates a "seamstress.osc.Method" closure, consuming num_upvalues from the top of the stack
/// this is a convenience function
/// allowing Zig-defined OSC handlers to not pay the cost of creating a seamstress.osc.Message
/// zigFn should be a function of type fn (*Lua, std.net.Address, path, ...) z.Continue;
pub fn wrap(l: *Lua, comptime arg_types: []const u8, zigFn: anytype, num_upvalues: i32) void {
    const wrapped = struct {
        fn wrapped(lua: *Lua) i32 {
            const bytes = lua.checkString(2);
            const addr = parseAddress(lua, 3) catch lua.typeError(3, "address");
            var parsed = z.parseOSC(bytes) catch lua.typeError(2, "seamstress.osc.Message");
            const ret: z.Continue = switch (parsed) {
                .bundle => lua.raiseError(),
                .message => |*iter| ret: {
                    if (!z.matchTypes(arg_types, iter.types)) {
                        lua.raiseErrorStr("unexpected types for path %s: %s!", .{ iter.path.ptr, iter.types.ptr });
                    }
                    const tuple = iter.unpack(arg_types) catch
                        lua.raiseErrorStr("bad OSC data!", .{});
                    break :ret @call(.always_inline, zigFn, .{ lua, addr, iter.path } ++ tuple);
                },
            };
            lua.pushBoolean(switch (ret) {
                .yes => true,
                .no => false,
            });
            return 1;
        }
    }.wrapped;
    l.pushClosure(ziglua.wrap(wrapped), num_upvalues);
    l.newTable();
    l.createTable(0, 3);
    l.rotate(-3, -1);
    _ = l.pushStringZ("__call");
    l.rotate(-2, 1);
    l.setTable(-3);
    _ = l.pushStringZ("__name");
    _ = l.pushStringZ("seamstress.osc.Method");
    l.setTable(-3);
    // l.pushValue(-1);
    // _ = l.pushStringZ("__index");
    // l.setTable(-3);
    l.setMetatable(-2);
}

pub const ClientZigFn = fn (l: *Lua, handle: i32, message: *z.Parse.MessageIterator) z.Continue;

/// stack effect: adds one (the message)
pub fn pushMessage(l: *Lua, message: *z.Parse.MessageIterator) !void {
    lu.load(l, "seamstress.osc.Message") catch unreachable;
    l.createTable(@intCast(message.types.len), 2);
    errdefer l.pop(1);
    _ = l.pushString(message.path);
    _ = l.pushString(message.types);
    l.setField(-3, "types");
    l.setField(-2, "path");
    var idx: i32 = 1;
    while (try message.next()) |data| : (idx += 1) {
        pushData(l, data);
        l.setIndex(-2, idx);
    }
}

/// pushes the datum onto the stack, adding one to the top of the stack
pub fn pushData(l: *Lua, data: z.Data) void {
    switch (data) {
        .i, .h => |i| l.pushInteger(i),
        .f, .d => |f| l.pushNumber(f),
        .r => |r| {
            var buf: ziglua.Buffer = undefined;
            const slice = buf.initSize(l, 9);
            _ = std.fmt.bufPrint(slice, "#{x}", .{r}) catch unreachable;
            buf.pushResultSize(9);
        },
        .t => |t| {
            l.createTable(2, 0);
            l.pushInteger(t.seconds);
            l.pushInteger(t.frac);
            l.setIndex(-3, 2);
            l.setIndex(-2, 1);
        },
        .s, .S, .b => |bytes| _ = l.pushString(bytes),
        .F, .T => l.pushBoolean(data == .T),
        .N, .I => l.pushNil(),
        .c => |c| _ = l.pushString(&.{c}),
        .m => |m| _ = l.pushString(&m),
    }
}

pub fn toData(l: *Lua, tag: ?u8) !z.Data {
    if (l.getTop() == 0) l.raiseErrorStr("no item to read!", .{});
    return if (tag) |byte| switch (byte) {
        inline 'f', 'd' => |which| ret: {
            const t = l.typeOf(-1);
            if (t != .number) return error.TypeMismatch;
            const number = l.toNumber(-1) catch unreachable;
            break :ret @unionInit(z.Data, &.{which}, @floatCast(number));
        },
        inline 'i', 'h' => |which| ret: {
            const t = l.typeOf(-1);
            if (t != .number or !l.isInteger(-1)) return error.TypeMismatch;
            const integer = l.toInteger(-1) catch unreachable;
            break :ret @unionInit(z.Data, &.{which}, if (which == 'i')
                std.math.cast(i32, integer) orelse return error.BadIntegerValue
            else
                integer);
        },
        'T', 'F' => if (byte == 'T') .T else .F,
        'N', 'I' => if (byte == 'N') .N else .I,
        inline 'm', 'c', 's', 'S', 'b' => |which| ret: {
            const t = l.typeOf(-1);
            if (t != .string) return error.TypeMismatch;
            const str = l.toString(-1) catch unreachable;
            break :ret if (which == 'c')
                .{ .c = str[0] }
            else if (which == 'm') blk: {
                var midi: [4]u8 = .{ 0, 0, 0, 0 };
                const len = @min(midi.len, str.len);
                @memcpy(midi[0..len], str[0..len]);
                break :blk .{ .m = midi };
            } else @unionInit(z.Data, &.{which}, str);
        },
        'r' => ret: {
            const str = l.toStringEx(-1);
            if (str.len < 9) return error.TypeMismatch;
            const @"u32" = std.fmt.parseInt(u32, str[1..9], 16) catch return error.TypeMismatch;
            break :ret .{ .r = @"u32" };
        },
        't' => ret: {
            const t = l.typeOf(-1);
            if (t != .table) return error.TypeMismatch;
            defer l.pop(1);
            if (l.getIndex(-1, 1) != .number) return error.TypeMismatch;
            defer l.pop(1);
            if (l.getIndex(-2, 2) != .number) return error.TypeMismatch;
            if (!l.isInteger(-1) or !l.isInteger(-2)) return error.TypeMismatch;
            break :ret .{ .t = .{
                .frac = std.math.cast(u32, l.toInteger(-1) catch unreachable) orelse return error.BadIntegerValue,
                .seconds = std.math.cast(u32, l.toInteger(-2) catch unreachable) orelse return error.BadIntegerValue,
            } };
        },
        else => error.BadTag,
    } else switch (l.typeOf(-1)) {
        .number => if (l.isInteger(-1)) .{
            .i = std.math.cast(i32, l.toInteger(-1) catch unreachable) orelse return error.BadIntegerValue,
        } else .{
            .f = @floatCast(l.toNumber(-1) catch unreachable),
        },
        .string => .{ .s = l.toString(-1) catch unreachable },
        .boolean => if (l.toBoolean(-1)) .T else .F,
        .nil => .N,
        .table => ret: {
            defer l.pop(1);
            if (l.getIndex(-1, 1) != .string) return error.BadOSCArgument;
            const type_str = l.toString(-1) catch unreachable;
            _ = l.getIndex(-2, 2);
            break :ret try toData(l, type_str[0]);
        },
        else => error.TypeMismatch,
    };
}

pub const Server = @import("osc/server.zig");
pub const Client = @import("osc/client.zig");
pub const z = @import("zosc");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("lua_util.zig");
const xev = @import("xev");
const std = @import("std");
const builtin = @import("builtin");
