const std = @import("std");
const args = @import("args.zig");
const c = @import("input.zig").c;

var allocator: std.mem.Allocator = undefined;
var location: []const u8 = undefined;
var to_be_freed: ?[]const u8 = null;

pub fn init(option: args.CreateOptions, alloc: std.mem.Allocator, loc: []const u8) !void {
    allocator = alloc;
    location = loc;
    _ = c.rl_initialize();
    c.rl_prep_terminal(1);
    defer _ = c.rl_reset_terminal(null);
    switch (option) {
        .script => try script(),
        .project => try project(false),
        .norns_project => try project(true),
    }
}

fn script() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        std.debug.print("unable to capture $HOME! exiting\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(home);
    try stdout.print("welcome to SEAMSTRESS\n", .{});
    try stdout.print("creating a script in ~/seamstress; let's name it\n", .{});
    try bw.flush();
    const c_line = c.readline("[default 'script'] > ");
    var name = std.fmt.allocPrint(
        allocator,
        "{s}",
        .{c_line},
    ) catch @panic("OOM!");
    if (name.len == 0) {
        allocator.free(name);
        name = allocator.dupe(u8, "script") catch @panic("OOM!");
    }
    to_be_freed = name;
    c.free(c_line);
    const suffix = ".lua";
    if (std.mem.endsWith(u8, name, suffix)) {
        name = name[0 .. name.len - suffix.len];
    }
    defer args.script_file = name;
    const seamstress_home = std.fmt.allocPrint(allocator, "{s}/seamstress", .{home}) catch @panic("OOM!");
    defer allocator.free(seamstress_home);
    std.fs.makeDirAbsolute(seamstress_home) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("error making ~/seamstress! exiting\n", .{});
            std.process.exit(1);
        }
    };
    const with_dot_lua = std.fmt.allocPrint(allocator, "{s}.lua", .{name}) catch @panic("OOM!");
    defer allocator.free(with_dot_lua);
    const new_script_path = std.fs.path.join(
        allocator,
        &.{ seamstress_home, with_dot_lua },
    ) catch @panic("OOM!");
    var try_again = false;

    var new_script_file = std.fs.createFileAbsolute(
        new_script_path,
        .{ .exclusive = true },
    ) catch |err| blk: {
        if (err != error.PathAlreadyExists) {
            std.debug.print("error creating file! exiting\n", .{});
            std.process.exit(1);
        }
        try_again = true;
        break :blk @as(std.fs.File, undefined);
    };

    if (try_again) {
        try stdout.print("a file with that name already exists! overwrite it?\n", .{});
        try bw.flush();
        var c_confirm = c.readline("['yes' to overwrite] > ");
        const c_slice = std.mem.span(c_confirm);
        if (!std.mem.eql(u8, c_slice, "yes")) {
            try stdout.print("did not receive 'yes': goodbye!\n", .{});
            try bw.flush();
            std.process.exit(0);
        }
        new_script_file = std.fs.createFileAbsolute(
            new_script_path,
            .{ .truncate = true },
        ) catch {
            std.debug.print("error creating file! exiting\n", .{});
            std.process.exit(1);
        };
    }
    new_script_file.close();
    const template_file_path = std.fs.path.join(
        allocator,
        &.{ location, "..", "share", "seamstress", "resources", "script.lua" },
    ) catch @panic("OOM!");
    std.fs.copyFileAbsolute(template_file_path, new_script_path, .{}) catch {
        std.debug.print("error copying file! exiting\n", .{});
        std.process.exit(1);
    };
    try stdout.print("seamstress will now restart, loading your new script!\n", .{});
    try stdout.print("bye for now!\n", .{});
    try bw.flush();
    args.watch = true;
}

fn project(is_norns: bool) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        std.debug.print("unable to capture $HOME! exiting\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(home);
    try stdout.print("welcome to SEAMSTRESS\n", .{});
    try stdout.print("creating a new project; let's choose a name for the folder to put it in\n", .{});
    try bw.flush();
    const c_line = c.readline("[default 'my-project'] > ");
    var name = std.fmt.allocPrint(
        allocator,
        "{s}",
        .{c_line},
    ) catch @panic("OOM!");
    c.free(c_line);
    if (name.len == 0) {
        allocator.free(name);
        name = allocator.dupe(u8, "my-project") catch @panic("OOM!");
    }
    defer allocator.free(name);
    const prefix = "~/";
    const project_name = get_project_name(name);
    const project_path = blk: {
        if (std.mem.startsWith(u8, name, prefix)) {
            break :blk std.fs.path.join(allocator, &.{ home, name[2..name.len] }) catch @panic("OOM!");
        } else {
            break :blk allocator.dupe(u8, name) catch @panic("OOM!");
        }
    };
    defer allocator.free(project_path);
    const cwd = std.fs.cwd();
    cwd.makeDir(project_path) catch |err| {
        std.debug.print("error making directory! ", .{});
        if (err == error.PathAlreadyExists) {
            std.debug.print("directory already exists! ", .{});
        }
        std.debug.print("exiting\n", .{});
        std.process.exit(1);
    };
    const project_dir = cwd.openDir(project_path, .{}) catch {
        std.debug.print("unable to open directory! exiting\n", .{});
        std.process.exit(1);
    };

    project_dir.setAsCwd() catch {
        std.debug.print("unable to entor directory! exiting\n", .{});
        std.process.exit(1);
    };
    var git_init = std.process.Child.init(&.{ "git", "init" }, allocator);
    _ = git_init.spawnAndWait() catch {
        std.debug.print("error calling git init; maybe you don't have it installed?\n", .{});
    };

    const filename = blk: {
        if (is_norns) {
            // have to do a little fancy footwork to divine the name of the script.
            const filename = std.fmt.allocPrint(allocator, "{s}.lua", .{project_name}) catch @panic("OOM!");
            const file = project_dir.createFile(filename, .{}) catch {
                std.debug.print("error creating {s}! exiting\n", .{filename});
                std.process.exit(1);
            };
            file.close();
            break :blk filename;
        } else {
            const file = project_dir.createFile("script.lua", .{}) catch {
                std.debug.print("error creating script.lua! exiting\n", .{});
                std.process.exit(1);
            };
            file.close();
            break :blk "script.lua";
        }
    };
    defer if (is_norns) allocator.free(filename);
    const full_path = std.fs.realpathAlloc(allocator, filename) catch @panic("OOM!");
    defer allocator.free(full_path);
    const template_file_path = std.fs.path.join(
        allocator,
        &.{ location, "..", "share", "seamstress", "resources", if (is_norns) "norns.lua" else "script.lua" },
    ) catch @panic("OOM!");
    defer allocator.free(template_file_path);
    std.fs.copyFileAbsolute(template_file_path, full_path, .{}) catch {
        std.debug.print("error copying file! exiting\n", .{});
        std.process.exit(1);
    };

    if (is_norns) {
        try stdout.print("seamstress will now exit\n", .{});
        try stdout.print("bye for now!\n", .{});
        try bw.flush();
        std.process.exit(0);
    }

    var success = false;
    blk: {
        const file = project_dir.createFile(".luarc.json", .{}) catch break :blk;
        defer file.close();
        const lua_files = std.fs.path.join(allocator, &.{ location, "..", "share", "seamstress", "lua" }) catch break :blk;
        defer allocator.free(lua_files);
        const real_lua_files = std.fs.realpathAlloc(allocator, lua_files) catch @panic("OOM!");
        defer allocator.free(real_lua_files);
        std.json.stringify(.{
            .diagnostics = .{
                .globals = .{"_seamstress"},
                .disable = .{"lowercase-global"},
            },
            .workspace = .{
                .library = .{real_lua_files},
            },
        }, .{}, file.writer()) catch break :blk;
        success = true;
    }
    if (!success) std.debug.print("unable to create .luarc.json!\n", .{});

    try stdout.print("seamstress will now restart, loading your new script!\n", .{});
    try stdout.print("bye for now!\n", .{});
    try bw.flush();
    args.watch = true;
}

fn get_project_name(name: []const u8) []const u8 {
    const lastslash = std.mem.lastIndexOf(u8, name, "/");
    if (lastslash) |l| return name[l + 1 .. name.len];
    return name;
}

pub fn deinit() void {
    if (to_be_freed) |mem| allocator.free(mem);
}
