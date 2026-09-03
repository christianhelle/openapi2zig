//! Covers the `$ref` branches of the OpenAPI converters. A referenced
//! parameter, request body or response carries no inline definition, so the
//! converters record the reference string itself in `Parameter.name` /
//! `Response.description`. Those fields are borrowed from the source document
//! and must never be duplicated: `deinit` does not free them, so a copy would
//! leak. The leak-checked allocator here is what guards that.

const std = @import("std");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("../generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;
const UnifiedDocument = @import("../models/common/document.zig").UnifiedDocument;

const parameter_ref = "#/components/parameters/Limit";
const request_body_ref = "#/components/requestBodies/Pet";
const response_ref = "#/components/responses/Ok";

fn specWithReferences(comptime version: []const u8) []const u8 {
    return
    \\{
    \\  "openapi": "
    ++ version ++
        \\",
        \\  "info": { "title": "refs", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "operationId": "listPets",
        \\        "parameters": [{ "$ref": "#/components/parameters/Limit" }],
        \\        "responses": { "200": { "$ref": "#/components/responses/Ok" } }
        \\      },
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": { "$ref": "#/components/requestBodies/Pet" },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
}

/// Asserts the three reference strings survived conversion unchanged.
fn expectReferencesPreserved(unified: UnifiedDocument) !void {
    const path = unified.paths.get("/pets") orelse return error.MissingPath;

    const get = path.get orelse return error.MissingGetOperation;
    const get_params = get.parameters orelse return error.MissingParameters;
    try std.testing.expectEqual(@as(usize, 1), get_params.len);
    try std.testing.expectEqualStrings(parameter_ref, get_params[0].name);
    try std.testing.expectEqual(.query, get_params[0].location);

    const response = get.responses.get("200") orelse return error.MissingResponse;
    try std.testing.expectEqualStrings(response_ref, response.description);

    const post = path.post orelse return error.MissingPostOperation;
    const post_params = post.parameters orelse return error.MissingParameters;
    try std.testing.expectEqual(@as(usize, 1), post_params.len);
    try std.testing.expectEqualStrings(request_body_ref, post_params[0].name);
    try std.testing.expectEqual(.body, post_params[0].location);
}

fn testReferencesPreserved(
    comptime DocType: type,
    comptime Converter: type,
    json: []const u8,
) !void {
    var gpa = test_utils.createTestAllocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var parsed = try DocType.parseFromJson(allocator, json);
    defer parsed.deinit(allocator);

    var converter = Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    try expectReferencesPreserved(unified);
}

test "OpenAPI v3.0 converter keeps referenced parameters, bodies and responses" {
    try testReferencesPreserved(models.OpenApiDocument, OpenApiConverter, specWithReferences("3.0.0"));
}

test "OpenAPI v3.1 converter keeps referenced parameters, bodies and responses" {
    try testReferencesPreserved(models.OpenApi31Document, OpenApi31Converter, specWithReferences("3.1.0"));
}

test "OpenAPI v3.2 converter keeps referenced parameters, bodies and responses" {
    try testReferencesPreserved(models.OpenApi32Document, OpenApi32Converter, specWithReferences("3.2.0"));
}
