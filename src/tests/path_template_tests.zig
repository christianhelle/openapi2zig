const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const cli = @import("../cli.zig");
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
    return generateClientWithArgs(allocator, spec, .{ .input_path = "fixture.json" });
}

fn generateClientWithArgs(allocator: std.mem.Allocator, spec: []const u8, args: cli.CliArgs) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, args);
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
    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/repos/{s}/{s}/stacks/{d}\"") != null);
}

test "path placeholders substitute correctly for operations without an operationId" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_without_operation_id);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/repos/{s}/{s}/stacks/{d}\"") != null);
}

// Some descriptions, GitHub among them, list path parameters in a different
// order than their paths use them, with and without matching types.
const spec_with_parameters_out_of_path_order =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/users/{username}/projects/{project_number}/fields/{field_id}": {
    \\      "get": {
    \\        "operationId": "getField",
    \\        "parameters": [
    \\          { "name": "project_number", "in": "path", "required": true, "schema": { "type": "integer" } },
    \\          { "name": "field_id", "in": "path", "required": true, "schema": { "type": "integer" } },
    \\          { "name": "username", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    },
    \\    "/environments/{environment_name}/variables/{name}": {
    \\      "get": {
    \\        "operationId": "getVariable",
    \\        "parameters": [
    \\          { "name": "name", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "environment_name", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    },
    \\    "/mirrors/{id}/of/{id}": {
    \\      "get": {
    \\        "operationId": "getMirror",
    \\        "parameters": [
    \\          { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

const spec_with_parameters_out_of_path_order_no_operation_id =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/environments/{environment_name}/variables/{name}": {
    \\      "get": {
    \\        "parameters": [
    \\          { "name": "name", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "environment_name", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

const spec_with_parameter_missing_from_path =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/things/{id}": {
    \\      "get": {
    \\        "operationId": "getThing",
    \\        "parameters": [
    \\          { "name": "unused", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

test "a path parameter the template never uses still gets an argument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_parameter_missing_from_path);
    defer allocator.free(code);

    // The extra argument makes the generated code fail to compile, rather than
    // silently ignoring the value the caller passed.
    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/things/{s}\", .{ client.base_url, id, unused }") != null);
}

test "path arguments follow the path template when their types differ" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_parameters_out_of_path_order);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/users/{s}/projects/{d}/fields/{d}\", .{ client.base_url, username, project_number, field_id }") != null);
}

test "path arguments follow the path template when their types match" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_parameters_out_of_path_order);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/environments/{s}/variables/{s}\", .{ client.base_url, environment_name, name }") != null);
}

test "struct path arguments follow the path template" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClientWithArgs(allocator, spec_with_parameters_out_of_path_order, .{ .input_path = "fixture.json", .parameters_as_struct = true });
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/users/{s}/projects/{d}/fields/{d}\", .{ client.base_url, options.username, options.project_number, options.field_id }") != null);
}

test "struct path arguments follow the path template for operations without an operationId" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClientWithArgs(allocator, spec_with_parameters_out_of_path_order_no_operation_id, .{ .input_path = "fixture.json", .parameters_as_struct = true });
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/environments/{s}/variables/{s}\", .{ client.base_url, options.environment_name, options.name }") != null);
}

test "a repeated path placeholder gets one argument per occurrence" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_parameters_out_of_path_order);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/mirrors/{s}/of/{s}\", .{ client.base_url, id, id }") != null);
}

test "path arguments follow the path template for operations without an operationId" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_parameters_out_of_path_order_no_operation_id);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "\"{s}/environments/{s}/variables/{s}\", .{ client.base_url, environment_name, name }") != null);
}
