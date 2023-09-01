const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "seamstress",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const install_lua_files = b.addInstallDirectory(.{
        .source_dir = .{ .path = "lua" },
        .install_dir = .{ .custom = "share/seamstress" },
        .install_subdir = "lua",
    });
    const install_resources = b.addInstallDirectory(.{
        .source_dir = .{ .path = "resources" },
        .install_dir = .{ .custom = "share/seamstress" },
        .install_subdir = "resources",
    });
    b.getInstallStep().dependOn(&install_resources.step);
    b.getInstallStep().dependOn(&install_lua_files.step);

    const zig_sdl = b.dependency("SDL", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(zig_sdl.artifact("SDL2"));
    exe.linkLibrary(zig_sdl.artifact("SDL2_ttf"));
    exe.linkLibrary(zig_sdl.artifact("SDL_image"));

    const zig_lua = b.dependency("Lua", .{
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("ziglua", zig_lua.module("ziglua"));
    exe.linkLibrary(zig_lua.artifact("lua"));

    const zig_readline = b.dependency("readline", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(zig_readline.artifact("readline"));
    exe.linkSystemLibrary("ncurses");

    const zig_liblo = b.dependency("liblo", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(zig_liblo.artifact("liblo"));

    const zig_rtmidi = b.dependency("rtmidi", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(zig_rtmidi.artifact("rtmidi"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
