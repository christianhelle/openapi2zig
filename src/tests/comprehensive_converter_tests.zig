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
    if (unified.paths.count() > 0) {
        var path_iterator = unified.paths.iterator();
        while (path_iterator.next()) |entry| {
            try std.testing.expect(entry.key_ptr.*.len > 0);
        }
    }
    std.debug.print("✓ OpenAPI v3.0 -> UnifiedDocument: {s} ({s}) - {d} paths\n", .{ unified.info.title, unified.version, unified.paths.count() });
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
    if (unified.paths.count() > 0) {
        var path_iterator = unified.paths.iterator();
        while (path_iterator.next()) |entry| {
            try std.testing.expect(entry.key_ptr.*.len > 0);
        }
    }
    std.debug.print("✓ Swagger v2.0 -> UnifiedDocument: {s} ({s}) - {d} paths\n", .{ unified.info.title, unified.version, unified.paths.count() });
}

test "dynamically convert all OpenAPI v3.0 JSON files to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const openapi_dir = try std.fs.cwd().openDir("openapi/v3.0", .{ .iterate = true });
    var iterator = openapi_dir.iterate();
    var successful_conversions: u32 = 0;
    var total_files: u32 = 0;
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        total_files += 1;
        var path_buffer: [256]u8 = undefined;
        const full_path = try std.fmt.bufPrint(path_buffer[0..], "openapi/v3.0/{s}", .{entry.name});
        testOpenApiToUnifiedDocumentConversion(allocator, full_path) catch |err| {
            std.debug.print("✗ Failed to convert OpenAPI v3.0 {s}: {any}\n", .{ full_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Dynamic OpenAPI v3.0 test: {d}/{d} files converted successfully\n", .{ successful_conversions, total_files });
    try std.testing.expect(successful_conversions == total_files);
    try std.testing.expect(total_files > 0);
}

test "dynamically convert all Swagger v2.0 JSON files to UnifiedDocument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const swagger_dir = try std.fs.cwd().openDir("openapi/v2.0", .{ .iterate = true });
    var iterator = swagger_dir.iterate();
    var successful_conversions: u32 = 0;
    var total_files: u32 = 0;
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        total_files += 1;
        var path_buffer: [256]u8 = undefined;
        const full_path = try std.fmt.bufPrint(path_buffer[0..], "openapi/v2.0/{s}", .{entry.name});
        testSwaggerToUnifiedDocumentConversion(allocator, full_path) catch |err| {
            std.debug.print("✗ Failed to convert Swagger v2.0 {s}: {any}\n", .{ full_path, err });
            continue;
        };
        successful_conversions += 1;
    }
    std.debug.print("Dynamic Swagger v2.0 test: {d}/{d} files converted successfully\n", .{ successful_conversions, total_files });
    try std.testing.expect(successful_conversions == total_files);
    try std.testing.expect(total_files > 0);
}

test "memory leak stress test for converters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const iterations = 50;
    for (0..iterations) |i| {
        {
            var openapi_doc = try loadOpenApiDocument(allocator, "openapi/v3.0/petstore.json");
            defer openapi_doc.deinit(allocator);
            var converter = OpenApiConverter.init(allocator);
            var unified = try converter.convert(openapi_doc);
            defer unified.deinit(allocator);
            try std.testing.expect(unified.info.title.len > 0);
        }
        {
            var swagger_doc = try loadSwaggerDocument(allocator, "openapi/v2.0/petstore.json");
            defer swagger_doc.deinit(allocator);
            var converter = SwaggerConverter.init(allocator);
            var unified = try converter.convert(swagger_doc);
            defer unified.deinit(allocator);
            try std.testing.expect(unified.info.title.len > 0);
        }
        if ((i + 1) % 10 == 0) {
            std.debug.print("Completed {d}/{d} stress test iterations\n", .{ i + 1, iterations });
        }
    }
    std.debug.print("✓ Memory leak stress test passed: {d} iterations completed successfully\n", .{iterations});
}
