const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const run_integration_tests = b.option(bool, "run-integration", "Run network integration tests") orelse false;
    const build_info = createBuildInfoOptions(b, run_integration_tests);
    const package_snapshot_step = createPackageSnapshotStep(b);
    const yaml_dep = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    // Library module for external packages
    const openapi2zig_mod = b.addModule("openapi2zig", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    openapi2zig_mod.addIncludePath(b.path("src"));
    openapi2zig_mod.addOptions("build_info", build_info);
    openapi2zig_mod.addImport("yaml", yaml_dep.module("yaml"));

    // CLI executable
    const exe_root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_root_module.addOptions("build_info", build_info);
    exe_root_module.addImport("yaml", yaml_dep.module("yaml"));
    const exe = b.addExecutable(.{
        .name = "openapi2zig",
        .root_module = exe_root_module,
    });
    exe.root_module.addImport("openapi2zig", openapi2zig_mod);
    b.installArtifact(exe);

    // Static library for linking
    const lib_root_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_root_module.addOptions("build_info", build_info);
    lib_root_module.addImport("yaml", yaml_dep.module("yaml"));
    const lib = b.addLibrary(.{
        .name = "openapi2zig",
        .root_module = lib_root_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_generate_v3_cmd = b.addRunArtifact(exe);
    run_generate_v3_cmd.addArgs(&.{
        "generate",
        "-i",
        "openapi/v3.0/petstore.json",
        "-o",
        "generated/generated_v3.zig",
        "--base-url",
        "https://petstore3.swagger.io/api/v3",
    });
    const run_generate_v3_step = b.step("run-generate-v3", "Run the app with generate command");
    run_generate_v3_step.dependOn(&run_generate_v3_cmd.step);

    const run_generate_v2_cmd = b.addRunArtifact(exe);
    run_generate_v2_cmd.addArgs(&.{
        "generate",
        "-i",
        "openapi/v2.0/petstore.json",
        "-o",
        "generated/generated_v2.zig",
        "--base-url",
        "https://petstore.swagger.io/v2",
    });
    const run_generate_v2_step = b.step("run-generate-v2", "Run the app with generate command");
    run_generate_v2_step.dependOn(&run_generate_v2_cmd.step);

    const run_generate_v32_cmd = b.addRunArtifact(exe);
    run_generate_v32_cmd.addArgs(&.{
        "generate",
        "-i",
        "openapi/v3.2/petstore.json",
        "-o",
        "generated/generated_v32.zig",
        "--base-url",
        "https://petstore3.swagger.io/api/v3",
    });
    const run_generate_v32_step = b.step("run-generate-v32", "Run the app with generate command for OpenAPI v3.2");
    run_generate_v32_step.dependOn(&run_generate_v32_cmd.step);

    const run_generate_v31_cmd = b.addRunArtifact(exe);
    run_generate_v31_cmd.addArgs(&.{
        "generate",
        "-i",
        "openapi/v3.1/webhook-example.json",
        "-o",
        "generated/generated_v31.zig",
    });
    const run_generate_v31_step = b.step("run-generate-v31", "Run the app with generate command for OpenAPI v3.1");
    run_generate_v31_step.dependOn(&run_generate_v31_cmd.step);

    const run_generate = b.step("run-generate", "Run the app with generate commands");
    run_generate.dependOn(&run_generate_v3_cmd.step);
    run_generate.dependOn(&run_generate_v2_cmd.step);
    run_generate.dependOn(&run_generate_v32_cmd.step);
    run_generate.dependOn(&run_generate_v31_cmd.step);

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_mod.addOptions("build_info", build_info);
    tests_mod.addImport("yaml", yaml_dep.module("yaml"));

    const exe_unit_tests = b.addTest(.{
        .root_module = tests_mod,
    });
    exe_unit_tests.root_module.addImport("openapi2zig", openapi2zig_mod);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const generated_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated/compile_generated.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_generated_tests = b.addRunArtifact(generated_tests);
    test_step.dependOn(&run_generated_tests.step);

    const test_package_cmd = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    test_package_cmd.step.dependOn(package_snapshot_step);
    test_package_cmd.setCwd(b.path(".zig-cache/package-snapshot/examples/package_consumer"));
    const test_package_step = b.step("test-package", "Build downstream package consumer example");
    test_package_step.dependOn(&test_package_cmd.step);
    test_step.dependOn(&test_package_cmd.step);

    const test_artifact = b.addInstallArtifact(
        exe_unit_tests,
        .{ .dest_dir = .{ .override = .{ .custom = "tests" } } },
    );
    const install_test_step = b.step("install_test", "Create test binaries for debugging");
    install_test_step.dependOn(&test_artifact.step);
}

fn createBuildInfoOptions(b: *std.Build, run_integration_tests: bool) *std.Build.Step.Options {
    const options = b.addOptions();
    const io = b.graph.io;
    const package_version = getPackageVersion(b.allocator, io) orelse "unknown";
    const git_tag = getGitOutput(b.allocator, io, &.{ "git", "describe", "--tags", "--abbrev=0" }) orelse b.fmt("v{s}", .{package_version});
    const git_commit = getGitOutput(b.allocator, io, &.{ "git", "rev-parse", "--short", "HEAD" }) orelse "unknown";
    const version = if (std.mem.startsWith(u8, git_tag, "v")) git_tag[1..] else git_tag;
    const build_date = getBuildDate(b.allocator, io) orelse "unknown";

    options.addOption([]const u8, "VERSION", version);
    options.addOption([]const u8, "GIT_TAG", git_tag);
    options.addOption([]const u8, "GIT_COMMIT", git_commit);
    options.addOption([]const u8, "BUILD_DATE", build_date);
    options.addOption(bool, "RUN_INTEGRATION_TESTS", run_integration_tests);

    return options;
}

fn createPackageSnapshotStep(b: *std.Build) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "prepare-package-snapshot",
        .owner = b,
        .makeFn = makePackageSnapshot,
    });
    return step;
}

fn makePackageSnapshot(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    _ = options;
    const b = step.owner;
    const allocator = b.allocator;
    const io = b.graph.io;
    const cwd = std.Io.Dir.cwd();
    const snapshot_root = ".zig-cache/package-snapshot";

    try cwd.deleteTree(io, snapshot_root);
    try cwd.createDirPath(io, snapshot_root);

    const repo_files = getPackageSnapshotFiles(allocator, io) orelse return error.UnableToPreparePackageSnapshot;
    defer allocator.free(repo_files);

    var lines = std.mem.tokenizeScalar(u8, repo_files, '\n');
    while (lines.next()) |line| {
        const repo_path = std.mem.trimEnd(u8, line, "\r");
        if (repo_path.len == 0) continue;

        const destination_path = try std.fs.path.join(allocator, &.{ snapshot_root, repo_path });
        defer allocator.free(destination_path);

        if (std.fs.path.dirname(destination_path)) |dest_dir| {
            try cwd.createDirPath(io, dest_dir);
        }

        try cwd.copyFile(repo_path, cwd, destination_path, io, .{});
    }
}

fn getBuildDate(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const timestamp = std.Io.Clock.real.now(io).toSeconds();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(timestamp)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    }) catch null;
}

fn getPackageVersion(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const content = std.Io.Dir.cwd().readFileAlloc(io, "build.zig.zon", allocator, .limited(64 * 1024)) catch return null;
    const marker = ".version = \"";
    const start = std.mem.indexOf(u8, content, marker) orelse return null;
    const version_start = start + marker.len;
    const version_end = std.mem.indexOfScalarPos(u8, content, version_start, '"') orelse return null;
    return content[version_start..version_end];
}

fn getPackageSnapshotFiles(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    return getGitOutput(allocator, io, &.{
        "git",
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        "build.zig",
        "build.zig.zon",
        "src",
        "openapi",
        "generated",
        "vendor/zig-yaml",
        "LICENSE",
        "README.md",
        "examples/package_consumer",
    });
}

fn getGitOutput(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) ?[]const u8 {
    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(16 * 1024),
    }) catch return null;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) {
                return std.mem.trim(u8, result.stdout, " \t\n\r");
            } else {
                allocator.free(result.stdout);
                return null;
            }
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }
}
