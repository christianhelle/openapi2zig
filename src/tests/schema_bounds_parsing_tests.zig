const std = @import("std");
const models = @import("../models.zig");
const test_utils = @import("test_utils.zig");

fn parseJsonValue(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
}

test "v3.0 schema parses integer multipleOf as float" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf != null);
    try std.testing.expectEqual(@as(f64, 5.0), schema.multipleOf.?);
}

test "v3.0 schema parses integer maximum as float" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"maximum\": 100}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.maximum != null);
    try std.testing.expectEqual(@as(f64, 100.0), schema.maximum.?);
}

test "v3.0 schema parses integer minimum as float" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"minimum\": 1}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.minimum != null);
    try std.testing.expectEqual(@as(f64, 1.0), schema.minimum.?);
}

test "v3.0 schema parses float multipleOf" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 2.5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf != null);
    try std.testing.expectEqual(@as(f64, 2.5), schema.multipleOf.?);
}

test "v3.0 schema parses float maximum" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"maximum\": 99.9}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.maximum != null);
    try std.testing.expectEqual(@as(f64, 99.9), schema.maximum.?);
}

test "v3.0 schema parses float minimum" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"minimum\": 0.5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.minimum != null);
    try std.testing.expectEqual(@as(f64, 0.5), schema.minimum.?);
}

test "v3.0 schema missing numeric bounds are null" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"type\": \"string\"}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf == null);
    try std.testing.expect(schema.maximum == null);
    try std.testing.expect(schema.minimum == null);
}

test "v3.0 schema invalid string multipleOf is null" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": \"not-a-number\"}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf == null);
}

test "v3.0 schema retains exclusiveMaximum/exclusiveMinimum as bool" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"exclusiveMaximum\": true, \"exclusiveMinimum\": false}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.exclusiveMaximum != null);
    try std.testing.expect(schema.exclusiveMaximum.?);
    try std.testing.expect(schema.exclusiveMinimum != null);
    try std.testing.expect(!schema.exclusiveMinimum.?);
}

test "v3.0 schema parses all numeric bounds together" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 10, \"maximum\": 200, \"minimum\": 5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expectEqual(@as(f64, 10.0), schema.multipleOf.?);
    try std.testing.expectEqual(@as(f64, 200.0), schema.maximum.?);
    try std.testing.expectEqual(@as(f64, 5.0), schema.minimum.?);
}

test "v3.2 schema parses integer multipleOf as float" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf != null);
    try std.testing.expectEqual(@as(f64, 5.0), schema.multipleOf.?);
}

test "v3.2 schema parses integer maximum as float" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"maximum\": 100}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.maximum != null);
    try std.testing.expectEqual(@as(f64, 100.0), schema.maximum.?);
}

test "v3.2 schema parses integer minimum as float" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"minimum\": 1}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.minimum != null);
    try std.testing.expectEqual(@as(f64, 1.0), schema.minimum.?);
}

test "v3.2 schema parses float multipleOf" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 2.5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf != null);
    try std.testing.expectEqual(@as(f64, 2.5), schema.multipleOf.?);
}

test "v3.2 schema parses float maximum" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"maximum\": 99.9}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.maximum != null);
    try std.testing.expectEqual(@as(f64, 99.9), schema.maximum.?);
}

test "v3.2 schema parses float minimum" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"minimum\": 0.5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.minimum != null);
    try std.testing.expectEqual(@as(f64, 0.5), schema.minimum.?);
}

test "v3.2 schema missing numeric bounds are null" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"type\": \"string\"}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf == null);
    try std.testing.expect(schema.maximum == null);
    try std.testing.expect(schema.minimum == null);
}

test "v3.2 schema invalid string multipleOf is null" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": \"not-a-number\"}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf == null);
}

test "v3.2 schema retains exclusiveMaximum/exclusiveMinimum as bool" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"exclusiveMaximum\": true, \"exclusiveMinimum\": false}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.exclusiveMaximum != null);
    try std.testing.expect(schema.exclusiveMaximum.?);
    try std.testing.expect(schema.exclusiveMinimum != null);
    try std.testing.expect(!schema.exclusiveMinimum.?);
}

test "v3.2 schema parses all numeric bounds together" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 10, \"maximum\": 200, \"minimum\": 5}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expectEqual(@as(f64, 10.0), schema.multipleOf.?);
    try std.testing.expectEqual(@as(f64, 200.0), schema.maximum.?);
    try std.testing.expectEqual(@as(f64, 5.0), schema.minimum.?);
}

test "v3.2 schema parses negative numeric bounds" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": -2, \"maximum\": -1, \"minimum\": -10}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expectEqual(@as(f64, -2.0), schema.multipleOf.?);
    try std.testing.expectEqual(@as(f64, -1.0), schema.maximum.?);
    try std.testing.expectEqual(@as(f64, -10.0), schema.minimum.?);
}

test "v3.0 schema parses overflowing integer multipleOf via number_string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 999999999999999999999}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf != null);
}

test "v3.0 schema parses overflowing integer maximum via number_string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"maximum\": 999999999999999999999}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.maximum != null);
}

test "v3.0 schema parses overflowing integer minimum via number_string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"minimum\": 999999999999999999999}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.minimum != null);
}

test "v3.2 schema parses overflowing integer multipleOf via number_string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": 999999999999999999999}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.multipleOf != null);
}

test "v3.2 schema parses overflowing integer maximum via number_string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"maximum\": 999999999999999999999}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.maximum != null);
}

test "v3.2 schema parses overflowing integer minimum via number_string" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"minimum\": 999999999999999999999}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v32.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expect(schema.minimum != null);
}

test "v3.0 schema parses negative numeric bounds" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const source = "{\"multipleOf\": -2, \"maximum\": -1, \"minimum\": -10}";
    var parsed = try parseJsonValue(allocator, source);
    defer parsed.deinit();
    var schema = try models.v3.Schema.parseFromJson(allocator, parsed.value);
    defer schema.deinit(allocator);
    try std.testing.expectEqual(@as(f64, -2.0), schema.multipleOf.?);
    try std.testing.expectEqual(@as(f64, -1.0), schema.maximum.?);
    try std.testing.expectEqual(@as(f64, -10.0), schema.minimum.?);
}
