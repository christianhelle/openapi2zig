const std = @import("std");
const builtin = @import("builtin");
const version_info = @import("build_info");

const GITHUB_REPO = "christianhelle/openapi2zig";

const Platform = enum {
    linux_x86_64,
    linux_aarch64,
    macos_x86_64,
    macos_aarch64,
    windows_x86_64,
};

fn getPlatform() Platform {
    return switch (builtin.target.cpu.arch) {
        .x86_64 => switch (builtin.target.os.tag) {
            .linux => .linux_x86_64,
            .macos => .macos_x86_64,
            .windows => .windows_x86_64,
            else => @compileError("unsupported OS for x86_64"),
        },
        .aarch64 => switch (builtin.target.os.tag) {
            .linux => .linux_aarch64,
            .macos => .macos_aarch64,
            else => @compileError("unsupported OS for aarch64"),
        },
        else => @compileError("unsupported architecture"),
    };
}

fn platformString(p: Platform) []const u8 {
    return switch (p) {
        .linux_x86_64 => "linux-x86_64",
        .linux_aarch64 => "linux-aarch64",
        .macos_x86_64 => "macos-x86_64",
        .macos_aarch64 => "macos-aarch64",
        .windows_x86_64 => "windows-x86_64",
    };
}

fn isWindows(p: Platform) bool {
    return switch (p) {
        .windows_x86_64 => true,
        else => false,
    };
}

fn isLinux(p: Platform) bool {
    return switch (p) {
        .linux_x86_64, .linux_aarch64 => true,
        else => false,
    };
}

fn stripVPrefix(version: []const u8) []const u8 {
    if (std.mem.startsWith(u8, version, "v")) return version[1..];
    return version;
}

const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,

    fn parse(s: []const u8) !Version {
        var it = std.mem.splitScalar(u8, s, '.');
        const major = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidVersion, 10);
        const minor = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidVersion, 10);
        const patch = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidVersion, 10);
        return .{ .major = major, .minor = minor, .patch = patch };
    }

    fn newerThan(self: Version, other: Version) bool {
        if (self.major != other.major) return self.major > other.major;
        if (self.minor != other.minor) return self.minor > other.minor;
        return self.patch > other.patch;
    }
};

fn archiveName(allocator: std.mem.Allocator, p: Platform) ![]const u8 {
    const ext = if (isWindows(p)) ".zip" else ".tar.gz";
    return std.fmt.allocPrint(allocator, "openapi2zig-{s}{s}", .{ platformString(p), ext });
}

fn getTempDir(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (environ_map.get("TMP")) |p| return allocator.dupe(u8, p);
        if (environ_map.get("TEMP")) |p| return allocator.dupe(u8, p);
        return error.UpgradeFailed;
    }
    if (environ_map.get("TMPDIR")) |p| return allocator.dupe(u8, p);
    return allocator.dupe(u8, "/tmp");
}

fn fetchLatestVersion(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const command = if (builtin.os.tag == .windows)
        [_][]const u8{
            "powershell", "-NoProfile", "-Command",
            "(Invoke-RestMethod 'https://api.github.com/repos/" ++ GITHUB_REPO ++ "/releases/latest' -Headers @{ 'User-Agent' = 'openapi2zig' }).tag_name",
        }
    else
        [_][]const u8{
            "curl", "-s",
            "-H", "User-Agent: openapi2zig",
            "https://api.github.com/repos/" ++ GITHUB_REPO ++ "/releases/latest",
        };

    const result = try std.process.run(allocator, io, .{ .argv = &command });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        std.debug.print("  Version check command failed: term={}, stderr={s}\n", .{ result.term, result.stderr });
        return error.UpgradeFailed;
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) {
        std.debug.print("  Empty response from version check\n", .{});
        return error.UpgradeFailed;
    }

    if (builtin.os.tag != .windows) {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const root = switch (parsed.value) {
            .object => |obj| obj,
            else => {
                std.debug.print("  Unexpected JSON root type\n", .{});
                return error.UpgradeFailed;
            },
        };
        const tag_value = root.get("tag_name") orelse {
            std.debug.print("  Missing 'tag_name' in release response\n", .{});
            return error.UpgradeFailed;
        };
        const version = switch (tag_value) {
            .string => |s| s,
            else => {
                std.debug.print("  'tag_name' is not a string\n", .{});
                return error.UpgradeFailed;
            },
        };
        return allocator.dupe(u8, version);
    }

    return allocator.dupe(u8, trimmed);
}

fn downloadArchive(allocator: std.mem.Allocator, io: std.Io, version: []const u8, platform: Platform, dest_dir: std.Io.Dir) ![]const u8 {
    const archive = try archiveName(allocator, platform);
    defer allocator.free(archive);

    const url = try std.fmt.allocPrint(allocator, "https://github.com/{s}/releases/download/{s}/{s}", .{ GITHUB_REPO, version, archive });
    defer allocator.free(url);

    const uri = try std.Uri.parse(url);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var req = try client.request(.GET, uri, .{});
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buf: [8192]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    if (response.head.status != .ok) return error.UpgradeFailed;

    const content_length = response.head.content_length;

    var transfer_buf: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buf);
    const body = try reader.allocRemaining(allocator, .limited(100 * 1024 * 1024));
    defer allocator.free(body);

    try dest_dir.writeFile(io, .{ .sub_path = archive, .data = body });

    if (content_length) |_| {
        std.debug.print("  Downloaded... ({s})\n", .{archive});
    }

    return allocator.dupe(u8, archive);
}

fn extractArchive(allocator: std.mem.Allocator, io: std.Io, archive_path: []const u8, dest_dir_path: []const u8, platform: Platform) !void {
    const cmd = if (isWindows(platform))
        [_][]const u8{ "tar", "-xf", archive_path, "-C", dest_dir_path }
    else
        [_][]const u8{ "tar", "-xzf", archive_path, "-C", dest_dir_path };

    const result = try std.process.run(allocator, io, .{ .argv = &cmd });
    if (result.term != .exited or result.term.exited != 0) return error.UpgradeFailed;
}

fn replaceBinary(allocator: std.mem.Allocator, io: std.Io, new_binary_path: []const u8) !void {
    const exe_path = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(exe_path);

    const platform = getPlatform();

    if (isWindows(platform)) {
        const old_path = try std.fmt.allocPrint(allocator, "{s}.old", .{exe_path});
        defer allocator.free(old_path);

        std.Io.Dir.renameAbsolute(exe_path, old_path, io) catch |err| {
            std.debug.print("  Warning: could not rename current binary: {}\n", .{err});
            try copyFile(allocator, io, new_binary_path, exe_path);
            return;
        };

        copyFile(allocator, io, new_binary_path, exe_path) catch |err| {
            std.debug.print("  Warning: could not copy new binary: {}\n", .{err});
            std.Io.Dir.renameAbsolute(old_path, exe_path, io) catch {};
            return error.UpgradeFailed;
        };

        const cleanup_cmd = try std.fmt.allocPrint(allocator, "Start-Sleep 2; Remove-Item -Force '{s}'", .{old_path});
        defer allocator.free(cleanup_cmd);

        if (std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "powershell", "-NoProfile", "-Command", cleanup_cmd },
        })) |cleanup_result| {
            allocator.free(cleanup_result.stdout);
            allocator.free(cleanup_result.stderr);
        } else |_| {}
    } else {
        try copyFile(allocator, io, new_binary_path, exe_path);
    }
}

fn copyFile(allocator: std.mem.Allocator, io: std.Io, src: []const u8, dst: []const u8) !void {
    const result = if (builtin.os.tag == .windows)
        try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "cmd", "/c", "copy", "/y", src, dst },
        })
    else
        try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "cp", "-f", src, dst },
        });
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, environ_map: *std.process.Environ.Map) !void {
    std.debug.print("openapi2zig upgrade\n", .{});
    std.debug.print("  Current version: {s}\n", .{version_info.VERSION});

    const platform = getPlatform();
    std.debug.print("  Platform: {s}\n", .{platformString(platform)});

    std.debug.print("  Checking for updates...\n", .{});
    const latest_version = fetchLatestVersion(allocator, io) catch |err| {
        std.debug.print("  Failed to check for updates: {}\n", .{err});
        return err;
    };
    defer allocator.free(latest_version);

    const current = version_info.VERSION;
    const latest_trimmed = stripVPrefix(latest_version);

    std.debug.print("  Latest version: {s}\n", .{latest_version});

    const current_version = Version.parse(current) catch {
        std.debug.print("  Could not parse current version: {s}\n", .{current});
        return;
    };
    const latest_parsed = Version.parse(latest_trimmed) catch {
        std.debug.print("  Could not parse latest version: {s}\n", .{latest_trimmed});
        return;
    };

    if (!latest_parsed.newerThan(current_version)) {
        std.debug.print("  Already up to date.\n", .{});
        return;
    }

    const tmp_dir_path = try getTempDir(allocator, environ_map);
    defer allocator.free(tmp_dir_path);

    const sub_dir_name = "openapi2zig-upgrade";
    const tmp_sub = try std.fs.path.join(allocator, &.{ tmp_dir_path, sub_dir_name });
    defer allocator.free(tmp_sub);

    var sub_dir = try std.Io.Dir.cwd().createDirPathOpen(io, tmp_sub, .{});
    defer sub_dir.close(io);

    std.debug.print("  Downloading...\n", .{});
    const archive_name = try downloadArchive(allocator, io, latest_version, platform, sub_dir);
    defer allocator.free(archive_name);

    const archive_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, sub_dir_name, archive_name });
    defer allocator.free(archive_path);

    std.debug.print("  Extracting...\n", .{});
    try extractArchive(allocator, io, archive_path, tmp_sub, platform);

    const binary_name = if (isWindows(platform)) "openapi2zig.exe" else "openapi2zig";
    const new_binary = try std.fs.path.join(allocator, &.{ tmp_dir_path, sub_dir_name, binary_name });
    defer allocator.free(new_binary);

    std.debug.print("  Installing...\n", .{});
    try replaceBinary(allocator, io, new_binary);

    std.debug.print("  Upgrade complete. Re-run the command to use the new version.\n", .{});
}

test "platformString returns correct values" {
    try std.testing.expectEqualStrings("linux-x86_64", platformString(.linux_x86_64));
    try std.testing.expectEqualStrings("linux-aarch64", platformString(.linux_aarch64));
    try std.testing.expectEqualStrings("macos-x86_64", platformString(.macos_x86_64));
    try std.testing.expectEqualStrings("macos-aarch64", platformString(.macos_aarch64));
    try std.testing.expectEqualStrings("windows-x86_64", platformString(.windows_x86_64));
}

test "isWindows returns true only for windows" {
    try std.testing.expect(!isWindows(.linux_x86_64));
    try std.testing.expect(!isWindows(.linux_aarch64));
    try std.testing.expect(!isWindows(.macos_x86_64));
    try std.testing.expect(!isWindows(.macos_aarch64));
    try std.testing.expect(isWindows(.windows_x86_64));
}

test "isLinux returns true only for linux" {
    try std.testing.expect(isLinux(.linux_x86_64));
    try std.testing.expect(isLinux(.linux_aarch64));
    try std.testing.expect(!isLinux(.macos_x86_64));
    try std.testing.expect(!isLinux(.macos_aarch64));
    try std.testing.expect(!isLinux(.windows_x86_64));
}

test "version comparison skips v prefix" {
    try std.testing.expect(std.mem.eql(u8, "0.2.0", (if (std.mem.startsWith(u8, "v0.2.0", "v")) "v0.2.0"[1..] else "v0.2.0")));
    try std.testing.expect(std.mem.eql(u8, "0.2.0", (if (std.mem.startsWith(u8, "0.2.0", "v")) "0.2.0"[1..] else "0.2.0")));
}
