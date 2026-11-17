const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn spec(comptime security: []const u8) []const u8 {
    return "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{" ++
        "\"/users\":{\"get\":{\"operationId\":\"listUsers\",\"parameters\":[" ++
        "{\"name\":\"ConsistencyLevel\",\"in\":\"header\",\"required\":true,\"schema\":{\"type\":\"string\"}}," ++
        "{\"name\":\"X-Trace\",\"in\":\"header\",\"schema\":{\"type\":\"string\"}}]," ++
        "\"responses\":{\"200\":{\"description\":\"ok\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/UserPage\"}}}}}," ++
        "\"x-ms-pageable\":{\"nextLinkName\":\"next\\\"link\"}}}}," ++
        "\"components\":{" ++ security ++ "\"schemas\":{\"UserPage\":{\"type\":\"object\",\"properties\":{\"next\\\"link\":{\"type\":\"string\"}}}}}}";
}

fn generate(allocator: std.mem.Allocator, json: []const u8) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, json);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .pagination = true });
    defer generator.deinit();
    return generator.generate(unified);
}

test "a pager carries the header parameters and escapes the link property" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generate(allocator, spec(""));
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "!Pager(UserPage, \"next\\\"link\", true)") != null);
    try testing.expect(std.mem.indexOf(u8, code, "try page_headers.append(allocator, .{ .name = \"ConsistencyLevel\", .value = ConsistencyLevel });") != null);
    try testing.expect(std.mem.indexOf(u8, code, "if (@\"X-Trace\") |header_value| try page_headers.append(allocator, .{ .name = \"X-Trace\", .value = header_value });") != null);
    try testing.expect(std.mem.indexOf(u8, code, ".init(client, first_page, try page_headers.toOwnedSlice(allocator))") != null);
}

test "a pager for an api key operation sends the key header instead of a bearer token" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generate(allocator, spec("\"securitySchemes\":{\"key\":{\"type\":\"apiKey\",\"in\":\"header\",\"name\":\"X-Api-Key\"}},"));
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "!Pager(UserPage, \"next\\\"link\", false)") != null);
    try testing.expect(std.mem.indexOf(u8, code, "if (client.api_key.len > 0) try page_headers.append(allocator, .{ .name = \"X-Api-Key\", .value = client.api_key });") != null);
}
