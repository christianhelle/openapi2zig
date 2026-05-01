const std = @import("std");
const detector = @import("../detector.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");
const yaml_loader = @import("../yaml_loader.zig");

test "convert OpenAPI YAML to JSON and detect version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: YAML Petstore
        \\  version: 1.0.0
        \\paths:
        \\  /pets:
        \\    get:
        \\      operationId: listPets
        \\      responses:
        \\        '200':
        \\          description: OK
        \\components:
        \\  schemas:
        \\    Pet:
        \\      type: object
        \\      required:
        \\        - name
        \\      properties:
        \\        name:
        \\          type: string
        \\          maxLength: 64
        \\        age:
        \\          type: integer
        \\          minimum: 0
    ;

    const json_content = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);

    try std.testing.expectEqual(detector.OpenApiVersion.v3_0, try detector.getOpenApiVersion(allocator, json_content));

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, json_content);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("3.0.3", parsed.openapi);
    try std.testing.expectEqualStrings("YAML Petstore", parsed.info.title);
}

test "normalize OpenAPI YAML parser edge cases" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Edge Case API
        \\  description: |-
        \\    First line
        \\    Second line
        \\  version: 1.0.0
        \\paths:
        \\  /pets/{petId}:
        \\    get:
        \\      operationId: getPet
        \\      description: ""
        \\      responses:
        \\        '200':
        \\          description: OK
    ;

    const json_content = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, json_content);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("First line\nSecond line", parsed.info.description.?);
    try std.testing.expect(parsed.paths.path_items.contains("/pets/{petId}"));
    try std.testing.expectEqualStrings("", parsed.paths.path_items.get("/pets/{petId}").?.get.?.description.?);
}

test "convert Swagger YAML with quoted response keys" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\swagger: '2.0'
        \\info:
        \\  title: YAML Swagger
        \\  version: 1.0.0
        \\paths:
        \\  /pets:
        \\    get:
        \\      operationId: listPets
        \\      responses:
        \\        '200':
        \\          description: OK
    ;

    const json_content = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);

    try std.testing.expectEqual(detector.OpenApiVersion.v2_0, try detector.getOpenApiVersion(allocator, json_content));

    var parsed = try models.SwaggerDocument.parseFromJson(allocator, json_content);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("2.0", parsed.swagger);
    try std.testing.expectEqualStrings("YAML Swagger", parsed.info.title);
}

test "convert YAML specification to unified document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Unified YAML API
        \\  version: 1.0.0
        \\paths:
        \\  /pets:
        \\    get:
        \\      operationId: listPets
        \\      responses:
        \\        '200':
        \\          description: OK
    ;

    const json_content = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, json_content);
    defer parsed.deinit(allocator);

    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    try std.testing.expectEqualStrings("3.0.3", unified.version);
    try std.testing.expectEqualStrings("Unified YAML API", unified.info.title);
    try std.testing.expect(unified.paths.count() == 1);
}

test "preserve quoted YAML scalars as JSON strings" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: "false"
        \\  version: "null"
        \\paths:
        \\  /pets:
        \\    get:
        \\      operationId: listPets
        \\      responses:
        \\        '200':
        \\          description: OK
        \\components:
        \\  schemas:
        \\    Sample:
        \\      type: object
        \\      minimum: "10"
        \\      maxLength: "8"
        \\      properties:
        \\        flag:
        \\          type: string
        \\          default: "false"
    ;

    const json_content = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const info = root.get("info").?.object;
    const schemas = root.get("components").?.object.get("schemas").?.object;
    const sample = schemas.get("Sample").?.object;
    const properties = sample.get("properties").?.object;
    const flag = properties.get("flag").?.object;

    try std.testing.expectEqualStrings("false", info.get("title").?.string);
    try std.testing.expectEqualStrings("null", info.get("version").?.string);
    try std.testing.expectEqualStrings("10", sample.get("minimum").?.string);
    try std.testing.expectEqualStrings("8", sample.get("maxLength").?.string);
    try std.testing.expectEqualStrings("false", flag.get("default").?.string);
}

test "preserve folded YAML paragraph breaks and backslashes" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: YAML Petstore
        \\  description: >
        \\    First paragraph
        \\
        \\    C:\temp
        \\  version: 1.0.0
        \\paths:
        \\  /pets:
        \\    get:
        \\      operationId: listPets
        \\      responses:
        \\        '200':
        \\          description: OK
    ;

    const json_content = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, json_content);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("First paragraph\n\nC:\\temp", parsed.info.description.?);
}
