const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const common = @import("../models/common/document.zig");

const spec =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Refs", "version": "1.0.0" },
    \\  "paths": {
    \\    "/repos/{owner}/{repo}/stacks": {
    \\      "get": {
    \\        "operationId": "listStacks",
    \\        "parameters": [
    \\          { "$ref": "#/components/parameters/owner" },
    \\          { "$ref": "#/components/parameters/repo" }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  },
    \\  "components": {
    \\    "parameters": {
    \\      "owner": {
    \\        "name": "owner",
    \\        "in": "path",
    \\        "required": true,
    \\        "schema": { "type": "string" }
    \\      },
    \\      "repo": {
    \\        "name": "repo",
    \\        "in": "path",
    \\        "required": true,
    \\        "schema": { "type": "string" }
    \\      }
    \\    }
    \\  }
    \\}
;

test "component parameter references resolve to the referenced parameter" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const path_item = unified.paths.get("/repos/{owner}/{repo}/stacks").?;
    const params = path_item.get.?.parameters.?;
    try testing.expectEqual(@as(usize, 2), params.len);

    // An unresolved $ref used to surface as a query parameter literally named
    // "#/components/parameters/owner", which left the {owner} path placeholder
    // unfilled in the generated request.
    try testing.expectEqualStrings("owner", params[0].name);
    try testing.expectEqual(common.ParameterLocation.path, params[0].location);
    try testing.expect(params[0].required);

    try testing.expectEqualStrings("repo", params[1].name);
    try testing.expectEqual(common.ParameterLocation.path, params[1].location);
    try testing.expect(params[1].required);
}
