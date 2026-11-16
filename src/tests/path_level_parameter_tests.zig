const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("../generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;
const SwaggerConverter = @import("../generators/converters/swagger_converter.zig").SwaggerConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn spec3(comptime version: []const u8) []const u8 {
    return "{\"openapi\":\"" ++ version ++ "\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{" ++
        "\"/users/{id}/posts\":{" ++
        "\"parameters\":[" ++
        "{\"name\":\"id\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}}," ++
        "{\"name\":\"limit\",\"in\":\"query\",\"schema\":{\"type\":\"integer\"}}]," ++
        "\"get\":{\"operationId\":\"listPosts\",\"parameters\":[" ++
        "{\"name\":\"limit\",\"in\":\"query\",\"required\":true,\"schema\":{\"type\":\"string\"}}," ++
        "{\"name\":\"expand\",\"in\":\"query\",\"schema\":{\"type\":\"string\"}}]," ++
        "\"responses\":{\"200\":{\"description\":\"ok\"}}}," ++
        "\"delete\":{\"operationId\":\"deletePosts\",\"responses\":{\"204\":{\"description\":\"gone\"}}}}}}";
}

fn expectMergedParameters(unified: anytype) !void {
    const item = unified.paths.get("/users/{id}/posts").?;

    // Operation-level `limit` overrides the path-level one; `id` is inherited.
    const list = item.get.?.parameters.?;
    try testing.expectEqual(@as(usize, 3), list.len);
    try testing.expectEqualStrings("id", list[0].name);
    try testing.expectEqualStrings("limit", list[1].name);
    try testing.expect(list[1].required);
    try testing.expectEqualStrings("expand", list[2].name);

    // An operation without parameters of its own inherits every path-level one.
    const inherited = item.delete.?.parameters.?;
    try testing.expectEqual(@as(usize, 2), inherited.len);
    try testing.expectEqualStrings("id", inherited[0].name);
    try testing.expectEqualStrings("limit", inherited[1].name);
}

test "openapi 3.0 operations inherit path-level parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec3("3.0.3"));
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try expectMergedParameters(unified);
}

test "generated functions take inherited path parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec3("3.0.3"));
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub fn deletePosts(client: *Client, id: []const u8") != null);
}
