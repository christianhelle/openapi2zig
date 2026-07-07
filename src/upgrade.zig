const std = @import("std");
const builtin = @import("builtin");
const version_info = @import("build_info");

const GITHUB_REPO = "christianhelle/openapi2zig";

const Platform = enum {
    linux_x86_64,
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
            .macos => .macos_aarch64,
            else => @compileError("unsupported OS for aarch64"),
        },
        else => @compileError("unsupported architecture"),
    };
}

fn platformString(p: Platform) []const u8 {
    return switch (p) {
        .linux_x86_64 => "linux-x86_64",
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

fn archiveName(p: Platform) []const u8 {
    const ext = if (isWindows(p)) ".zip" else ".tar.gz";
    return "openapi2zig-" ++ platformString(p) ++ ext;
}

fn fetchLatestVersion(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const url = "https://api.github.com/repos/" ++ GITHUB_REPO ++ "/releases/latest";
    const uri = try std.Uri.parse(url);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var req = try client.request(.GET, uri, .{});
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buf: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    if (response.head.status != .ok) {
        return error.UpgradeFailed;
    }

    var transfer_buf: [4096]u8 = undefined;
    const reader = response.reader(&transfer_buf);
    const body = try reader.allocRemaining(allocator, .limited(1024 * 1024));

    var token_stream = std.json.TokenStream.init(body);
    const parsed = try std.json.parse(std.json.Value, &token_stream, .{ .allocator = allocator, .ignore_unknown_fields = true });
    defer parsed.deinit();

    const tag_name = parsed.value.object.get("tag_name") orelse return error.UpgradeFailed;
    const version = switch (tag_name) {
        .string => |s| s,
        else => return error.UpgradeFailed,
    };

    return allocator.dupe(u8, version);
}

fn downloadArchive(allocator: std.mem.Allocator, io: std.Io, version: []const u8, platform: Platform, dest_dir: std.fs.Dir) ![]const u8 {
    const archive = archiveName(platform);
    var url_buf = std.ArrayList(u8).init(allocator);
    defer url_buf.deinit();

    const writer = url_buf.writer();
    try writer.print("https://github.com/{s}/releases/download/{s}/{s}", .{ GITHUB_REPO, version, archive });

    const uri = try std.Uri.parse(url_buf.items);
    const out_name = try allocator.dupe(u8, archive);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var req = try client.request(.GET, uri, .{});
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buf: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    if (response.head.status != .ok) {
        return error.UpgradeFailed;
    }

    const content_length = response.head.content_length;

    var file = try dest_dir.createFile(out_name, .{});
    defer file.close();

    var transfer_buf: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buf);

    var downloaded: u64 = 0;
    while (true) {
        const bytes = try reader.read(&transfer_buf);
        if (bytes == 0) break;
        try file.writeAll(transfer_buf[0..bytes]);
        downloaded += bytes;
        if (content_length) |total| {
            const pct = @as(f64, @floatFromInt(downloaded)) / @as(f64, @floatFromInt(total)) * 100.0;
            std.debug.print("\r  Downloading... {d: >3.0}%", .{pct});
        }
    }
    std.debug.print("\n", .{});

    return out_name;
}

fn extractArchive(allocator: std.mem.Allocator, io: std.Io, archive_path: []const u8, dest_dir_path: []const u8, platform: Platform) !void {
    _ = allocator;
    _ = io;

    const cmd = if (isWindows(platform))
        [_][]const u8{ "tar", "-xf", archive_path, "-C", dest_dir_path }
    else
        [_][]const u8{ "tar", "-xzf", archive_path, "-C", dest_dir_path };

    var child = std.process.Child.init(&cmd, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return error.UpgradeFailed;
    }
}

fn replaceBinary(allocator: std.mem.Allocator, io: std.Io, new_binary_path: []const u8) !void {
    _ = io;

    var exe_buf: [1024]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&exe_buf);
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";
    const exe_name = std.fs.path.basename(exe_path);

    const platform = getPlatform();

    if (isWindows(platform)) {
        const old_path = try std.fmt.allocPrint(allocator, "{s}.old", .{exe_path});
        defer allocator.free(old_path);

        std.fs.renameAbsolute(exe_path, old_path) catch |err| {
            std.debug.print("  Warning: could not rename current binary: {}\n", .{err});
            const new_name = try std.fs.path.join(allocator, &.{ exe_dir, exe_name });
            defer allocator.free(new_name);
            try copyBinary(new_binary_path, new_name);
            try scheduleCleanup(allocator, old_path);
            return;
        };

        copyBinary(new_binary_path, exe_path) catch |err| {
            std.debug.print("  Warning: could not copy new binary: {}\n", .{err});
            std.fs.renameAbsolute(old_path, exe_path) catch {};
            return error.UpgradeFailed;
        };

        try scheduleCleanup(allocator, old_path);
    } else {
        try copyBinary(new_binary_path, exe_path);
    }
}

fn copyBinary(src: []const u8, dst: []const u8) !void {
    var src_file = try std.fs.openFileAbsolute(src, .{});
    defer src_file.close();

    const stat = try src_file.stat();
    const mode = if (@hasDecl(std.fs, "mode")) stat.mode else @as(u32, 0);

    var dst_file = try std.fs.createFileAbsolute(dst, .{});
    defer dst_file.close();

    try dst_file.writeAll(src_file.reader().readAllAlloc(
        std.heap.page_allocator,
        @as(usize, @intCast(stat.size)),
    ) catch unreachable);

    if (@hasDecl(std.fs, "setMode")) {
        std.fs.setMode(dst, mode) catch {};
    }
}

fn scheduleCleanup(allocator: std.mem.Allocator, old_path: []const u8) !void {
    _ = allocator;
    _ = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{
            "powershell",
            "-NoProfile",
            "-Command",
            "Start-Sleep 2; Remove-Item -Force '" ++ old_path ++ "'",
        },
    }) catch {};
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
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
    const latest_trimmed = if (std.mem.startsWith(u8, latest_version, "v")) latest_version[1..] else latest_version;

    std.debug.print("  Latest version: {s}\n", .{latest_version});

    if (std.mem.eql(u8, current, latest_trimmed)) {
        std.debug.print("  Already up to date.\n", .{});
        return;
    }

    const tmp_dir_path = std.fs.getTempDir();
    var tmp_dir = try std.fs.openDirAbsolute(tmp_dir_path, .{});
    defer tmp_dir.close();

    const sub_dir_name = "openapi2zig-upgrade-XXXXXX";
    const sub_dir = try std.fs.Dir.makeOpenPath(tmp_dir, sub_dir_name, .{});

    std.debug.print("  Downloading...\n", .{});
    const archive_name = try downloadArchive(allocator, io, latest_version, platform, sub_dir);
    defer allocator.free(archive_name);

    const archive_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, sub_dir_name, archive_name });
    defer allocator.free(archive_path);

    std.debug.print("  Extracting...\n", .{});
    try extractArchive(allocator, io, archive_path, tmp_dir_path, platform);

    const binary_name = if (isWindows(platform)) "openapi2zig.exe" else "openapi2zig";
    const new_binary = try std.fs.path.join(allocator, &.{ tmp_dir_path, sub_dir_name, binary_name });
    defer allocator.free(new_binary);

    std.debug.print("  Installing...\n", .{});
    try replaceBinary(allocator, io, new_binary);

    std.debug.print("  Upgrade complete. Re-run the command to use the new version.\n", .{});
}
