const std = @import("std");
const openapi2zig = @import("../lib.zig");
const test_utils = @import("test_utils.zig");

// The three OpenAPI 3.x converters share a shape but not code, so each one is
// run over the same spec: cookie and unrecognised parameter locations fall back
// to query, an unknown schema type falls back to string, and a response whose
// content is not JSON still yields the first media type's schema.

fn convert(allocator: std.mem.Allocator, path: []const u8) !openapi2zig.UnifiedDocument {
    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .unlimited);
    defer allocator.free(file_contents);
    return openapi2zig.parseToUnified(allocator, file_contents);
}

fn expectSharedConversions(allocator: std.mem.Allocator, path: []const u8) !void {
    var document = try convert(allocator, path);
    defer document.deinit(allocator);

    const operation = document.paths.get("/items").?.get.?;
    for (operation.parameters.?) |parameter| {
        // Cookie parameters, and anything the converter does not recognise, are
        // treated as query parameters.
        try std.testing.expectEqual(openapi2zig.ParameterLocation.query, parameter.location);
    }

    try std.testing.expectEqual(
        openapi2zig.SchemaType.string,
        document.schemas.?.get("Mystery").?.type.?,
    );

    // A non-JSON response body still contributes its schema.
    const csv_response = operation.responses.get("400").?;
    try std.testing.expectEqual(openapi2zig.SchemaType.string, csv_response.schema.?.type.?);

    // A schema's own properties always survive conversion.
    const merged = document.schemas.?.get("Merged").?.properties.?;
    try std.testing.expect(merged.get("own") != null);
    try std.testing.expectEqual(openapi2zig.SchemaType.string, merged.get("replaced").?.type.?);
}

test "the v3.0 converter normalises locations, unknown types and non-JSON responses" {
    var gpa = test_utils.createTestAllocator();
    try expectSharedConversions(gpa.allocator(), "openapi/v3.0/converter-edge-cases.json");
}

test "the v3.1 converter normalises locations, unknown types and non-JSON responses" {
    var gpa = test_utils.createTestAllocator();
    try expectSharedConversions(gpa.allocator(), "openapi/v3.1/converter-edge-cases.json");
}

test "the v3.2 converter normalises locations, unknown types and non-JSON responses" {
    var gpa = test_utils.createTestAllocator();
    try expectSharedConversions(gpa.allocator(), "openapi/v3.2/converter-edge-cases.json");
}

// The 3.0 and 3.1 converters merge allOf members; the 3.2 converter does not
// implement allOf at all and keeps only the schema's own properties.
fn expectMergedAllOf(allocator: std.mem.Allocator, path: []const u8) !void {
    var document = try convert(allocator, path);
    defer document.deinit(allocator);

    const merged = document.schemas.?.get("Merged").?;
    const properties = merged.properties.?;

    try std.testing.expect(properties.get("id") != null);
    try std.testing.expect(properties.get("shared") != null);
    try std.testing.expect(properties.get("extra") != null);
    try std.testing.expect(properties.get("inline_prop") != null);
    try std.testing.expect(properties.get("own") != null);

    // The schema's own definition of a property replaces the inherited one.
    try std.testing.expectEqual(openapi2zig.SchemaType.string, properties.get("replaced").?.type.?);

    // "id" is required by both Base and Extra but must only be listed once.
    var id_count: usize = 0;
    for (merged.required.?) |name| {
        if (std.mem.eql(u8, name, "id")) id_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), id_count);
    try std.testing.expectEqual(@as(usize, 2), merged.required.?.len);
}

test "the v3.0 converter merges allOf members into one schema" {
    var gpa = test_utils.createTestAllocator();
    try expectMergedAllOf(gpa.allocator(), "openapi/v3.0/converter-edge-cases.json");
}

test "the v3.1 converter merges allOf members into one schema" {
    var gpa = test_utils.createTestAllocator();
    try expectMergedAllOf(gpa.allocator(), "openapi/v3.1/converter-edge-cases.json");
}

test "the v3.2 converter does not implement allOf" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var document = try convert(allocator, "openapi/v3.2/converter-edge-cases.json");
    defer document.deinit(allocator);

    const properties = document.schemas.?.get("Merged").?.properties.?;
    try std.testing.expect(properties.get("own") != null);
    try std.testing.expect(properties.get("id") == null);
    try std.testing.expect(properties.get("inline_prop") == null);
}
