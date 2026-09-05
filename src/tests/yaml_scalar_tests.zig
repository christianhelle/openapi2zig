const std = @import("std");
const test_utils = @import("test_utils.zig");
const yaml_loader = @import("../yaml_loader.zig");

// The YAML front end normalizes forms that zig-yaml does not handle directly:
// double-quoted continuations, quoted-scalar escapes, empty and boolean
// scalars, and the numeric spellings the schema keywords accept.

fn expectContains(json: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, json, needle) != null);
}

test "double quoted values continue across lines" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: "first part \
        \\    second part \
        \\    third part"
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "first part second part third part");
}

test "double quoted escape sequences are decoded" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: "tab\there and a \"quote\" plus a back\\slash"
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "tab\\there and a");
    try expectContains(json, "\\\"quote\\\"");
    try expectContains(json, "back\\\\slash");
}

test "single quoted values decode doubled quotes" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: 'it''s a title'
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "it's a title");
}

test "empty and boolean scalars become JSON null and booleans" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Flags
        \\  version: 1.0.0
        \\paths:
        \\  /pets:
        \\    get:
        \\      operationId: listPets
        \\      deprecated: true
        \\      description: null
        \\      responses:
        \\        '200':
        \\          description: OK
        \\components:
        \\  schemas:
        \\    Pet:
        \\      type: object
        \\      properties:
        \\        active:
        \\          type: boolean
        \\          default: false
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "\"deprecated\":true");
    try expectContains(json, "\"description\":null");
    try expectContains(json, "\"default\":false");
}

test "numeric schema keywords keep their float and integer spellings" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Numbers
        \\  version: 1.0.0
        \\components:
        \\  schemas:
        \\    Measurement:
        \\      type: object
        \\      properties:
        \\        ratio:
        \\          type: number
        \\          multipleOf: 1.0e3
        \\          minimum: -1.5E-3
        \\          maximum: 10
        \\        label:
        \\          type: string
        \\          maxLength: 64
        \\          minLength: 0
        \\        bag:
        \\          type: object
        \\          maxProperties: 8
        \\          minProperties: 1
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "\"multipleOf\":1.0e3");
    try expectContains(json, "\"minimum\":-1.5E-3");
    try expectContains(json, "\"maximum\":10.0");
    try expectContains(json, "\"maxLength\":64");
    try expectContains(json, "\"minLength\":0");
    try expectContains(json, "\"maxProperties\":8");
    try expectContains(json, "\"minProperties\":1");
}

test "literal block scalars keep their blank lines" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Blocks
        \\  version: 1.0.0
        \\  description: |
        \\    first line
        \\
        \\    third line
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "first line\\n\\nthird line");
}

test "an empty document is rejected" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    try std.testing.expectError(
        yaml_loader.YamlToJsonError.EmptyYamlDocument,
        yaml_loader.yamlToJson(allocator, ""),
    );
}

test "multiple documents in one file are rejected" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\---
        \\openapi: 3.0.3
        \\---
        \\openapi: 3.0.2
    ;

    try std.testing.expectError(
        yaml_loader.YamlToJsonError.MultipleYamlDocumentsUnsupported,
        yaml_loader.yamlToJson(allocator, yaml_content),
    );
}

test "a quoted scalar on its own line is left alone" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title:
        \\    "a wrapped title"
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "a wrapped title");
}

test "block scalars escape tabs and quotes" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    // Written with escapes rather than a multiline literal so the tab survives.
    const yaml_content = "openapi: 3.0.3\ninfo:\n  title: Blocks\n  version: 1.0.0\n  description: |\n    a \"quoted\" word\tand a tab\n";

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "a \\\"quoted\\\" word\\tand a tab");
}
