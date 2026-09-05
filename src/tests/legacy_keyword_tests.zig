const std = @import("std");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");

// `nullable` and boolean `exclusiveMaximum`/`exclusiveMinimum` were dropped in
// OpenAPI 3.1, but specs converted from 3.0 keep carrying them, so the 3.1 and
// 3.2 parsers still read both. The kitchen-sink fixtures stay conformant; these
// keep the lenient paths covered.

test "the v3.1 parser still reads 3.0 era nullable and boolean bounds" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "openapi/v3.1/legacy-30-keywords.json",
        allocator,
        .unlimited,
    );
    defer allocator.free(contents);
    var parsed = try models.OpenApi31Document.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);

    const properties = parsed.components.?.schemas.?.get("LegacyItem").?.schema.properties.?;
    try std.testing.expectEqual(true, properties.get("name").?.schema.nullable.?);

    const count = properties.get("count").?.schema;
    try std.testing.expectEqual(false, count.exclusiveMaximum.?);
    try std.testing.expectEqual(true, count.exclusiveMinimum.?);

    // A license with a url and no identifier is the conformant 3.1 spelling.
    try std.testing.expectEqualStrings("https://opensource.org/licenses/MIT", parsed.info.license.?.url.?);
    try std.testing.expect(parsed.info.license.?.identifier == null);
}

test "the v3.2 parser still reads 3.0 era nullable and boolean bounds" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "openapi/v3.2/legacy-30-keywords.json",
        allocator,
        .unlimited,
    );
    defer allocator.free(contents);
    var parsed = try models.OpenApi32Document.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);

    const properties = parsed.components.?.schemas.?.get("LegacyItem").?.schema.properties.?;
    try std.testing.expectEqual(true, properties.get("name").?.schema.nullable.?);

    const count = properties.get("count").?.schema;
    try std.testing.expectEqual(false, count.exclusiveMaximum.?);
    try std.testing.expectEqual(true, count.exclusiveMinimum.?);

    try std.testing.expectEqualStrings("https://opensource.org/licenses/MIT", parsed.info.license.?.url.?);
    try std.testing.expect(parsed.info.license.?.identifier == null);
}
