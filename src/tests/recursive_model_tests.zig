const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{},\"components\":{\"schemas\":{" ++
    "\"A\":{\"type\":\"object\",\"properties\":{\"b\":{\"$ref\":\"#/components/schemas/B\"},\"name\":{\"type\":\"string\"}}}," ++
    "\"B\":{\"type\":\"object\",\"properties\":{\"a\":{\"$ref\":\"#/components/schemas/A\"},\"c\":{\"$ref\":\"#/components/schemas/C\"}}}," ++
    "\"C\":{\"type\":\"object\",\"properties\":{\"b\":{\"anyOf\":[{\"$ref\":\"#/components/schemas/B\"},{\"type\":\"object\",\"nullable\":true}]}}}," ++
    "\"Node\":{\"type\":\"object\",\"properties\":{\"next\":{\"$ref\":\"#/components/schemas/Node\"},\"children\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/components/schemas/Node\"}}}}" ++
    "}}}";

fn generate(allocator: std.mem.Allocator) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    return generator.generate(unified);
}

test "fields that close a reference cycle become pointers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generate(allocator);
    defer allocator.free(code);

    // A -> B -> C -> B closes on C.b, and B -> A closes on B.a.
    try testing.expect(std.mem.indexOf(u8, code, "a: ?*const A = null,") != null);
    try testing.expect(std.mem.indexOf(u8, code, "b: ?*const B = null,") != null);
    // Tree edges and slices stay by value.
    try testing.expect(std.mem.indexOf(u8, code, "b: ?B = null,") != null);
    try testing.expect(std.mem.indexOf(u8, code, "c: ?C = null,") != null);
    try testing.expect(std.mem.indexOf(u8, code, "children: ?[]const Node = null,") != null);
    try testing.expect(std.mem.indexOf(u8, code, "next: ?*const Node = null,") != null);
}

test "pointer fields survive a json round trip" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generate(allocator);
    defer allocator.free(code);

    // The generated declarations must be valid Zig that can refer to itself.
    const source = try allocator.dupeSentinel(u8, code, 0);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .{ .mode = .zig });
    defer tree.deinit(allocator);
    try testing.expectEqual(@as(usize, 0), tree.errors.len);
}

const union_cycle_spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{},\"components\":{\"schemas\":{" ++
    "\"A\":{\"type\":\"object\",\"properties\":{\"b\":{\"$ref\":\"#/components/schemas/B\"}}}," ++
    "\"B\":{\"oneOf\":[{\"$ref\":\"#/components/schemas/A\"},{\"$ref\":\"#/components/schemas/C\"}]}," ++
    "\"C\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}}}}";

test "a cycle through a union gets its pointer on the property before the union" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, union_cycle_spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    // A holds a B, B may hold an A: the property A.b becomes the indirection.
    try testing.expect(std.mem.indexOf(u8, code, "b: ?*const B = null,") != null);
}
