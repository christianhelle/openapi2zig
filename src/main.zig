const models = @import("openapi.zig");
const std = @import("std");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush(); // Don't forget to flush!
}

test "can deserialize openapi version" {
    const allocator = std.testing.allocator;
    const json_data = "{ \"openapi\": \"3.0.0\", \"info\": { \"title\": \"test\", \"version\": \"1.0.0\" }, \"paths\": {} }";
    const parsed = try std.json.parseFromSlice(models.OpenApiDocument, allocator, json_data, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("3.0.0", parsed.value.openapi);
}

test "can deserialize petstore.json" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try std.json.parseFromSlice(models.OpenApiDocument, allocator, file_contents, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("3.0.2", parsed.value.openapi);
}

test "can deserialize petstore into OpenAPI" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try std.json.parseFromSlice(models.OpenApiDocument, allocator, file_contents, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("3.0.2", parsed.value.openapi);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.value.info.title);
}

