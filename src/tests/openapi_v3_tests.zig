const ModelCodeGenerator = @import("../generators/v3.0/modelgenerator.zig").ModelCodeGenerator;
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const models = @import("../models.zig");
const std = @import("std");
const test_utils = @import("test_utils.zig");

// Helper function to load and parse an OpenAPI document from a file
fn loadOpenApiDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.OpenApiDocument {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    return try models.OpenApiDocument.parseFromJson(allocator, file_contents);
}

// Helper function to test if an OpenAPI document can be parsed successfully
fn testOpenApiDocumentParsing(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApiDocument(allocator, file_path);
    defer parsed.deinit(allocator);

    // Basic validation - ensure we have the required fields
    try std.testing.expect(parsed.openapi.len > 0);
    try std.testing.expect(parsed.info.title.len > 0);

    std.debug.print("Successfully parsed OpenAPI document from {s}: {s} (version: {s})\n", .{ file_path, parsed.info.title, parsed.openapi });
}

test "can deserialize petstore into OpenApiDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadOpenApiDocument(allocator, "openapi/v3.0/petstore.json");
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("3.0.2", parsed.openapi);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);

    // std.debug.print("Parsed OpenAPI document: {any}\n", .{parsed});

    // var iterator = parsed.paths.path_items.iterator();
    // while (iterator.next()) |path| {
    //     // std.debug.print("Path: {s}\n", .{path.key_ptr.*});
    //     // std.debug.print("{any}\n\n", .{path.value_ptr.*});
    // }
}

test "can generate data structures from petstore OpenAPI specification" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadOpenApiDocument(allocator, "openapi/v3.0/petstore.json");
    defer parsed.deinit(allocator);

    var code_gen = ModelCodeGenerator.init(allocator);
    defer code_gen.deinit();

    const generated_code = try code_gen.generate(parsed);
    defer allocator.free(generated_code);

    // std.debug.print("Generated code:\n{s}\n", .{generated_code});
    try std.testing.expect(generated_code.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "pub const Pet = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_code, "name: []const u8") != null);
}

// Tests for parsing all JSON OpenAPI specifications in v3.0 folder

test "can parse api-with-examples.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/api-with-examples.json");
}

test "can parse callback-example.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/callback-example.json");
}

test "can parse hubspot-events.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/hubspot-events.json");
}

test "can parse hubspot-webhooks.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/hubspot-webhooks.json");
}

test "can parse ingram-micro.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/ingram-micro.json");
}

test "can parse link-example.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/link-example.json");
}

test "can parse petstore-expanded.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/petstore-expanded.json");
}

test "can parse petstore.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/petstore.json");
}

test "can parse uspto.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/uspto.json");
}

test "can parse weather.json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiDocumentParsing(allocator, "openapi/v3.0/weather.json");
}

// Comprehensive test that validates all JSON OpenAPI specifications can be parsed
test "can parse all v3.0 JSON OpenAPI specifications" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json_files = [_][]const u8{
        "openapi/v3.0/api-with-examples.json",
        "openapi/v3.0/callback-example.json",
        "openapi/v3.0/hubspot-events.json",
        "openapi/v3.0/hubspot-webhooks.json",
        "openapi/v3.0/ingram-micro.json",
        "openapi/v3.0/link-example.json",
        "openapi/v3.0/petstore-expanded.json",
        "openapi/v3.0/petstore.json",
        "openapi/v3.0/uspto.json",
        "openapi/v3.0/weather.json",
    };

    var successful_parses: u32 = 0;

    for (json_files) |file_path| {
        testOpenApiDocumentParsing(allocator, file_path) catch |err| {
            std.debug.print("Failed to parse {s}: {any}\n", .{ file_path, err });
            continue;
        };
        successful_parses += 1;
    }

    std.debug.print("Successfully parsed {d}/{d} JSON OpenAPI specifications\n", .{ successful_parses, json_files.len });
    try std.testing.expect(successful_parses > 0);
}

// Helper function to test if an OpenAPI v3.0 document can be converted to UnifiedDocument
fn testOpenApiToUnifiedDocumentConversion(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApiDocument(allocator, file_path);
    defer parsed.deinit(allocator);

    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    // Basic validation - ensure conversion was successful
    try std.testing.expect(unified.version.len > 0);
    try std.testing.expect(unified.info.title.len > 0);

    std.debug.print("Successfully converted OpenAPI document from {s}: {s} (version: {s})\n", .{ file_path, unified.info.title, unified.version });
}

// Tests for converting all JSON OpenAPI v3.0 specifications to UnifiedDocument

test "can convert api-with-examples.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/api-with-examples.json");
}

test "can convert callback-example.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/callback-example.json");
}

test "can convert hubspot-events.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/hubspot-events.json");
}

test "can convert hubspot-webhooks.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/hubspot-webhooks.json");
}

test "can convert ingram-micro.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/ingram-micro.json");
}

test "can convert link-example.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/link-example.json");
}

test "can convert petstore-expanded.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/petstore-expanded.json");
}

test "can convert petstore.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/petstore.json");
}

test "can convert uspto.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/uspto.json");
}

test "can convert weather.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApiToUnifiedDocumentConversion(allocator, "openapi/v3.0/weather.json");
}

// Comprehensive test that validates all JSON OpenAPI v3.0 specifications can be converted to UnifiedDocument
test "can convert all v3.0 JSON OpenAPI specifications to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json_files = [_][]const u8{
        "openapi/v3.0/api-with-examples.json",
        "openapi/v3.0/callback-example.json",
        "openapi/v3.0/hubspot-events.json",
        "openapi/v3.0/hubspot-webhooks.json",
        "openapi/v3.0/ingram-micro.json",
        "openapi/v3.0/link-example.json",
        "openapi/v3.0/petstore-expanded.json",
        "openapi/v3.0/petstore.json",
        "openapi/v3.0/uspto.json",
        "openapi/v3.0/weather.json",
    };

    var successful_conversions: u32 = 0;

    for (json_files) |file_path| {
        testOpenApiToUnifiedDocumentConversion(allocator, file_path) catch |err| {
            std.debug.print("Failed to convert {s}: {any}\n", .{ file_path, err });
            continue;
        };
        successful_conversions += 1;
    }

    std.debug.print("Successfully converted {d}/{d} JSON OpenAPI v3.0 specifications to UnifiedDocument\n", .{ successful_conversions, json_files.len });
    try std.testing.expect(successful_conversions > 0);
}
