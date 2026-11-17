const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn generateModels(allocator: std.mem.Allocator, spec: []const u8) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    return generator.generate(unified);
}

const nullable_component_spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{},\"components\":{\"schemas\":{" ++
    "\"Pet\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}," ++
    "\"NullablePet\":{\"anyOf\":[{\"$ref\":\"#/components/schemas/Pet\"},{\"type\":\"object\",\"nullable\":true}]}," ++
    "\"Holder\":{\"type\":\"object\",\"properties\":{\"pet\":{\"$ref\":\"#/components/schemas/NullablePet\"}}}}}}";

test "a component that is a nullable reference is still declared" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateModels(allocator, nullable_component_spec);
    defer allocator.free(code);
    try testing.expect(std.mem.indexOf(u8, code, "pub const NullablePet = Pet;") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pet: ?NullablePet = null,") != null);
}

const sibling_spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{},\"components\":{\"schemas\":{" ++
    "\"Pet\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}," ++
    "\"Wrapper\":{\"type\":\"object\",\"required\":[\"extra\"],\"properties\":{\"extra\":{\"type\":\"string\"}}," ++
    "\"anyOf\":[{\"$ref\":\"#/components/schemas/Pet\"},{\"type\":\"object\",\"nullable\":true}]}}}}";

const default_spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{},\"components\":{\"schemas\":{" ++
    "\"Thing\":{\"type\":\"object\",\"required\":[\"code\"],\"properties\":{\"code\":{\"type\":\"string\",\"default\":\"a\\u0000b\\bc\"}}}}}}";

test "string defaults with control characters stay valid Zig" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateModels(allocator, default_spec);
    defer allocator.free(code);
    try testing.expect(std.mem.indexOf(u8, code, "code: []const u8 = \"a\\x00b\\x08c\",") != null);

    const source = try allocator.dupeSentinel(u8, code, 0);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .{ .mode = .zig });
    defer tree.deinit(allocator);
    try testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "a nullable reference with sibling properties keeps them" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, sibling_spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const wrapper = unified.schemas.?.get("Wrapper").?;
    try testing.expect(wrapper.ref == null);
    try testing.expect(wrapper.properties.?.contains("extra"));
    try testing.expectEqualStrings("extra", wrapper.required.?[0]);
    try testing.expectEqual(@as(usize, 2), wrapper.any_of.?.len);
}

test "inherited swagger body parameters follow the operation's consumes" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const SwaggerConverter = @import("../generators/converters/swagger_converter.zig").SwaggerConverter;
    const swagger_spec =
        "{\"swagger\":\"2.0\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"consumes\":[\"application/json\"],\"paths\":{" ++
        "\"/blob\":{\"parameters\":[{\"name\":\"payload\",\"in\":\"body\",\"required\":true,\"schema\":{\"type\":\"string\"}}]," ++
        "\"put\":{\"operationId\":\"putBlob\",\"consumes\":[\"text/plain\"],\"responses\":{\"204\":{\"description\":\"ok\"}}}}}}";
    var parsed = try models.SwaggerDocument.parseFromJson(allocator, swagger_spec);
    defer parsed.deinit(allocator);
    var converter = SwaggerConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const params = unified.paths.get("/blob").?.put.?.parameters.?;
    try testing.expectEqualStrings("text/plain", params[0].content_type.?);
}
