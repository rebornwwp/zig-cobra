const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── pflag 依赖 (通过 build.zig.zon) ──
    const pflag_dep = b.dependency("pflag", .{
        .target = target,
        .optimize = optimize,
    });
    const pflag_mod = pflag_dep.module("pflag");

    // ── cobra 库 ──
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/cobra.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pflag", .module = pflag_mod },
        },
    });

    const lib = b.addLibrary(.{
        .name = "cobra",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // ── Demo ──
    const demo_exe = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cobra", .module = lib_mod },
                .{ .name = "pflag", .module = pflag_mod },
            },
        }),
    });
    const install_demo = b.addInstallArtifact(demo_exe, .{});
    b.getInstallStep().dependOn(&install_demo.step);

    const run_demo = b.addRunArtifact(demo_exe);
    run_demo.step.dependOn(&install_demo.step);
    if (b.args) |args| run_demo.addArgs(args);
    const run_demo_step = b.step("run-demo", "Run demo app");
    run_demo_step.dependOn(&run_demo.step);

    // ── Dockr Demo ──
    const dockr_exe = b.addExecutable(.{
        .name = "dockr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/dockr/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cobra", .module = lib_mod },
                .{ .name = "pflag", .module = pflag_mod },
            },
        }),
    });
    const install_dockr = b.addInstallArtifact(dockr_exe, .{});
    b.getInstallStep().dependOn(&install_dockr.step);

    const run_dockr = b.addRunArtifact(dockr_exe);
    run_dockr.step.dependOn(&install_dockr.step);
    if (b.args) |args| run_dockr.addArgs(args);
    const run_dockr_step = b.step("run-dockr", "Run Docker-style demo");
    run_dockr_step.dependOn(&run_dockr.step);

    // ── 测试 ──
    const test_files = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "cobra_test", .path = "src/cobra_test.zig" },
        .{ .name = "command_test", .path = "src/command_test.zig" },
        .{ .name = "args_test", .path = "src/args_test.zig" },
        .{ .name = "completions_test", .path = "src/completions_test.zig" },
        .{ .name = "active_help_test", .path = "src/active_help_test.zig" },
        .{ .name = "flag_groups_test", .path = "src/flag_groups_test.zig" },
    };

    const test_step = b.step("test", "Run library tests");
    inline for (test_files) |tf| {
        const tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(tf.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "pflag", .module = pflag_mod },
                },
            }),
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }
}
