const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("../generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn spec(comptime version: []const u8) []const u8 {
    return "{\"openapi\":\"" ++ version ++ "\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{" ++
        "\"/pets\":{\"get\":{\"operationId\":\"listPets\",\"responses\":{" ++
        "\"2XX\":{\"$ref\":\"#/components/responses/PetList\"}," ++
        "\"4XX\":{\"$ref\":\"#/components/responses/Failure\"}}}}," ++
        "\"/pets/{id}\":{\"get\":{\"operationId\":\"getPet\",\"parameters\":[{\"name\":\"id\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}}]," ++
        "\"responses\":{\"200\":{\"$ref\":\"#/components/responses/PetAlias\"}}}}}," ++
        "\"components\":{\"schemas\":{\"Pet\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}," ++
        "\"Error\":{\"type\":\"object\",\"properties\":{\"message\":{\"type\":\"string\"}}}}," ++
        "\"responses\":{" ++
        "\"PetList\":{\"description\":\"A list of pets\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/components/schemas/Pet\"}}}}}," ++
        "\"Failure\":{\"description\":\"Something failed\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/Error\"}}}}," ++
        "\"PetAlias\":{\"$ref\":\"#/components/responses/PetOne\"}," ++
        "\"PetOne\":{\"description\":\"One pet\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/Pet\"}}}}}}}";
}

fn expectResolved(unified: anytype) !void {
    const list = unified.paths.get("/pets").?.get.?;
    const ok = list.responses.get("2XX").?;
    try testing.expectEqualStrings("A list of pets", ok.description);
    try testing.expect(ok.schema != null);

    const failure = list.responses.get("4XX").?;
    try testing.expectEqualStrings("Something failed", failure.description);
    try testing.expectEqualStrings("#/components/schemas/Error", failure.schema.?.ref.?);

    // A components entry that is itself a reference is followed to its target.
    const one = unified.paths.get("/pets/{id}").?.get.?.responses.get("200").?;
    try testing.expectEqualStrings("One pet", one.description);
    try testing.expectEqualStrings("#/components/schemas/Pet", one.schema.?.ref.?);
}

test "openapi 3.0 resolves response references" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec("3.0.3"));
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    try expectResolved(unified);
}

test "wildcard success responses give operations a return type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec("3.0.3"));
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(client: *Client, id: []const u8) !Owned(Pet)") != null);
}
