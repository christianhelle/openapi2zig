const models = @import("models.zig");

const std = @import("std");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush(); // Don't forget to flush!
}

const OpenAPI = struct {
    openapi: []const u8,
};

test "can deserialize openapi version" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(OpenAPI, allocator,
        \\{ "openapi": "3.0.0" }
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("3.0.0", parsed.value.openapi);
}

test "can deserialize petstore.json" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try std.json.parseFromSlice(OpenAPI, allocator, file_contents, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("3.0.2", parsed.value.openapi);
}

test "can deserialize petstore into OpenApiDocument" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try models.OpenApiDocument.parse(allocator, file_contents);
    try std.testing.expectEqualStrings("3.0.2", parsed.openapi);
}
