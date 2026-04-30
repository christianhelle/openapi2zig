const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yaml_module = b.addModule("yaml", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const yaml_tests = b.addTest(.{
        .root_module = yaml_module,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(yaml_tests).step);
}
