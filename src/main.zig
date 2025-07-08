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

test "can deserialize petstore into OpenApiDocument" {
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

test "can deserialize petstore paths" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try std.json.parseFromSlice(models.OpenApiDocument, allocator, file_contents, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    std.debug.print("\nParsed OpenAPI Document: \n{any}\n", .{parsed.value});
    std.debug.print("\n\nPaths: \n{any}\n", .{parsed.value.paths});

    //var path_items_map = std.StringHashMap(models.PathItem).init(allocator);
    //errdefer path_items_map.deinit();
    //const obj = parsed.value.paths.object;
    //for (obj.keys()) |key| {
    //    if (key[0] == '/') { // Path items start with '/'
    //        const item = models.PathItem{
    //            .ref = obj.get("$ref").?.value.?.string orelse null,
    //            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
    //            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
    //        };
    //        try path_items_map.put(key, item);
    //    }
    //}

    //try std.testing.expect(path_items_map.count() > 0);
}

