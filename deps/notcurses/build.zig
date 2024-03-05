const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const static = b.option(bool, "static", "build a (minimal) static notcurses") orelse false;

    const module = b.addModule("notcurses", .{
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const test_exe = b.addExecutable(.{
        .root_source_file = .{ .path = "test.zig" },
        .target = target,
        .optimize = optimize,
        .name = "notcurses-core-tests",
        .link_libc = true,
    });

    if (static) {
        const lib = try compileNotcurses(b, target, optimize);
        b.installArtifact(lib);
        tests.linkLibrary(lib);
        test_exe.linkLibrary(lib);
        module.linkLibrary(lib);
    } else {
        tests.linkSystemLibrary("notcurses-core");
        test_exe.linkSystemLibrary("notcurses-core");
        module.linkSystemLibrary("notcurses-core", .{
            .needed = true,
        });
    }

    const tests_run_step = b.addRunArtifact(tests);
    const test_exe_install_step = b.addInstallArtifact(test_exe, .{});
    const test_exe_run_step = b.addRunArtifact(test_exe);
    test_exe_run_step.step.dependOn(&test_exe_install_step.step);
    const tests_step = b.step("test", "run the tests");
    tests_step.dependOn(&tests_run_step.step);
    tests_step.dependOn(&test_exe_run_step.step);
}

fn compileNotcurses(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    if (true) return error.NotImplemented;

    const upstream = b.dependency("upstream", .{});
    _ = upstream; // autofix

    const lib = b.addStaticLibrary(.{
        .link_libc = true,
        .name = "notcurses",
        .target = target,
        .optimize = optimize,
    });
    return lib;
}
