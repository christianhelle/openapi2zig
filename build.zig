const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Generate version information at build time
    const version_step = generateVersionStep(b);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "openapi2zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Generate version info before building
    exe.step.dependOn(version_step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_generate_cmd = b.addRunArtifact(exe);
    run_generate_cmd.addArgs(&.{
        "generate",
        "-i",
        "openapi/v3.0/petstore.json",
        "-o",
        "test/generated.zig",
        "--base-url",
        "https://petstore.swagger.io/api/v3",
    });
    const run_generate_step = b.step("run-generate", "Run the app with generate command");
    run_generate_step.dependOn(&run_generate_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    //
    //
    // We will also create a module for our other entry point, 'main.zig'.
    const tests_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_unit_tests = b.addTest(.{
        .root_module = tests_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
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

    // Get git information at build time (simplified for reliability)
    const git_tag = getGitOutput(allocator, &.{ "git", "describe", "--tags", "--abbrev=0" }) orelse "unknown";
    const git_commit = getGitOutput(allocator, &.{ "git", "rev-parse", "--short", "HEAD" }) orelse "unknown";

    // Parse version from git tag (remove 'v' prefix if present)
    const version = if (std.mem.startsWith(u8, git_tag, "v"))
        git_tag[1..]
    else
        git_tag;

    // Get current timestamp and format it nicely
    const timestamp = std.time.timestamp();
    const seconds_since_epoch = @as(u64, @intCast(timestamp));

    // Format date as close to the original as possible
    const days_since_epoch = seconds_since_epoch / (24 * 3600);
    const seconds_today = seconds_since_epoch % (24 * 3600);

    // Approximate date calculation (good enough for build timestamps)
    const years_since_1970 = days_since_epoch / 365;
    const year = 1970 + years_since_1970;
    const day_of_year = days_since_epoch % 365;
    const month = 1 + (day_of_year / 30); // Rough approximation
    const day = 1 + (day_of_year % 30);

    const hour = seconds_today / 3600;
    const minute = (seconds_today % 3600) / 60;
    const second = seconds_today % 60;

    var date_buf: [64]u8 = undefined;
    const build_date = std.fmt.bufPrint(&date_buf, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{ year, month, day, hour, minute, second }) catch "unknown";

    // Generate version_info.zig content
    const content = std.fmt.allocPrint(allocator,
        \\// This file is auto-generated at build time
        \\pub const VERSION = "{s}";
        \\pub const GIT_TAG = "{s}";
        \\pub const GIT_COMMIT = "{s}";
        \\pub const BUILD_DATE = "{s}";
        \\
    , .{ version, git_tag, git_commit, build_date }) catch @panic("OOM");

    // Write directly to the src directory
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
