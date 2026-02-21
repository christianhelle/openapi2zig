const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;
const models = @import("../models.zig");
const std = @import("std");
const test_utils = @import("test_utils.zig");

fn loadOpenApi32Document(allocator: std.mem.Allocator, file_path: []const u8) !models.OpenApi32Document {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);
    return try models.OpenApi32Document.parseFromJson(allocator, file_contents);
}

fn testOpenApi32DocumentParsing(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApi32Document(allocator, file_path);
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.openapi.len > 0);
    try std.testing.expect(parsed.info.title.len > 0);
    std.debug.print("Successfully parsed OpenAPI 3.2 document from {s}: {s} (version: {s})\n", .{ file_path, parsed.info.title, parsed.openapi });
}

test "can deserialize petstore into OpenApi32Document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings("3.2.0", parsed.openapi);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);
}

test "can parse petstore info summary field" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.info.summary != null);
    try std.testing.expectEqualStrings("A sample API that uses a petstore as an example", parsed.info.summary.?);
}

test "can parse petstore license identifier" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.info.license != null);
    try std.testing.expectEqualStrings("Apache-2.0", parsed.info.license.?.identifier.?);
}

test "can parse petstore paths" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.paths != null);
    try std.testing.expect(parsed.paths.?.path_items.count() > 0);
}

test "can parse petstore components schemas" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.components != null);
    try std.testing.expect(parsed.components.?.schemas != null);
    try std.testing.expect(parsed.components.?.schemas.?.count() > 0);
}

test "can parse petstore tags" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.tags != null);
    try std.testing.expect(parsed.tags.?.len == 3);
}

test "can parse petstore servers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.servers != null);
    try std.testing.expect(parsed.servers.?.len == 1);
    try std.testing.expectEqualStrings("https://petstore3.swagger.io/api/v3", parsed.servers.?[0].url);
}

test "can parse petstore security schemes" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.components != null);
    try std.testing.expect(parsed.components.?.securitySchemes != null);
    try std.testing.expect(parsed.components.?.securitySchemes.?.count() == 2);
}

test "can parse petstore-expanded.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApi32DocumentParsing(allocator, "openapi/v3.2/petstore-expanded.json");
}

test "can parse petstore-expanded webhooks" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore-expanded.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.webhooks != null);
    try std.testing.expect(parsed.webhooks.?.count() == 2);
}

test "can parse petstore-expanded type arrays for nullable" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore-expanded.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.components != null);
    try std.testing.expect(parsed.components.?.schemas != null);
    const schemas = parsed.components.?.schemas.?;
    const pet_schema_or_ref = schemas.get("Pet").?;
    switch (pet_schema_or_ref) {
        .schema => |schema| {
            try std.testing.expect(schema.properties != null);
            const tag_prop = schema.properties.?.get("tag").?;
            switch (tag_prop) {
                .schema => |tag_schema| {
                    // "type": ["string", "null"] should populate type_array
                    try std.testing.expect(tag_schema.type_array != null);
                    try std.testing.expect(tag_schema.type_array.?.len == 2);
                },
                .reference => {
                    return error.UnexpectedReference;
                },
            }
        },
        .reference => {
            return error.UnexpectedReference;
        },
    }
}

test "can parse petstore-expanded multiple servers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore-expanded.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.servers != null);
    try std.testing.expect(parsed.servers.?.len == 2);
}

test "can parse all v3.2 JSON OpenAPI specifications" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const json_files = [_][]const u8{
        "openapi/v3.2/petstore.json",
        "openapi/v3.2/petstore-expanded.json",
    };
    var successful_parses: u32 = 0;
    for (json_files) |file_path| {
        testOpenApi32DocumentParsing(allocator, file_path) catch |err| {
            std.debug.print("Failed to parse {s}: {}\n", .{ file_path, err });
            continue;
        };
        successful_parses += 1;
    }
    std.debug.print("Successfully parsed {d}/{d} JSON OpenAPI 3.2 specifications\n", .{ successful_parses, json_files.len });
    try std.testing.expect(successful_parses == json_files.len);
}

fn testOpenApi32ToUnifiedDocumentConversion(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApi32Document(allocator, file_path);
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.version.len > 0);
    try std.testing.expect(unified.info.title.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, unified.version, "3.2"));
    std.debug.print("Successfully converted OpenAPI 3.2 document from {s}: {s} (version: {s})\n", .{ file_path, unified.info.title, unified.version });
}

test "can convert petstore.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApi32ToUnifiedDocumentConversion(allocator, "openapi/v3.2/petstore.json");
}

test "can convert petstore-expanded.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApi32ToUnifiedDocumentConversion(allocator, "openapi/v3.2/petstore-expanded.json");
}

test "converted petstore has correct version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("3.2.0", unified.version);
}

test "converted petstore has correct title" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("Swagger Petstore", unified.info.title);
}

test "converted petstore has paths" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.paths.count() > 0);
}

test "converted petstore has schemas" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.schemas != null);
    try std.testing.expect(unified.schemas.?.count() > 0);
}

test "converted petstore has servers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.servers != null);
    try std.testing.expect(unified.servers.?.len == 1);
}

test "converted petstore has tags" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.tags != null);
    try std.testing.expect(unified.tags.?.len == 3);
}

test "converted petstore has external docs" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.externalDocs != null);
}

test "converted petstore-expanded has correct paths" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore-expanded.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.paths.count() == 2);
}

test "can convert all v3.2 JSON OpenAPI specifications to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const json_files = [_][]const u8{
        "openapi/v3.2/petstore.json",
        "openapi/v3.2/petstore-expanded.json",
    };
    var successful_conversions: u32 = 0;
    for (json_files) |file_path| {
        testOpenApi32ToUnifiedDocumentConversion(allocator, file_path) catch |err| {
            std.debug.print("Failed to convert {s}: {}\n", .{ file_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Successfully converted {d}/{d} JSON OpenAPI v3.2 specifications to UnifiedDocument\n", .{ successful_conversions, json_files.len });
    try std.testing.expect(successful_conversions == json_files.len);
}

test "dynamically convert all OpenAPI v3.2 JSON files to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var openapi_dir = try std.fs.cwd().openDir("openapi/v3.2", .{ .iterate = true });
    defer openapi_dir.close();
    var iterator = openapi_dir.iterate();
    var successful_conversions: u32 = 0;
    var total_files: u32 = 0;
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        total_files += 1;
        var path_buffer: [256]u8 = undefined;
        const full_path = try std.fmt.bufPrint(path_buffer[0..], "openapi/v3.2/{s}", .{entry.name});
        testOpenApi32ToUnifiedDocumentConversion(allocator, full_path) catch |err| {
            std.debug.print("✗ Failed to convert OpenAPI v3.2 {s}: {}\n", .{ full_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Dynamic OpenAPI v3.2 test: {d}/{d} files converted successfully\n", .{ successful_conversions, total_files });
    try std.testing.expect(successful_conversions == total_files);
    try std.testing.expect(total_files > 0);
}

test "memory leak stress test for v3.2 converter" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const iterations = 50;
    for (0..iterations) |i| {
        {
            var openapi_doc = try loadOpenApi32Document(allocator, "openapi/v3.2/petstore.json");
            defer openapi_doc.deinit(allocator);
            var converter = OpenApi32Converter.init(allocator);
            var unified = try converter.convert(openapi_doc);
            defer unified.deinit(allocator);
            try std.testing.expect(unified.info.title.len > 0);
        }
        if ((i + 1) % 10 == 0) {
            std.debug.print("Completed {d}/{d} v3.2 stress test iterations\n", .{ i + 1, iterations });
        }
    }
    std.debug.print("✓ v3.2 memory leak stress test passed: {d} iterations completed successfully\n", .{iterations});
}
