const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;

const spec_with_operation_id =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/repos/{owner}/{repo}/stacks/{stack_number}": {
    \\      "get": {
    \\        "operationId": "getStack",
    \\        "parameters": [
    \\          { "name": "owner", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "repo", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "stack_number", "in": "path", "required": true, "schema": { "type": "integer" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

// Operations without an operationId take a separate code path
// (generateFunctionBodyDirect), which builds its request URI independently.
const spec_without_operation_id =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/repos/{owner}/{repo}/stacks/{stack_number}": {
    \\      "get": {
    \\        "parameters": [
    \\          { "name": "owner", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "repo", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "stack_number", "in": "path", "required": true, "schema": { "type": "integer" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

fn generateClient(allocator: std.mem.Allocator, spec: []const u8) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    return generator.generate(unified);
}

test "path parameters substitute only their placeholder, not literal segments" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_operation_id);
    defer allocator.free(code);

    // The `repo` parameter name also occurs inside the literal `repos` segment.
    // Substituting the bare name rather than the `{repo}` placeholder rewrote
    // that segment too, producing "/ss/" in place of "/repos/".
    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/repos/{f}/{f}/stacks/{f}\"") != null);
}

test "path placeholders substitute correctly for operations without an operationId" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_without_operation_id);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/repos/{f}/{f}/stacks/{f}\"") != null);
}

// Path parameter values are interpolated into the request URI. Query values go
// through percentEncode; path values did not, so a value containing '/', '?' or
// '#' silently changed the request target. Every path parameter now goes through
// the pathComponent formatter regardless of its declared type.

test "path parameter values are percent-encoded" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_operation_id);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pathComponent(owner)") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pathComponent(repo)") != null);
    // Integers are routed through the same formatter, so there is no bare {d}.
    try testing.expect(std.mem.indexOf(u8, code, "pathComponent(stack_number)") != null);

    // The runtime helpers the format string depends on must be emitted.
    try testing.expect(std.mem.indexOf(u8, code, "fn isPathChar(") != null);
    try testing.expect(std.mem.indexOf(u8, code, "fn writePathValue(") != null);
    try testing.expect(std.mem.indexOf(u8, code, "fn pathComponent(") != null);
}

test "path parameter values are percent-encoded without an operationId" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_without_operation_id);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pathComponent(owner)") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pathComponent(stack_number)") != null);
}
