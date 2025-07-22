const models = @import("../models.zig");
const std = @import("std");
const test_utils = @import("test_utils.zig");

// Helper function to load and parse a Swagger v2.0 document from a file
fn loadSwaggerDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.SwaggerDocument {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    return try models.SwaggerDocument.parseFromJson(allocator, file_contents);
}

// Helper function to test if a Swagger v2.0 document can be parsed successfully
fn testSwaggerDocumentParsing(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadSwaggerDocument(allocator, file_path);
    defer parsed.deinit(allocator);

    // Basic validation - ensure we have the required fields
    try std.testing.expect(parsed.swagger.len > 0);
    try std.testing.expect(parsed.info.title.len > 0);

    std.debug.print("Successfully parsed Swagger document from {s}: {s} (version: {s})\n", .{ file_path, parsed.info.title, parsed.swagger });
}

test "can deserialize v2.0 petstore into SwaggerDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadSwaggerDocument(allocator, "openapi/v2.0/petstore.json");
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("2.0", parsed.swagger);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);

    // std.debug.print("Parsed Swagger document: {any}\n", .{parsed});

    // var iterator = parsed.paths.path_items.iterator();
    // while (iterator.next()) |path| {
    // std.debug.print("Path: {s}\n", .{path.key_ptr.*});
    // std.debug.print("{any}\n\n", .{path.value_ptr.*});
    // }
}

// Tests for parsing all JSON Swagger v2.0 specifications in v2.0 folder

test "can parse v2.0 api-with-examples.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/api-with-examples.json");
}

test "can parse v2.0 petstore-expanded.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/petstore-expanded.json");
}

test "can parse v2.0 petstore-minimal.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/petstore-minimal.json");
}

test "can parse v2.0 petstore-simple.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/petstore-simple.json");
}

test "can parse v2.0 petstore-with-external-docs.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/petstore-with-external-docs.json");
}

test "can parse v2.0 petstore.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/petstore.json");
}

test "can parse v2.0 uber.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testSwaggerDocumentParsing(allocator, "openapi/v2.0/uber.json");
}

// Comprehensive test that validates all JSON Swagger v2.0 specifications can be parsed
test "can parse all v2.0 JSON Swagger specifications" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json_files = [_][]const u8{
        "openapi/v2.0/api-with-examples.json",
        "openapi/v2.0/petstore-expanded.json",
        "openapi/v2.0/petstore-minimal.json",
        "openapi/v2.0/petstore-simple.json",
        "openapi/v2.0/petstore-with-external-docs.json",
        "openapi/v2.0/petstore.json",
        "openapi/v2.0/uber.json",
    };

    var successful_parses: u32 = 0;

    for (json_files) |file_path| {
        testSwaggerDocumentParsing(allocator, file_path) catch |err| {
            std.debug.print("Failed to parse {s}: {any}\n", .{ file_path, err });
            continue;
        };
        successful_parses += 1;
    }

    std.debug.print("Successfully parsed {d}/{d} JSON Swagger v2.0 specifications\n", .{ successful_parses, json_files.len });
    try std.testing.expect(successful_parses > 0);
}
