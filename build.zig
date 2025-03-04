const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "seamstress",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.headerpad_max_install_names = true;

    const install_lua_files = b.addInstallDirectory(.{
        .source_dir = b.path("lua"),
        .install_dir = .{ .custom = "share/seamstress" },
        .install_subdir = "lua",
    });
    const install_resources = b.addInstallDirectory(.{
        .source_dir = b.path("resources"),
        .install_dir = .{ .custom = "share/seamstress" },
        .install_subdir = "resources",
    });
    const install_examples = b.addInstallDirectory(.{
        .source_dir = b.path("examples"),
        .install_dir = .{ .custom = "share/seamstress" },
        .install_subdir = "examples",
    });
    b.getInstallStep().dependOn(&install_resources.step);
    b.getInstallStep().dependOn(&install_lua_files.step);
    b.getInstallStep().dependOn(&install_examples.step);

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");
    exe.linkSystemLibrary("SDL2_ttf");
    const zig_lua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("ziglua", zig_lua.module("ziglua"));
    exe.linkSystemLibrary("lua");

    const zig_link = b.dependency("abl_link", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("abl_link", zig_link.module("zig-abl_link"));
    exe.linkLibrary(zig_link.artifact("abl_link"));

    switch (target.result.os.tag) {
        .macos => {
            exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/readline/lib" });
            // exe.addLibraryPath(.{ .cwd_relative = "/usr/local/opt/readline/lib" });
            exe.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/readline/include" });
            // exe.addSystemIncludePath(.{ .cwd_relative = "/usr/local/opt/readline/include" });
        },
        else => {},
    }
    exe.linkSystemLibrary("readline");
    exe.linkSystemLibrary("lo");
    exe.linkSystemLibrary("rtmidi");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
