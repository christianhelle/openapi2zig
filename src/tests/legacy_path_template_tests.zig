const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const models = @import("../models.zig");
const V2ApiCodeGenerator = @import("../generators/v2.0/apigenerator.zig").ApiCodeGenerator;
const V3ApiCodeGenerator = @import("../generators/v3.0/apigenerator.zig").ApiCodeGenerator;

// `repo` also occurs inside the literal `repos` segment, so substituting the
// bare parameter name rewrites that segment too and corrupts the request path.
const swagger_v2_spec =
    \\{
    \\  "swagger": "2.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/repos/{owner}/{repo}/stacks": {
    \\      "get": {
    \\        "operationId": "getStack",
    \\        "parameters": [
    \\          { "name": "owner", "in": "path", "required": true, "type": "string" },
    \\          { "name": "repo", "in": "path", "required": true, "type": "string" }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

const openapi_v3_spec =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Paths", "version": "1.0.0" },
    \\  "paths": {
    \\    "/repos/{owner}/{repo}/stacks": {
    \\      "get": {
    \\        "operationId": "getStack",
    \\        "parameters": [
    \\          { "name": "owner", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "repo", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

test "v2.0 generator substitutes path placeholders, not literal segments" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try models.SwaggerDocument.parseFromJson(allocator, swagger_v2_spec);
    defer document.deinit(allocator);

    var generator = V2ApiCodeGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "/repos/{any}/{any}/stacks") != null);
    try testing.expect(std.mem.indexOf(u8, code, "/anys/") == null);
}

test "v3.0 generator substitutes path placeholders, not literal segments" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try models.OpenApiDocument.parseFromJson(allocator, openapi_v3_spec);
    defer document.deinit(allocator);

    var generator = V3ApiCodeGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "/repos/{any}/{any}/stacks") != null);
    try testing.expect(std.mem.indexOf(u8, code, "/anys/") == null);
}
