const std = @import("std");
const output_writer = @import("../generator/output_writer.zig");
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn read(allocator: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]u8 {
    return dir.readFileAlloc(testing.io, path, allocator, .unlimited);
}

test "writeOwned writes a missing file and creates parent directories" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const result = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "docs/a.md", "hello\n", .scaffold, false);
    try testing.expectEqual(output_writer.WriteResult.written, result);

    const content = try read(allocator, tmp.dir, "docs/a.md");
    defer allocator.free(content);
    try testing.expectEqualStrings("hello\n", content);
}

test "writeOwned never overwrites an existing scaffold file" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    _ = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "README.md", "mine\n", .scaffold, false);
    const result = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "README.md", "generated\n", .scaffold, false);
    try testing.expectEqual(output_writer.WriteResult.skipped_existing, result);

    const content = try read(allocator, tmp.dir, "README.md");
    defer allocator.free(content);
    try testing.expectEqualStrings("mine\n", content);
}

test "writeOwned overwrites scaffold files when forced" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    _ = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "README.md", "mine\n", .scaffold, false);
    const result = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "README.md", "generated\n", .scaffold, true);
    try testing.expectEqual(output_writer.WriteResult.written, result);

    const content = try read(allocator, tmp.dir, "README.md");
    defer allocator.free(content);
    try testing.expectEqualStrings("generated\n", content);
}

test "writeOwned always overwrites generated files that changed" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    _ = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "build.zig", "old\n", .generated, false);
    const result = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "build.zig", "new\n", .generated, false);
    try testing.expectEqual(output_writer.WriteResult.written, result);

    const content = try read(allocator, tmp.dir, "build.zig");
    defer allocator.free(content);
    try testing.expectEqualStrings("new\n", content);
}

test "writeOwned skips generated files whose content is unchanged" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    _ = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "build.zig", "same\n", .generated, false);
    const result = try output_writer.writeOwned(allocator, testing.io, tmp.dir, "build.zig", "same\n", .generated, false);
    try testing.expectEqual(output_writer.WriteResult.skipped_unchanged, result);
}
