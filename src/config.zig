const Config = @This();

tui: bool,

// eats a Config struct to populate the list of modules
pub fn consume(config: Config, seamstress: *Seamstress) Error!void {
    _ = config; // autofix
    // const tui_module = if (config.tui) @import("tui.zig").module() else @import("cli.zig").module();
    // try seamstress.modules.append(seamstress.allocator, tui_module);
    try seamstress.modules.append(seamstress.allocator, @import("osc.zig").module());
    // try seamstress.modules.append(seamstress.allocator, @import("metros.zig").module());
}

const Seamstress = @import("seamstress.zig");
const Error = Seamstress.Error;
