pub fn register(l: *Lua) i32 {
    l.pushFunction(ziglua.wrap(repl));
    return 1;
}

fn repl(l: *Lua) i32 {
    const input = l.checkString(1);
    const top = l.getTop();
    return switch (processChunk(l, input) catch l.raiseError()) {
        .ok => l.getTop() - top,
        .incomplete => 1,
    };
}

/// processes the buffer as plaintext Lua code
/// stack effect: essentially arbitrary: usually you should subsequently call `print`
fn processChunk(l: *Lua, buffer: []const u8) !enum { ok, incomplete } {
    lu.format(l, "return {s}", .{buffer});
    const with_return = l.toString(-1) catch unreachable;
    l.pop(1);
    // loads the chunk...
    l.loadBuffer(with_return, "=repl", .text) catch |err| {
        // ... if the chunk does not compile
        switch (err) {
            error.Memory => return error.OutOfMemory,
            error.Syntax => {
                // remove the error message
                l.pop(1);
                // load the original buffer
                l.loadBuffer(buffer, "=repl", .text) catch |err2| switch (err2) {
                    error.Memory => return error.OutOfMemory,
                    error.Syntax => {
                        const msg = l.toStringEx(-1);
                        // does the syntax error tell us the statement isn't finished?
                        if (std.mem.endsWith(u8, msg, "<eof>")) {
                            return .incomplete;
                        } else {
                            // return an error to signal the syntax error
                            return error.LuaSyntaxError;
                        }
                    },
                };
            },
        }
        // call the compiled function
        try lu.doCall(l, 0, ziglua.mult_return);
        return .ok;
    };
    // ... the chunk compiles fine with "return " added!
    // call the compiled function
    try lu.doCall(l, 0, ziglua.mult_return);
    return .ok;
}

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const lu = @import("lua_util.zig");
const std = @import("std");
