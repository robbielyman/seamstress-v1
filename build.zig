const std = @import("std");
const ziglua = @import("lib/ziglua/build.zig");

pub fn build(b: *std.Build) void {
    b.install_prefix = "/usr/local";
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "seamstress",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (target.isDarwin()) {
        exe.addIncludePath("/opt/homebrew/include");
        exe.addIncludePath("/opt/homebrew/opt/readline/include");
        exe.addLibraryPath("/opt/homebrew/lib");
        exe.addLibraryPath("/opt/homebrew/opt/readline/lib");
    }

    b.installArtifact(exe);
    const install_lua_files = b.addInstallDirectory(.{
        .source_dir = "lua",
        .install_dir = .{ .custom = "share/seamstress" },
        .install_subdir = "lua",
    });
    const install_font = b.addInstallFileWithDir(
        std.Build.FileSource.relative("resources/04b03.ttf"),
        .{ .custom = "share/seamstress" },
        "resources/04b03.ttf",
    );
    b.getInstallStep().dependOn(&install_font.step);
    b.getInstallStep().dependOn(&install_lua_files.step);

    // if (target.isLinux()) {
    //     exe.linkSystemLibrary("dns_sd");
    // }
    exe.linkSystemLibrary("LIBLO");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_ttf");
    exe.linkSystemLibrary("rtmidi");
    exe.linkSystemLibrary("readline");
    exe.addModule("ziglua", ziglua.compileAndCreateModule(b, exe, .{}));
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
