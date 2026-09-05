const std = @import("std");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");

const spec_path = "openapi/v3.1/kitchen-sink.json";

fn loadKitchenSink(allocator: std.mem.Allocator) !models.OpenApi31Document {
    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, spec_path, allocator, .unlimited);
    defer allocator.free(file_contents);
    return try models.OpenApi31Document.parseFromJson(allocator, file_contents);
}

test "kitchen sink parses every document level field" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("3.1.0", parsed.openapi);
    try std.testing.expectEqualStrings("Kitchen Sink", parsed.info.title);
    try std.testing.expectEqualStrings("MIT", parsed.info.license.?.identifier.?);
    try std.testing.expectEqualStrings("api@example.com", parsed.info.contact.?.email.?);
    try std.testing.expectEqualStrings("https://json-schema.org/draft/2020-12/schema", parsed.jsonSchemaDialect.?);
    try std.testing.expectEqualStrings("https://example.com/docs", parsed.externalDocs.?.url);
    try std.testing.expectEqual(@as(usize, 1), parsed.servers.?.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.security.?.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.tags.?.len);
}

test "kitchen sink parses server variables" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const variables = parsed.servers.?[0].variables.?;
    const host = variables.get("host").?;
    try std.testing.expectEqualStrings("api.example.com", host.default);
    try std.testing.expectEqual(@as(usize, 2), host.enum_values.?.len);
}

test "kitchen sink parses every path item operation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const items = parsed.paths.?.path_items.get("/items").?;
    try std.testing.expect(items.get != null);
    try std.testing.expect(items.put != null);
    try std.testing.expect(items.post != null);
    try std.testing.expect(items.delete != null);
    try std.testing.expect(items.options != null);
    try std.testing.expect(items.head != null);
    try std.testing.expect(items.patch != null);
    try std.testing.expect(items.trace != null);
    try std.testing.expectEqual(@as(usize, 1), items.servers.?.len);
    try std.testing.expectEqual(@as(usize, 2), items.parameters.?.len);

    const ping = parsed.paths.?.path_items.get("/ping").?;
    try std.testing.expectEqualStrings("#/components/pathItems/Ping", ping.ref.?);
}

test "kitchen sink parses operation metadata" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const get = parsed.paths.?.path_items.get("/items").?.get.?;
    try std.testing.expectEqualStrings("listItems", get.operationId.?);
    try std.testing.expectEqual(@as(usize, 1), get.tags.?.len);
    try std.testing.expectEqual(false, get.deprecated.?);
    try std.testing.expectEqual(@as(usize, 1), get.security.?.len);
    try std.testing.expectEqual(@as(usize, 1), get.servers.?.len);
    try std.testing.expectEqualStrings("https://example.com/docs/list-items", get.externalDocs.?.url);
    try std.testing.expectEqual(@as(u32, 2), get.callbacks.?.count());
}

test "kitchen sink parses parameter styles and examples" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const get = parsed.paths.?.path_items.get("/items").?.get.?;
    const filter = get.parameters.?[0].parameter;
    try std.testing.expectEqualStrings("filter", filter.name);
    try std.testing.expectEqualStrings("query", filter.in_field);
    try std.testing.expectEqualStrings("form", filter.style.?);
    try std.testing.expectEqual(true, filter.explode.?);
    try std.testing.expectEqual(true, filter.allowEmptyValue.?);
    try std.testing.expectEqual(false, filter.allowReserved.?);
    try std.testing.expectEqual(@as(u32, 2), filter.examples.?.count());

    const cursor = get.parameters.?[1].parameter;
    try std.testing.expect(cursor.content.?.get("application/json") != null);
}

test "kitchen sink parses response headers content and links" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const responses = parsed.paths.?.path_items.get("/items").?.get.?.responses.?;
    const ok = responses.status_codes.get("200").?.response;
    try std.testing.expectEqual(@as(u32, 3), ok.headers.?.count());
    try std.testing.expectEqual(@as(u32, 2), ok.links.?.count());

    const rate_limit = ok.headers.?.get("X-Rate-Limit").?.header;
    try std.testing.expectEqual(true, rate_limit.required.?);
    try std.testing.expectEqualStrings("simple", rate_limit.style.?);
    try std.testing.expectEqual(@as(u32, 1), rate_limit.examples.?.count());
    try std.testing.expect(ok.headers.?.get("X-Cursor").?.header.content != null);
    try std.testing.expectEqualStrings("#/components/headers/RequestId", ok.headers.?.get("X-Request-Id").?.reference.ref);

    const json_media = ok.content.?.get("application/json").?;
    try std.testing.expectEqual(@as(u32, 3), json_media.examples.?.count());
    try std.testing.expectEqualStrings(
        "https://example.com/examples/items.json",
        json_media.examples.?.get("external").?.example.externalValue.?,
    );

    const next = ok.links.?.get("next").?.link;
    try std.testing.expectEqualStrings("listItems", next.operationId.?);
    try std.testing.expect(next.parameters.?.get("cursor") != null);
    try std.testing.expect(next.requestBody != null);
    try std.testing.expectEqualStrings("https://items.example.com", next.server.?.url);
    try std.testing.expectEqualStrings("#/components/links/GetItemById", ok.links.?.get("byId").?.reference.ref);

    try std.testing.expectEqualStrings("#/components/responses/NotFound", responses.status_codes.get("404").?.reference.ref);
}

test "kitchen sink parses request body encoding" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const post = parsed.paths.?.path_items.get("/items").?.post.?;
    const body = post.requestBody.?.request_body;
    try std.testing.expectEqual(true, body.required.?);
    const multipart = body.content.get("multipart/form-data").?;
    const file_encoding = multipart.encoding.?.get("file").?;
    try std.testing.expectEqualStrings("application/octet-stream", file_encoding.contentType.?);
    try std.testing.expectEqualStrings("form", file_encoding.style.?);
    try std.testing.expectEqual(false, file_encoding.explode.?);
    try std.testing.expectEqual(false, file_encoding.allowReserved.?);
    try std.testing.expectEqual(@as(u32, 2), file_encoding.headers.?.count());

    const put = parsed.paths.?.path_items.get("/items").?.put.?;
    try std.testing.expectEqualStrings("#/components/requestBodies/ItemBody", put.requestBody.?.reference.ref);
}

test "kitchen sink parses inline and referenced callbacks" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const callbacks = parsed.paths.?.path_items.get("/items").?.get.?.callbacks.?;
    const on_data = callbacks.get("onData").?.callback;
    try std.testing.expect(on_data.path_items.get("{$request.body#/callbackUrl}").?.post != null);
    try std.testing.expectEqualStrings("#/components/callbacks/OnEvent", callbacks.get("onEvent").?.reference.ref);
}

test "kitchen sink parses webhooks" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const webhooks = parsed.webhooks.?;
    try std.testing.expectEqual(@as(u32, 2), webhooks.count());
    try std.testing.expect(webhooks.get("itemCreated").?.path_item.post != null);
    try std.testing.expectEqualStrings("#/components/pathItems/Ping", webhooks.get("sharedHook").?.reference.ref);
}

test "kitchen sink parses every components map" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const components = parsed.components.?;
    try std.testing.expectEqual(@as(u32, 5), components.schemas.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.responses.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.parameters.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.examples.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.requestBodies.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.headers.?.count());
    try std.testing.expectEqual(@as(u32, 6), components.securitySchemes.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.links.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.callbacks.?.count());
    try std.testing.expectEqual(@as(u32, 2), components.pathItems.?.count());
}

test "kitchen sink parses every security scheme type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const schemes = parsed.components.?.securitySchemes.?;
    const api_key = schemes.get("apiKeyAuth").?.security_scheme.api_key;
    try std.testing.expectEqualStrings("X-API-Key", api_key.name);
    try std.testing.expectEqualStrings("header", api_key.in_field);

    const basic = schemes.get("basicAuth").?.security_scheme.http;
    try std.testing.expectEqualStrings("basic", basic.scheme);
    const bearer = schemes.get("bearerAuth").?.security_scheme.http;
    try std.testing.expectEqualStrings("JWT", bearer.bearerFormat.?);

    const oidc = schemes.get("oidcAuth").?.security_scheme.openIdConnect;
    try std.testing.expectEqualStrings(
        "https://example.com/.well-known/openid-configuration",
        oidc.openIdConnectUrl,
    );

    try std.testing.expectEqualStrings(
        "#/components/securitySchemes/apiKeyAuth",
        schemes.get("apiKeyAuthAlias").?.reference.ref,
    );
}

test "kitchen sink parses every oauth2 flow" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const flows = parsed.components.?.securitySchemes.?.get("oauth2Auth").?.security_scheme.oauth2.flows;

    const implicit = flows.implicit.?;
    try std.testing.expectEqualStrings("https://example.com/oauth/authorize", implicit.authorizationUrl);
    try std.testing.expectEqualStrings("https://example.com/oauth/refresh", implicit.refreshUrl.?);
    try std.testing.expectEqualStrings("Read items", implicit.scopes.get("read:items").?);

    const password = flows.password.?;
    try std.testing.expectEqualStrings("https://example.com/oauth/token", password.tokenUrl);
    try std.testing.expectEqualStrings("https://example.com/oauth/refresh", password.refreshUrl.?);

    const client_credentials = flows.clientCredentials.?;
    try std.testing.expectEqualStrings("https://example.com/oauth/token", client_credentials.tokenUrl);
    try std.testing.expectEqualStrings("Write items", client_credentials.scopes.get("write:items").?);

    const authorization_code = flows.authorizationCode.?;
    try std.testing.expectEqualStrings("https://example.com/oauth/authorize", authorization_code.authorizationUrl);
    try std.testing.expectEqualStrings("https://example.com/oauth/token", authorization_code.tokenUrl);
    try std.testing.expectEqual(@as(u32, 2), authorization_code.scopes.count());
}

test "kitchen sink parses schema keywords" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var parsed = try loadKitchenSink(allocator);
    defer parsed.deinit(allocator);

    const schemas = parsed.components.?.schemas.?;
    const item = schemas.get("Item").?.schema;
    try std.testing.expectEqualStrings("Item", item.title.?);
    try std.testing.expectEqual(@as(usize, 1), item.required.?.len);
    try std.testing.expectEqualStrings("item", item.xml.?.name.?);

    const properties = item.properties.?;
    try std.testing.expectEqual(true, properties.get("id").?.schema.readOnly.?);
    try std.testing.expectEqual(@as(usize, 2), properties.get("name").?.schema.type_array.?.len);
    try std.testing.expectEqual(@as(i64, 10), properties.get("tags").?.schema.maxItems.?);
    try std.testing.expectEqual(true, properties.get("tags").?.schema.uniqueItems.?);
    try std.testing.expectEqual(@as(f64, 100), properties.get("count").?.schema.maximum.?);
    try std.testing.expectEqual(@as(i64, 10), properties.get("code").?.schema.maxLength.?);
    try std.testing.expectEqual(@as(i64, 5), properties.get("extra").?.schema.maxProperties.?);
    try std.testing.expectEqual(@as(usize, 2), properties.get("status").?.schema.enum_values.?.len);
    try std.testing.expectEqual(true, properties.get("secret").?.schema.writeOnly.?);

    const legacy = properties.get("legacy").?.schema;
    try std.testing.expectEqual(true, legacy.nullable.?);
    try std.testing.expectEqualStrings("ex", legacy.xml.?.prefix.?);
    try std.testing.expectEqual(true, legacy.xml.?.attribute.?);
    try std.testing.expectEqualStrings("https://example.com/docs/legacy", legacy.externalDocs.?.url);

    const named = schemas.get("Named").?.schema;
    try std.testing.expectEqual(@as(usize, 2), named.oneOf.?.len);
    try std.testing.expectEqualStrings("kind", named.discriminator.?.propertyName);
    try std.testing.expect(named.discriminator.?.mapping.?.get("item") != null);

    const combo = schemas.get("Combo").?.schema;
    try std.testing.expectEqual(@as(usize, 1), combo.allOf.?.len);
    try std.testing.expectEqual(@as(usize, 1), combo.anyOf.?.len);
    try std.testing.expect(combo.not != null);

    try std.testing.expectEqual(true, schemas.get("OpenMap").?.schema.additionalProperties.?.boolean);
    try std.testing.expectEqualStrings("#/components/schemas/Item", schemas.get("ItemAlias").?.reference.ref);
}
