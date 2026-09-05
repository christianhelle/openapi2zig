const std = @import("std");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");
const security = @import("../models/v2.0/security.zig");
const parameter = @import("../models/v2.0/parameter.zig");

const spec_path = "openapi/v2.0/kitchen-sink.json";

fn loadKitchenSink(allocator: std.mem.Allocator) !models.SwaggerDocument {
    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, spec_path, allocator, .unlimited);
    defer allocator.free(file_contents);
    return try models.SwaggerDocument.parseFromJson(allocator, file_contents);
}

test "kitchen sink 2.0 parses every document level field" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("2.0", parsed.swagger);
    try std.testing.expectEqualStrings("Kitchen Sink", parsed.info.title);
    try std.testing.expectEqualStrings("api.example.com", parsed.host.?);
    try std.testing.expectEqualStrings("/v1", parsed.basePath.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.schemes.?.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.consumes.?.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.produces.?.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.security.?.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.tags.?.len);
    try std.testing.expectEqualStrings("https://example.com/docs", parsed.externalDocs.?.url);
}

test "kitchen sink 2.0 parses shared parameters responses and definitions" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 3), parsed.definitions.?.count());
    try std.testing.expectEqual(@as(u32, 1), parsed.parameters.?.count());
    try std.testing.expectEqual(@as(u32, 1), parsed.responses.?.count());
    try std.testing.expectEqualStrings("pageSize", parsed.parameters.?.get("PageSize").?.name);
    try std.testing.expectEqualStrings(
        "The item was not found",
        parsed.responses.?.get("NotFound").?.description,
    );
}

test "kitchen sink 2.0 parses every security definition flow" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const definitions = parsed.securityDefinitions.?.definitions;
    try std.testing.expectEqual(@as(u32, 7), definitions.count());
    try std.testing.expectEqual(security.SecuritySchemeType.basic, definitions.get("basicAuth").?.type);

    const api_key = definitions.get("apiKeyAuth").?;
    try std.testing.expectEqual(security.SecuritySchemeType.apiKey, api_key.type);
    try std.testing.expectEqual(security.ApiKeyLocation.header, api_key.in.?);
    try std.testing.expectEqual(security.ApiKeyLocation.query, definitions.get("apiKeyQuery").?.in.?);

    const implicit = definitions.get("oauth2Implicit").?;
    try std.testing.expectEqual(security.OAuth2Flow.implicit, implicit.flow.?);
    try std.testing.expectEqualStrings("https://example.com/oauth/authorize", implicit.authorizationUrl.?);
    try std.testing.expectEqualStrings("Read items", implicit.scopes.?.get("read:items").?);

    try std.testing.expectEqual(security.OAuth2Flow.password, definitions.get("oauth2Password").?.flow.?);
    try std.testing.expectEqual(security.OAuth2Flow.application, definitions.get("oauth2Application").?.flow.?);

    const access_code = definitions.get("oauth2AccessCode").?;
    try std.testing.expectEqual(security.OAuth2Flow.accessCode, access_code.flow.?);
    try std.testing.expectEqualStrings("https://example.com/oauth/token", access_code.tokenUrl.?);
    try std.testing.expectEqual(@as(u32, 2), access_code.scopes.?.count());
}

test "kitchen sink 2.0 skips vendor extensions and parses every operation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 2), parsed.paths.path_items.count());
    try std.testing.expect(parsed.paths.path_items.get("x-vendor-extension") == null);

    const items = parsed.paths.path_items.get("/items").?;
    try std.testing.expect(items.get != null);
    try std.testing.expect(items.put != null);
    try std.testing.expect(items.post != null);
    try std.testing.expect(items.delete != null);
    try std.testing.expect(items.options != null);
    try std.testing.expect(items.head != null);
    try std.testing.expect(items.patch != null);
    try std.testing.expectEqual(@as(usize, 1), items.parameters.?.len);

    try std.testing.expectEqualStrings("#/paths/~1items", parsed.paths.path_items.get("/ping").?.ref.?);
}

test "kitchen sink 2.0 parses operation metadata" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const get = parsed.paths.path_items.get("/items").?.get.?;
    try std.testing.expectEqualStrings("listItems", get.operationId.?);
    try std.testing.expectEqual(@as(usize, 1), get.tags.?.len);
    try std.testing.expectEqual(@as(usize, 1), get.consumes.?.len);
    try std.testing.expectEqual(@as(usize, 1), get.produces.?.len);
    try std.testing.expectEqual(@as(usize, 1), get.schemes.?.len);
    try std.testing.expectEqual(false, get.deprecated.?);
    try std.testing.expectEqual(@as(usize, 1), get.security.?.len);
    try std.testing.expectEqualStrings("https://example.com/docs/list-items", get.externalDocs.?.url);
}

test "kitchen sink 2.0 parses nested parameter items" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const tags = parsed.paths.path_items.get("/items").?.get.?.parameters.?[0];
    try std.testing.expectEqual(parameter.ParameterLocation.query, tags.in);
    try std.testing.expectEqual(parameter.PrimitiveType.array, tags.type.?);
    try std.testing.expectEqual(parameter.CollectionFormat.multi, tags.collectionFormat.?);
    try std.testing.expectEqual(true, tags.allowEmptyValue.?);

    const outer_items = tags.items.?;
    try std.testing.expectEqual(parameter.PrimitiveType.array, outer_items.type);
    try std.testing.expectEqual(parameter.CollectionFormat.csv, outer_items.collectionFormat.?);

    const inner_items = outer_items.items.?;
    try std.testing.expectEqual(parameter.PrimitiveType.string, inner_items.type);
    try std.testing.expectEqualStrings("uuid", inner_items.format.?);
    try std.testing.expectEqualStrings("^[a-z]+$", inner_items.pattern.?);
    try std.testing.expectEqual(@as(u32, 32), inner_items.maxLength.?);
    try std.testing.expectEqual(@as(u32, 1), inner_items.minLength.?);
    try std.testing.expectEqual(@as(f64, 10), inner_items.maximum.?);
    try std.testing.expectEqual(@as(f64, 1), inner_items.minimum.?);
    try std.testing.expectEqual(@as(u32, 5), inner_items.maxItems.?);
    try std.testing.expectEqual(true, inner_items.uniqueItems.?);
    try std.testing.expectEqual(@as(f64, 1), inner_items.multipleOf.?);
    try std.testing.expectEqual(@as(usize, 2), inner_items.enum_values.?.len);
    try std.testing.expect(inner_items.default != null);
}

test "kitchen sink 2.0 parses numeric parameter constraints" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const count = parsed.paths.path_items.get("/items").?.get.?.parameters.?[1];
    try std.testing.expectEqual(@as(f64, 100), count.maximum.?);
    try std.testing.expectEqual(@as(f64, 0), count.minimum.?);
    try std.testing.expectEqual(@as(f64, 2), count.multipleOf.?);
    try std.testing.expectEqual(false, count.exclusiveMaximum.?);
    try std.testing.expectEqual(false, count.exclusiveMinimum.?);
    try std.testing.expectEqual(@as(u32, 3), count.maxLength.?);
    try std.testing.expectEqual(@as(u32, 1), count.minLength.?);
    try std.testing.expectEqual(@as(u32, 4), count.maxItems.?);
    try std.testing.expectEqual(@as(u32, 1), count.minItems.?);
    try std.testing.expectEqual(false, count.uniqueItems.?);
    try std.testing.expectEqualStrings("^[0-9]+$", count.pattern.?);
    try std.testing.expectEqual(@as(usize, 2), count.enum_values.?.len);
}

test "kitchen sink 2.0 parses body and form data parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const body = parsed.paths.path_items.get("/items").?.post.?.parameters.?[0];
    try std.testing.expectEqual(parameter.ParameterLocation.body, body.in);
    try std.testing.expectEqual(true, body.required);
    try std.testing.expectEqualStrings("#/definitions/Item", body.schema.?.ref.?);

    const file = parsed.paths.path_items.get("/items").?.put.?.parameters.?[0];
    try std.testing.expectEqual(parameter.ParameterLocation.formData, file.in);
    try std.testing.expectEqual(parameter.PrimitiveType.file, file.type.?);
}

test "kitchen sink 2.0 parses response schema headers and examples" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const responses = parsed.paths.path_items.get("/items").?.get.?.responses;
    const ok = responses.get("200").?;
    try std.testing.expectEqualStrings("array", ok.schema.?.type.?);
    try std.testing.expectEqual(@as(u32, 1), ok.headers.?.count());
    try std.testing.expectEqualStrings("integer", ok.headers.?.get("X-Rate-Limit").?.type);
    try std.testing.expectEqualStrings("int32", ok.headers.?.get("X-Rate-Limit").?.format.?);
    try std.testing.expectEqual(@as(u32, 1), ok.examples.?.count());
    // Swagger 2.0 response $refs are not resolved by the parser: the entry is kept
    // with an empty description and no schema.
    try std.testing.expectEqualStrings("", responses.get("404").?.description);
    try std.testing.expect(responses.get("404").?.schema == null);
}

test "kitchen sink 2.0 parses definition schema keywords" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const item = parsed.definitions.?.get("Item").?;
    try std.testing.expectEqualStrings("Item", item.title.?);
    try std.testing.expectEqualStrings("kind", item.discriminator.?);
    try std.testing.expectEqual(@as(usize, 1), item.required.?.len);
    try std.testing.expectEqualStrings("item", item.xml.?.name.?);
    try std.testing.expectEqualStrings("https://example.com/docs/item", item.externalDocs.?.url);
    try std.testing.expect(item.example != null);

    const properties = item.properties.?;
    try std.testing.expectEqual(true, properties.get("id").?.readOnly.?);
    try std.testing.expectEqual(@as(u32, 64), properties.get("name").?.maxLength.?);
    try std.testing.expectEqual(@as(f64, 100), properties.get("count").?.maximum.?);
    try std.testing.expectEqual(@as(f64, 2), properties.get("count").?.multipleOf.?);
    try std.testing.expectEqual(@as(u32, 10), properties.get("tags").?.maxItems.?);
    try std.testing.expectEqual(true, properties.get("tags").?.uniqueItems.?);
    try std.testing.expect(properties.get("tags").?.items != null);
    try std.testing.expectEqual(@as(u32, 5), properties.get("extra").?.maxProperties.?);
    try std.testing.expect(properties.get("extra").?.additionalProperties != null);
    try std.testing.expectEqual(@as(usize, 2), properties.get("status").?.enum_values.?.len);

    try std.testing.expectEqual(@as(usize, 2), parsed.definitions.?.get("Combo").?.allOf.?.len);
}
