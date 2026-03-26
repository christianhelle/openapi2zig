const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const openapi2zig_dep = b.dependency("openapi2zig", .{
        .target = target,
        .optimize = optimize,
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "package_consumer",
        .root_module = root_module,
    });

    exe.root_module.addImport("openapi2zig", openapi2zig_dep.module("openapi2zig"));
    b.installArtifact(exe);
}
