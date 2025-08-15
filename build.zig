const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version_step = generateVersionStep(b);

    // Library module for external packages
    const openapi2zig_mod = b.addModule("openapi2zig", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    openapi2zig_mod.addIncludePath(b.path("src"));

    // CLI executable
    const exe = b.addExecutable(.{
        .name = "openapi2zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.step.dependOn(version_step);
    exe.root_module.addImport("openapi2zig", openapi2zig_mod);
    b.installArtifact(exe);

    // Static library for linking
    const lib = b.addStaticLibrary(.{
        .name = "openapi2zig",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.step.dependOn(version_step);
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
        "https://petstore.swagger.io/api/v3",
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
        "https://petstore.swagger.io/api/v2",
    });
    const run_generate_v2_step = b.step("run-generate-v2", "Run the app with generate command");
    run_generate_v2_step.dependOn(&run_generate_v2_cmd.step);

    const run_generate = b.step("run-generate", "Run the app with generate commands");
    run_generate.dependOn(&run_generate_v3_cmd.step);
    run_generate.dependOn(&run_generate_v2_cmd.step);

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_unit_tests = b.addTest(.{
        .root_module = tests_mod,
    });
    exe_unit_tests.step.dependOn(version_step);
    exe_unit_tests.root_module.addImport("openapi2zig", openapi2zig_mod);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const test_artifact = b.addInstallArtifact(
        exe_unit_tests,
        .{ .dest_dir = .{ .override = .{ .custom = "tests" } } },
    );
    const install_test_step = b.step("install_test", "Create test binaries for debugging");
    install_test_step.dependOn(&test_artifact.step);
}

fn generateVersionStep(b: *std.Build) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "generate-version-info",
        .owner = b,
        .makeFn = makeVersionInfo,
    });
    return step;
}

fn makeVersionInfo(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    _ = options;
    const b = step.owner;
    const allocator = b.allocator;
    const git_tag = getGitOutput(allocator, &.{ "git", "describe", "--tags", "--abbrev=0" }) orelse "unknown";
    const git_commit = getGitOutput(allocator, &.{ "git", "rev-parse", "--short", "HEAD" }) orelse "unknown";
    const version = if (std.mem.startsWith(u8, git_tag, "v")) git_tag[1..] else git_tag;
    const timestamp = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(timestamp)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    var date_buf: [64]u8 = undefined;
    const build_date = std.fmt.bufPrint(&date_buf, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1, day_seconds.getHoursIntoDay(), day_seconds.getMinutesIntoHour(), day_seconds.getSecondsIntoMinute() }) catch "unknown";
    const content = std.fmt.allocPrint(allocator,
        \\pub const VERSION = "{s}";
        \\pub const GIT_TAG = "{s}";
        \\pub const GIT_COMMIT = "{s}";
        \\pub const BUILD_DATE = "{s}";
        \\
    , .{ version, git_tag, git_commit, build_date }) catch @panic("OOM");
    const file_path = "src/version_info.zig";
    std.fs.cwd().writeFile(.{ .sub_path = file_path, .data = content }) catch |err| {
        std.log.err("Failed to write version_info.zig: {}", .{err});
        return;
    };
    std.log.info("Generated version info: {s} ({s} - {s})", .{ version, git_tag, git_commit });
}

fn getGitOutput(allocator: std.mem.Allocator, argv: []const []const u8) ?[]const u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.spawn() catch return null;
    const stdout = child.stdout.?.readToEndAlloc(allocator, 1024) catch return null;
    const stderr = child.stderr.?.readToEndAlloc(allocator, 1024) catch {
        allocator.free(stdout);
        return null;
    };
    defer allocator.free(stderr);
    const term = child.wait() catch {
        allocator.free(stdout);
        return null;
    };
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                return std.mem.trim(u8, stdout, " \t\n\r");
            } else {
                allocator.free(stdout);
                return null;
            }
        },
        else => {
            allocator.free(stdout);
            return null;
        },
    }
}
