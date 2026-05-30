const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const document = @import("../models/common/document.zig");
const Parameter = document.Parameter;
const ParameterLocation = document.ParameterLocation;
const UnifiedDocument = document.UnifiedDocument;
const Operation = document.Operation;
const models = @import("../models.zig");
const SwaggerConverter = @import("../generators/converters/swagger_converter.zig").SwaggerConverter;
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("../generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("../generators/converters/openapi32_converter.zig").OpenApi32Converter;

fn loadOpenApiDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.OpenApiDocument {
    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, file_path, allocator, .unlimited);
    defer allocator.free(file_contents);
    return try models.OpenApiDocument.parseFromJson(allocator, file_contents);
}

fn loadSwaggerDocument(allocator: std.mem.Allocator, file_path: []const u8) !models.SwaggerDocument {
    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, file_path, allocator, .unlimited);
    defer allocator.free(file_contents);
    return try models.SwaggerDocument.parseFromJson(allocator, file_contents);
}

fn parseAndConvertV3(allocator: std.mem.Allocator, json: []const u8) !UnifiedDocument {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, json);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    return converter.convert(parsed);
}

fn findOperation(unified: *const UnifiedDocument, path: []const u8, method: enum { get, post, put }) ?Operation {
    const path_item = unified.paths.get(path) orelse return null;
    return switch (method) {
        .get => path_item.get,
        .post => path_item.post,
        .put => path_item.put,
    };
}

fn findBodyParameter(op: Operation) ?Parameter {
    const params = op.parameters orelse return null;
    for (params) |p| {
        if (p.location == .body) return p;
    }
    return null;
}

test "Parameter.content_type owns and frees its allocation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var param = Parameter{
        .name = "requestBody",
        .location = .body,
        .required = true,
        .content_type = try allocator.dupe(u8, "application/octet-stream"),
    };
    defer param.deinit(allocator);

    try testing.expect(param.content_type != null);
    try testing.expectEqualStrings("application/octet-stream", param.content_type.?);
}

test "Parameter.content_type defaults to null for non-body parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var param = Parameter{
        .name = "petId",
        .location = .path,
        .required = true,
    };
    defer param.deinit(allocator);

    try testing.expect(param.content_type == null);
}

test "v3.0 converter :: octet-stream uploadFile body captures content_type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadOpenApiDocument(allocator, "openapi/v3.0/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/pet/{petId}/uploadImage", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expect(body.content_type != null);
    try testing.expectEqualStrings("application/octet-stream", body.content_type.?);
}

test "v3.0 converter :: addPet body prefers application/json content_type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadOpenApiDocument(allocator, "openapi/v3.0/petstore.json");
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/pet", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expect(body.content_type != null);
    try testing.expectEqualStrings("application/json", body.content_type.?);
}

test "v3.0 converter :: JSON wins when both JSON and XML present" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{
        \\  "openapi": "3.0.3",
        \\  "info": { "title": "T", "version": "1" },
        \\  "paths": {
        \\    "/x": {
        \\      "post": {
        \\        "operationId": "doX",
        \\        "requestBody": {
        \\          "content": {
        \\            "application/xml": { "schema": { "type": "string" } },
        \\            "application/json": { "schema": { "type": "object" } }
        \\          }
        \\        },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var unified = try parseAndConvertV3(allocator, spec);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/x", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expectEqualStrings("application/json", body.content_type.?);
}

test "v3.0 converter :: XML-only body falls back to application/xml" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{
        \\  "openapi": "3.0.3",
        \\  "info": { "title": "T", "version": "1" },
        \\  "paths": {
        \\    "/x": {
        \\      "post": {
        \\        "operationId": "doX",
        \\        "requestBody": {
        \\          "content": {
        \\            "application/xml": { "schema": { "type": "string" } }
        \\          }
        \\        },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var unified = try parseAndConvertV3(allocator, spec);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/x", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expectEqualStrings("application/xml", body.content_type.?);
}

test "v3.0 converter :: vendor +json suffix selected over non-json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{
        \\  "openapi": "3.0.3",
        \\  "info": { "title": "T", "version": "1" },
        \\  "paths": {
        \\    "/x": {
        \\      "post": {
        \\        "operationId": "doX",
        \\        "requestBody": {
        \\          "content": {
        \\            "application/xml": { "schema": { "type": "string" } },
        \\            "application/vnd.acme+json": { "schema": { "type": "object" } }
        \\          }
        \\        },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var unified = try parseAndConvertV3(allocator, spec);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/x", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expectEqualStrings("application/vnd.acme+json", body.content_type.?);
}

test "v3.1 converter :: octet-stream body captures content_type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{
        \\  "openapi": "3.1.0",
        \\  "info": { "title": "T", "version": "1" },
        \\  "paths": {
        \\    "/upload": {
        \\      "post": {
        \\        "operationId": "doUpload",
        \\        "requestBody": {
        \\          "content": {
        \\            "application/octet-stream": { "schema": { "type": "string", "format": "binary" } }
        \\          }
        \\        },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var parsed = try models.OpenApi31Document.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/upload", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expectEqualStrings("application/octet-stream", body.content_type.?);
}

test "v3.2 converter :: JSON wins over XML" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{
        \\  "openapi": "3.2.0",
        \\  "info": { "title": "T", "version": "1" },
        \\  "paths": {
        \\    "/x": {
        \\      "post": {
        \\        "operationId": "doX",
        \\        "requestBody": {
        \\          "content": {
        \\            "application/xml": { "schema": { "type": "string" } },
        \\            "application/json": { "schema": { "type": "object" } }
        \\          }
        \\        },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var parsed = try models.OpenApi32Document.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApi32Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/x", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expectEqualStrings("application/json", body.content_type.?);
}

test "v2.0 converter :: operation-level consumes octet-stream wins over spec-level json" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadSwaggerDocument(allocator, "openapi/v2.0/binary-upload.json");
    defer parsed.deinit(allocator);
    var converter = SwaggerConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/upload", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expect(body.content_type != null);
    try testing.expectEqualStrings("application/octet-stream", body.content_type.?);
}

test "v2.0 converter :: spec-level consumes inherits when operation omits consumes" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var parsed = try loadSwaggerDocument(allocator, "openapi/v2.0/binary-upload.json");
    defer parsed.deinit(allocator);
    var converter = SwaggerConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/echo", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expect(body.content_type != null);
    try testing.expectEqualStrings("application/json", body.content_type.?);
}

test "v3.0 converter :: JSON wins even when media type has parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const spec =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "T", "version": "1" },
        \\  "paths": {
        \\    "/x": {
        \\      "post": {
        \\        "operationId": "doX",
        \\        "requestBody": {
        \\          "content": {
        \\            "application/octet-stream": { "schema": { "type": "string" } },
        \\            "application/json; charset=utf-8": { "schema": { "type": "object" } }
        \\          }
        \\        },
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var unified = try parseAndConvertV3(allocator, spec);
    defer unified.deinit(allocator);

    const op = findOperation(&unified, "/x", .post) orelse return error.OperationNotFound;
    const body = findBodyParameter(op) orelse return error.BodyNotFound;
    try testing.expect(body.content_type != null);
    try testing.expectEqualStrings("application/json; charset=utf-8", body.content_type.?);
}

test "generated v3.0 :: uploadFile takes []const u8 requestBody and emits octet-stream Content-Type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "generated/generated_v3.zig", allocator, .unlimited);
    defer allocator.free(file_contents);

    try testing.expect(std.mem.indexOf(u8, file_contents, "pub fn uploadFile(client: *Client, petId: i64, additionalMetadata: ?[]const u8, requestBody: []const u8)") != null);
    try testing.expect(std.mem.indexOf(u8, file_contents, "pub fn uploadFileRaw(client: *Client, petId: i64, additionalMetadata: ?[]const u8, requestBody: []const u8)") != null);
    // The uploadFileRaw block must NOT JSON-stringify the body.
    const upload_idx = std.mem.indexOf(u8, file_contents, "pub fn uploadFileRaw").?;
    const upload_end = std.mem.indexOfPos(u8, file_contents, upload_idx, "pub fn uploadFileResult").?;
    const upload_block = file_contents[upload_idx..upload_end];
    try testing.expect(std.mem.indexOf(u8, upload_block, "std.json.Stringify.value(requestBody") == null);
    try testing.expect(std.mem.indexOf(u8, upload_block, "const payload: ?[]const u8 = requestBody;") != null);
    try testing.expect(std.mem.indexOf(u8, upload_block, "\"application/octet-stream\", \"application/json\"") != null);
}

test "generated v3.0 :: addPet still uses JSON encoding for application/json body" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "generated/generated_v3.zig", allocator, .unlimited);
    defer allocator.free(file_contents);

    const idx = std.mem.indexOf(u8, file_contents, "pub fn addPetRaw").?;
    const end = std.mem.indexOfPos(u8, file_contents, idx, "pub fn addPetResult").?;
    const block = file_contents[idx..end];
    try testing.expect(std.mem.indexOf(u8, block, "std.json.Stringify.value(requestBody") != null);
    try testing.expect(std.mem.indexOf(u8, block, "requestBody: Pet") != null);
}
