const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{}," ++
    "\"components\":{\"schemas\":{" ++
    "\"Pet\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}," ++
    "\"Dog\":{\"type\":\"object\",\"properties\":{\"bark\":{\"type\":\"string\"}}}," ++
    "\"Owner\":{\"type\":\"object\",\"required\":[\"parent\"],\"properties\":{" ++
    "\"parent\":{\"description\":\"The parent\",\"anyOf\":[{\"$ref\":\"#/components/schemas/Pet\"},{\"type\":\"object\",\"nullable\":true}]}," ++
    "\"value\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"integer\"}]}," ++
    "\"animal\":{\"oneOf\":[{\"$ref\":\"#/components/schemas/Pet\"},{\"$ref\":\"#/components/schemas/Dog\"}],\"discriminator\":{\"propertyName\":\"kind\"}}}}}}}";

test "openapi 3.0 collapses the nullable reference idiom" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const owner = unified.schemas.?.get("Owner").?;
    const parent = owner.properties.?.get("parent").?;
    try testing.expectEqualStrings("#/components/schemas/Pet", parent.ref.?);
    try testing.expect(parent.nullable);
    try testing.expect(parent.any_of == null);
}

test "openapi 3.0 keeps oneOf and discriminators" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const owner = unified.schemas.?.get("Owner").?;
    const value = owner.properties.?.get("value").?;
    try testing.expectEqual(@as(usize, 2), value.one_of.?.len);

    const animal = owner.properties.?.get("animal").?;
    try testing.expectEqualStrings("kind", animal.discriminator_property.?);
    try testing.expectEqual(@as(usize, 2), animal.one_of_refs.?.len);
    try testing.expectEqualStrings("Dog", animal.one_of_refs.?[1]);
}

test "openapi 3.0 nullable reference becomes an optional model field" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "parent: ?Pet,") != null);
}

test "openapi 3.2 keeps oneOf, anyOf and discriminators" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;
    var parsed = try models.OpenApi32Document.parseFromJson(allocator, spec32);
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const owner = unified.schemas.?.get("Owner").?;
    const value = owner.properties.?.get("value").?;
    try testing.expectEqual(@as(usize, 2), value.one_of.?.len);

    const animal = owner.properties.?.get("animal").?;
    try testing.expectEqualStrings("kind", animal.discriminator_property.?);
    try testing.expectEqualStrings("Dog", animal.one_of_refs.?[1]);

    const parent = owner.properties.?.get("parent").?;
    try testing.expectEqual(@as(usize, 2), parent.any_of.?.len);
}

const spec32 =
    "{\"openapi\":\"3.2.0\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{}," ++
    "\"components\":{\"schemas\":{" ++
    "\"Pet\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}," ++
    "\"Dog\":{\"type\":\"object\",\"properties\":{\"bark\":{\"type\":\"string\"}}}," ++
    "\"Owner\":{\"type\":\"object\",\"properties\":{" ++
    "\"parent\":{\"anyOf\":[{\"$ref\":\"#/components/schemas/Pet\"},{\"type\":\"null\"}]}," ++
    "\"value\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"integer\"}]}," ++
    "\"animal\":{\"oneOf\":[{\"$ref\":\"#/components/schemas/Pet\"},{\"$ref\":\"#/components/schemas/Dog\"}],\"discriminator\":{\"propertyName\":\"kind\"}}}}}}}";

test "openapi 3.0 and 3.2 keep string enum values" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;
    const body = "\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{},\"components\":{\"schemas\":{\"Pet\":{\"type\":\"object\",\"properties\":{\"status\":{\"type\":\"string\",\"enum\":[\"available\",\"sold\"]}}}}}}";

    var parsed30 = try models.OpenApiDocument.parseFromJson(allocator, "{\"openapi\":\"3.0.3\"," ++ body);
    defer parsed30.deinit(allocator);
    var converter30 = OpenApiConverter.init(allocator);
    var unified30 = try converter30.convert(parsed30);
    defer unified30.deinit(allocator);
    const status30 = unified30.schemas.?.get("Pet").?.properties.?.get("status").?;
    try testing.expectEqual(@as(usize, 2), status30.enum_values.?.len);
    try testing.expectEqualStrings("sold", status30.enum_values.?[1].string);

    var parsed32 = try models.OpenApi32Document.parseFromJson(allocator, "{\"openapi\":\"3.2.0\"," ++ body);
    defer parsed32.deinit(allocator);
    var converter32 = OpenApi32Converter.init(allocator);
    var unified32 = try converter32.convert(parsed32);
    defer unified32.deinit(allocator);
    const status32 = unified32.schemas.?.get("Pet").?.properties.?.get("status").?;
    try testing.expectEqual(@as(usize, 2), status32.enum_values.?.len);
}
