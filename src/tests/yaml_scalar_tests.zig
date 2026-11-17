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

test "double quoted values accept the full YAML escape set" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: "line one.\r\nline two.\tTabbed \/ slash é \x41 nul\0end"
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "line one.\\r\\nline two.\\tTabbed / slash \xc3\xa9 A nul\\u0000end");
}

test "an apostrophe inside a plain scalar does not open a quoted string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: A deleted item can't be restored. Also it's owner.
        \\  version: 1.0.0
        \\paths:
        \\  /a:
        \\    get:
        \\      responses:
        \\        '204':
        \\          description: Success
        \\        4XX:
        \\          $ref: '#/components/responses/error'
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "can't be restored. Also it's owner.");
    try expectContains(json, "\"4XX\"");
}

test "empty flow maps keep their parent map intact" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: t
        \\  version: 1.0.0
        \\x-example:
        \\  properties:
        \\    a: { }
        \\    b: { }
        \\    c: { }
        \\    d: { }
        \\    e: { }
        \\    f: {}
        \\    g: { }
        \\  required: true
        \\x-after: 1
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "\"properties\":{\"a\":{},\"b\":{},\"c\":{},\"d\":{},\"e\":{},\"f\":{},\"g\":{}}");
    try expectContains(json, "\"required\":true");
    try expectContains(json, "\"x-after\":\"1\"");
}

test "emphasis markers inside plain scalars are not aliases" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Retrieve the sets which are *excluded* in a policy & more!
        \\  description: It has no fixed value - you might see Note: this
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "sets which are *excluded* in a policy & more!");
    try expectContains(json, "no fixed value - you might");
}

test "flow mapping leaves are typed like block values" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: t
        \\  version: 1.0.0
        \\x-schema: {nullable: true, maxLength: 5, default: null, type: string}
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "\"nullable\":true");
    try expectContains(json, "\"default\":null");
    try expectContains(json, "\"type\":\"string\"");
}

test "unbalanced brackets inside plain scalars do not leak into later lines" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Use the filter {a and [b to narrow results
        \\  version: 1.0.0
        \\x-list:
        \\  - a trailing ] bracket } and brace
        \\  - second
        \\x-example:
        \\  properties:
        \\    rate: { }
        \\    basis: { }
        \\  required: true
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "Use the filter {a and [b to narrow results");
    try expectContains(json, "a trailing ] bracket } and brace");
    try expectContains(json, "\"required\":true");
}

test "quoted words inside a plain scalar stay part of the text" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: Header must be set to 'eventual'. Say "hi" to it's owner.
        \\  version: 1.0.0
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "set to 'eventual'. Say \\\"hi\\\" to it's owner.");
}

test "quoted keys may start with hash or contain syntax characters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const yaml_content =
        \\openapi: 3.0.3
        \\info:
        \\  title: t
        \\  version: 1.0.0
        \\x-mapping:
        \\  '#microsoft.graph.thing': '#/components/schemas/thing'
        \\  'two words': a
        \\  'a: b': c
        \\  'x, y [z]': d
        \\x-next:
        \\  k: v
        \\x-list:
        \\  - '@odata.type': microsoft.graph.thing
        \\    other: 1
    ;

    const json = try yaml_loader.yamlToJson(allocator, yaml_content);
    defer allocator.free(json);

    try expectContains(json, "\"x-list\":[{\"@odata.type\":\"microsoft.graph.thing\"");
    try expectContains(json, "\"#microsoft.graph.thing\":\"#/components/schemas/thing\"");
    try expectContains(json, "\"two words\":\"a\"");
    try expectContains(json, "\"a: b\":\"c\"");
    try expectContains(json, "\"x, y [z]\":\"d\"");
    try expectContains(json, "\"x-next\":{\"k\":\"v\"}");
}
