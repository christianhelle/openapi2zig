const OpenApi31Converter = @import("../generators/converters/openapi31_converter.zig").OpenApi31Converter;
const models = @import("../models.zig");
const std = @import("std");
const test_utils = @import("test_utils.zig");

fn loadOpenApi31Document(allocator: std.mem.Allocator, file_path: []const u8) !models.OpenApi31Document {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);
    return try models.OpenApi31Document.parseFromJson(allocator, file_contents);
}

fn testOpenApi31DocumentParsing(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApi31Document(allocator, file_path);
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.openapi.len > 0);
    try std.testing.expect(parsed.info.title.len > 0);
    std.debug.print("Successfully parsed OpenAPI 3.1 document from {s}: {s} (version: {s})\n", .{ file_path, parsed.info.title, parsed.openapi });
}

test "can deserialize non-oauth-scopes into OpenApi31Document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/non-oauth-scopes.json");
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings("3.1.0", parsed.openapi);
    try std.testing.expectEqualStrings("Non-oAuth Scopes example", parsed.info.title);
}

test "can deserialize webhook-example into OpenApi31Document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/webhook-example.json");
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings("3.1.0", parsed.openapi);
    try std.testing.expectEqualStrings("Webhook Example", parsed.info.title);
}

test "can parse non-oauth-scopes paths" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/non-oauth-scopes.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.paths != null);
    try std.testing.expect(parsed.paths.?.path_items.count() > 0);
}

test "can parse non-oauth-scopes components" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/non-oauth-scopes.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.components != null);
    try std.testing.expect(parsed.components.?.securitySchemes != null);
    try std.testing.expect(parsed.components.?.securitySchemes.?.count() == 1);
}

test "can parse webhook-example webhooks" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/webhook-example.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.webhooks != null);
    try std.testing.expect(parsed.webhooks.?.count() == 1);
}

test "can parse webhook-example components schemas" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/webhook-example.json");
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.components != null);
    try std.testing.expect(parsed.components.?.schemas != null);
    try std.testing.expect(parsed.components.?.schemas.?.count() > 0);
}

test "can parse all v3.1 JSON OpenAPI specifications" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const json_files = [_][]const u8{
        "openapi/v3.1/non-oauth-scopes.json",
        "openapi/v3.1/webhook-example.json",
    };
    var successful_parses: u32 = 0;
    for (json_files) |file_path| {
        testOpenApi31DocumentParsing(allocator, file_path) catch |err| {
            std.debug.print("Failed to parse {s}: {}\n", .{ file_path, err });
            continue;
        };
        successful_parses += 1;
    }
    std.debug.print("Successfully parsed {d}/{d} JSON OpenAPI 3.1 specifications\n", .{ successful_parses, json_files.len });
    try std.testing.expect(successful_parses == json_files.len);
}

fn testOpenApi31ToUnifiedDocumentConversion(allocator: std.mem.Allocator, file_path: []const u8) !void {
    var parsed = try loadOpenApi31Document(allocator, file_path);
    defer parsed.deinit(allocator);
    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.version.len > 0);
    try std.testing.expect(unified.info.title.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, unified.version, "3.1"));
    std.debug.print("Successfully converted OpenAPI 3.1 document from {s}: {s} (version: {s})\n", .{ file_path, unified.info.title, unified.version });
}

test "can convert non-oauth-scopes.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApi31ToUnifiedDocumentConversion(allocator, "openapi/v3.1/non-oauth-scopes.json");
}

test "can convert webhook-example.json to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    try testOpenApi31ToUnifiedDocumentConversion(allocator, "openapi/v3.1/webhook-example.json");
}

test "converted non-oauth-scopes has correct version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/non-oauth-scopes.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("3.1.0", unified.version);
}

test "converted non-oauth-scopes has correct title" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/non-oauth-scopes.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("Non-oAuth Scopes example", unified.info.title);
}

test "converted non-oauth-scopes has paths" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/non-oauth-scopes.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.paths.count() > 0);
}

test "converted webhook-example has schemas" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadOpenApi31Document(allocator, "openapi/v3.1/webhook-example.json");
    defer parsed.deinit(allocator);
    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try std.testing.expect(unified.schemas != null);
    try std.testing.expect(unified.schemas.?.count() > 0);
}

test "can convert all v3.1 JSON OpenAPI specifications to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const json_files = [_][]const u8{
        "openapi/v3.1/non-oauth-scopes.json",
        "openapi/v3.1/webhook-example.json",
    };
    var successful_conversions: u32 = 0;
    for (json_files) |file_path| {
        testOpenApi31ToUnifiedDocumentConversion(allocator, file_path) catch |err| {
            std.debug.print("Failed to convert {s}: {}\n", .{ file_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Successfully converted {d}/{d} JSON OpenAPI v3.1 specifications to UnifiedDocument\n", .{ successful_conversions, json_files.len });
    try std.testing.expect(successful_conversions == json_files.len);
}

test "dynamically convert all OpenAPI v3.1 JSON files to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const openapi_dir = try std.fs.cwd().openDir("openapi/v3.1", .{ .iterate = true });
    var iterator = openapi_dir.iterate();
    var successful_conversions: u32 = 0;
    var total_files: u32 = 0;
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        total_files += 1;
        var path_buffer: [256]u8 = undefined;
        const full_path = try std.fmt.bufPrint(path_buffer[0..], "openapi/v3.1/{s}", .{entry.name});
        testOpenApi31ToUnifiedDocumentConversion(allocator, full_path) catch |err| {
            std.debug.print("✗ Failed to convert OpenAPI v3.1 {s}: {}\n", .{ full_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Dynamic OpenAPI v3.1 test: {d}/{d} files converted successfully\n", .{ successful_conversions, total_files });
    try std.testing.expect(successful_conversions == total_files);
    try std.testing.expect(total_files > 0);
}

test "memory leak stress test for v3.1 converter" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const iterations = 50;
    for (0..iterations) |i| {
        {
            var openapi_doc = try loadOpenApi31Document(allocator, "openapi/v3.1/webhook-example.json");
            defer openapi_doc.deinit(allocator);
            var converter = OpenApi31Converter.init(allocator);
            var unified = try converter.convert(openapi_doc);
            defer unified.deinit(allocator);
            try std.testing.expect(unified.info.title.len > 0);
        }
        if ((i + 1) % 10 == 0) {
            std.debug.print("Completed {d}/{d} v3.1 stress test iterations\n", .{ i + 1, iterations });
        }
    }
    std.debug.print("✓ v3.1 memory leak stress test passed: {d} iterations completed successfully\n", .{iterations});
}
