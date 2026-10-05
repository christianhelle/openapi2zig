//! File operations the build graph needs but no built-in step provides.
//! Zig 0.17 removed custom build steps, so build.zig runs this program
//! through a Run step instead.
//!
//!   build_tools package-snapshot <dest> <pathspec>...
//!       Copy every git-tracked or untracked-but-not-ignored file matching
//!       <pathspec> from the working directory into <dest>, replacing it.
//!
//!   build_tools install <source> <dest-dir> <dest-name>
//!       Copy <source> to <dest-dir>/<dest-name>, creating <dest-dir>.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len >= 3 and std.mem.eql(u8, args[1], "package-snapshot")) {
        return packageSnapshot(arena, io, args[2], args[3..]);
    }
    if (args.len == 5 and std.mem.eql(u8, args[1], "install")) {
        return install(io, args[2], args[3], args[4]);
    }

    std.debug.print(
        \\usage: build_tools package-snapshot <dest> <pathspec>...
        \\       build_tools install <source> <dest-dir> <dest-name>
        \\
    , .{});
    std.process.exit(2);
}

fn packageSnapshot(arena: std.mem.Allocator, io: std.Io, snapshot_root: []const u8, pathspecs: []const []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    try cwd.deleteTree(io, snapshot_root);
    try cwd.createDirPath(io, snapshot_root);

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "git", "ls-files", "--cached", "--others", "--exclude-standard", "--" });
    try argv.appendSlice(arena, pathspecs);

    const result = try std.process.run(arena, io, .{
        .argv = argv.items,
        .stdout_limit = .limited(16 * 1024 * 1024),
        .stderr_limit = .limited(16 * 1024),
    });
    switch (result.term) {
        .exited => |code| if (code != 0) {
            std.debug.print("git ls-files failed: {s}\n", .{result.stderr});
            return error.UnableToPreparePackageSnapshot;
        },
        else => return error.UnableToPreparePackageSnapshot,
    }

    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        const repo_path = std.mem.trimEnd(u8, line, "\r");
        if (repo_path.len == 0) continue;

        const destination_path = try std.fs.path.join(arena, &.{ snapshot_root, repo_path });
        if (std.fs.path.dirname(destination_path)) |dest_dir| {
            try cwd.createDirPath(io, dest_dir);
        }

        try cwd.copyFile(repo_path, cwd, destination_path, io, .{});
    }
}

fn install(io: std.Io, source: []const u8, dest_dir: []const u8, dest_name: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, dest_dir);

    var dir = try cwd.openDir(io, dest_dir, .{});
    defer dir.close(io);

    try cwd.copyFile(source, dir, dest_name, io, .{});
}
