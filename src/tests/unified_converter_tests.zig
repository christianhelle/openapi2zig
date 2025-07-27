const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const SwaggerConverter = @import("../generators/converters/swagger_converter.zig").SwaggerConverter;
const models = @import("../models.zig");
const std = @import("std");
const test_utils = @import("test_utils.zig");
fn loadOpenApiDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.OpenApiDocument {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);
    return try models.OpenApiDocument.parseFromJson(allocator, file_contents);
}
fn loadSwaggerDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.SwaggerDocument {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);
    return try models.SwaggerDocument.parseFromJson(allocator, file_contents);
}
fn testOpenApiToUnifiedDocumentConversion(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApiDocument(allocator, file_path);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.version.len > 0);
    try std.testing.expect(unified.info.title.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, unified.version, "3."));
    std.debug.print("OpenAPI v3.0 -> UnifiedDocument: {s} ({s})\n", .{ unified.info.title, unified.version });
}
fn testSwaggerToUnifiedDocumentConversion(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadSwaggerDocument(allocator, file_path);
    defer parsed.deinit(allocator);
    var converter = SwaggerConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.version.len > 0);
    try std.testing.expect(unified.info.title.len > 0);
    try std.testing.expectEqualStrings("2.0", unified.version);
    std.debug.print("Swagger v2.0 -> UnifiedDocument: {s} ({s})\n", .{ unified.info.title, unified.version });
}
test "convert all OpenAPI v3.0 JSON specifications to UnifiedDocument" {
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
            std.debug.print("Failed to convert OpenAPI v3.0 {s}: {any}\n", .{ file_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Successfully converted {d}/{d} OpenAPI v3.0 specifications to UnifiedDocument\n", .{ successful_conversions, json_files.len });
    try std.testing.expect(successful_conversions == json_files.len);
}
test "convert all Swagger v2.0 JSON specifications to UnifiedDocument" {
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
    var successful_conversions: u32 = 0;
    for (json_files) |file_path| {
        testSwaggerToUnifiedDocumentConversion(allocator, file_path) catch |err| {
            std.debug.print("Failed to convert Swagger v2.0 {s}: {any}\n", .{ file_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Successfully converted {d}/{d} Swagger v2.0 specifications to UnifiedDocument\n", .{ successful_conversions, json_files.len });
    try std.testing.expect(successful_conversions == json_files.len);
}
test "unified conversion compatibility between Swagger v2.0 and OpenAPI v3.0" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var swagger_doc = try loadSwaggerDocument(allocator, "openapi/v2.0/petstore.json");
    defer swagger_doc.deinit(allocator);
    var openapi_doc = try loadOpenApiDocument(allocator, "openapi/v3.0/petstore.json");
    defer openapi_doc.deinit(allocator);
    var swagger_converter = SwaggerConverter.init(allocator);
    var swagger_unified = try swagger_converter.convert(swagger_doc);
    defer swagger_unified.deinit(allocator);
    var openapi_converter = OpenApiConverter.init(allocator);
    var openapi_unified = try openapi_converter.convert(openapi_doc);
    defer openapi_unified.deinit(allocator);
    try std.testing.expectEqualStrings("Swagger Petstore", swagger_unified.info.title);
    try std.testing.expectEqualStrings("Swagger Petstore", openapi_unified.info.title);
    try std.testing.expectEqualStrings("2.0", swagger_unified.version);
    try std.testing.expectEqualStrings("3.0.2", openapi_unified.version);
    try std.testing.expect(swagger_unified.paths.count() > 0);
    try std.testing.expect(openapi_unified.paths.count() > 0);
    std.debug.print("Unified conversion test passed: Swagger v2.0 ({d} paths) and OpenAPI v3.0 ({d} paths) both converted successfully\n", .{ swagger_unified.paths.count(), openapi_unified.paths.count() });
}
