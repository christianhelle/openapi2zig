const std = @import("std");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");
const schema_v30 = @import("../models/v3.0/schema.zig");
const schema_v31 = @import("../models/v3.1/schema.zig");
const schema_v32 = @import("../models/v3.2/schema.zig");
const security_v20 = @import("../models/v2.0/security.zig");

// Parser fallbacks that a well-formed specification never reaches: numeric
// literals too large for i64, an `additionalProperties` that is neither an
// object nor a boolean, and Swagger 2.0 enums built from unrecognised strings.

fn parseSchemaJson(comptime Schema: type, allocator: std.mem.Allocator, source: []const u8) !Schema {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    defer parsed.deinit();
    return Schema.parseFromJson(allocator, parsed.value);
}

test "v3.1 schema bounds accept numbers too large for a JSON integer" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    // std.json hands these back as `number_string` rather than `integer`.
    const source =
        \\{"type": "string", "maxLength": 99999999999999999999, "minLength": 1}
    ;
    var schema = try parseSchemaJson(schema_v31.Schema, allocator, source);
    defer schema.deinit(allocator);

    // The value does not fit in an i64, so it is dropped rather than truncated.
    try std.testing.expect(schema.maxLength == null);
    try std.testing.expectEqual(@as(i64, 1), schema.minLength.?);
}

test "v3.1 schema enums keep numbers too large for a JSON integer" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const source =
        \\{"type": "integer", "enum": [1, 99999999999999999999]}
    ;
    var schema = try parseSchemaJson(schema_v31.Schema, allocator, source);
    defer schema.deinit(allocator);

    const values = schema.enum_values.?;
    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqualStrings("99999999999999999999", values[1].number_string);
}

test "additionalProperties must be an object or a boolean" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const source =
        \\{"type": "object", "additionalProperties": "yes please"}
    ;
    try std.testing.expectError(
        error.InvalidAdditionalPropertiesType,
        parseSchemaJson(schema_v30.Schema, allocator, source),
    );
    try std.testing.expectError(
        error.InvalidAdditionalPropertiesType,
        parseSchemaJson(schema_v31.Schema, allocator, source),
    );
    try std.testing.expectError(
        error.InvalidAdditionalPropertiesType,
        parseSchemaJson(schema_v32.Schema, allocator, source),
    );
}

test "Swagger 2.0 security enums reject unrecognised values" {
    try std.testing.expect(security_v20.SecuritySchemeType.fromString("magic") == null);
    try std.testing.expect(security_v20.ApiKeyLocation.fromString("body") == null);
    try std.testing.expect(security_v20.OAuth2Flow.fromString("device") == null);
}

test "a Swagger 2.0 security definition with an unknown type is rejected" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const source =
        \\{
        \\  "swagger": "2.0",
        \\  "info": {"title": "fixture", "version": "1.0.0"},
        \\  "paths": {},
        \\  "securityDefinitions": {"weird": {"type": "magic"}}
        \\}
    ;
    try std.testing.expectError(
        error.InvalidSecuritySchemeType,
        models.SwaggerDocument.parseFromJson(allocator, source),
    );
}
