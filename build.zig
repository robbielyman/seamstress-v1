const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .root_source_file = b.path("src/main.zig"),
        .name = "seamstress",
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.linkLibC();

    const lua_install = b.addInstallDirectory(.{
        .include_extensions = &.{".lua"},
        .install_dir = .{ .custom = "share" },
        .install_subdir = "seamstress/lua",
        .source_dir = b.path("lua"),
    });
    b.getInstallStep().dependOn(&lua_install.step);

    try addDependencies(&exe.root_module, b, target, optimize);

    const run_artifact = b.addRunArtifact(exe);
    run_artifact.step.dependOn(b.getInstallStep());
    run_artifact.addArgs(b.args orelse &.{});

    const run_step = b.step("run", "run seamstress");
    run_step.dependOn(&run_artifact.step);

    const tests_step = b.step("test", "run seamstress tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    try addDependencies(&tests.root_module, b, target, optimize);

    const run_tests = b.addRunArtifact(tests);
    tests_step.dependOn(&run_tests.step);
}

fn addDependencies(m: *std.Build.Module, b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
        .lang = .lua54,
    });
    m.addImport("ziglua", ziglua.module("ziglua"));
    m.linkSystemLibrary("lua", .{ .needed = true });

    const vaxis = b.dependency("libvaxis", .{
        .target = target,
        .optimize = optimize,
    });
    m.addImport("vaxis", vaxis.module("vaxis"));

    const gap_buffer = b.dependency("gap_buffer", .{
        .target = target,
        .optimize = optimize,
    });
    m.addImport("gap_buffer", gap_buffer.module("gap_buffer"));

    const ziglo = b.dependency("ziglo", .{
        .target = target,
        .optimize = optimize,
    });
    m.addImport("ziglo", ziglo.module("ziglo"));

    const ziglink = b.dependency("zig-abl_link", .{
        .target = target,
        .optimize = optimize,
    });
    m.addImport("link", ziglink.module("zig-abl_link"));

    const rtmidi_z = b.dependency("rtmidi_z", .{
        .target = target,
        .optimize = optimize,
    });
    m.addImport("rtmidi", rtmidi_z.module("rtmidi_z"));
}
