const std = @import("std");
const common = @import("../models/common/document.zig");
const models = @import("../models.zig");
const OpenApi31Converter = @import("../generators/converters/openapi31_converter.zig").OpenApi31Converter;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;

fn stringSchema() common.Schema {
    return .{ .type = .string };
}

test "model generator treats properties without type as struct" {
    const allocator = std.testing.allocator;
    var properties = std.StringHashMap(common.Schema).init(allocator);
    defer {
        var iterator = properties.iterator();
        while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
        properties.deinit();
    }
    try properties.put(try allocator.dupe(u8, "foo"), stringSchema());

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    defer {
        var iterator = schemas.iterator();
        while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
        schemas.deinit();
    }
    try schemas.put(try allocator.dupe(u8, "Foo"), .{ .properties = properties });

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    defer paths.deinit();
    const document: common.UnifiedDocument = .{
        .version = "3.1.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };

    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const Foo = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "foo: ?[]const u8 = null") != null);
}

test "OpenAPI 3.1 allOf object refs merge into one schema" {
    const allocator = std.testing.allocator;
    const source =
        \\{
        \\  "openapi": "3.1.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {},
        \\  "components": {
        \\    "schemas": {
        \\      "Base": {
        \\        "type": "object",
        \\        "required": ["id"],
        \\        "properties": { "id": { "type": "string" } }
        \\      },
        \\      "Thing": {
        \\        "allOf": [
        \\          { "$ref": "#/components/schemas/Base" },
        \\          {
        \\            "type": "object",
        \\            "required": ["name"],
        \\            "properties": { "name": { "type": "string" } }
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var parsed = try models.OpenApi31Document.parseFromJson(allocator, source);
    defer parsed.deinit(allocator);

    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const schemas = unified.schemas.?;
    const thing = schemas.get("Thing").?;
    try std.testing.expect(thing.properties != null);
    try std.testing.expect(thing.properties.?.contains("id"));
    try std.testing.expect(thing.properties.?.contains("name"));
    try std.testing.expect(thing.required != null);
    try std.testing.expectEqual(@as(usize, 2), thing.required.?.len);
}

test "OpenAPI 3.1 discriminator oneOf emits tagged union with raw fallback" {
    const allocator = std.testing.allocator;
    const source =
        \\{
        \\  "openapi": "3.1.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {},
        \\  "components": {
        \\    "schemas": {
        \\      "Cat": {
        \\        "type": "object",
        \\        "required": ["type", "meows"],
        \\        "properties": {
        \\          "type": { "type": "string", "enum": ["cat"] },
        \\          "meows": { "type": "boolean" }
        \\        }
        \\      },
        \\      "Dog": {
        \\        "type": "object",
        \\        "required": ["type", "barks"],
        \\        "properties": {
        \\          "type": { "type": "string", "enum": ["dog"] },
        \\          "barks": { "type": "boolean" }
        \\        }
        \\      },
        \\      "Pet": {
        \\        "oneOf": [
        \\          { "$ref": "#/components/schemas/Cat" },
        \\          { "$ref": "#/components/schemas/Dog" }
        \\        ],
        \\        "discriminator": { "propertyName": "type" }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var parsed = try models.OpenApi31Document.parseFromJson(allocator, source);
    defer parsed.deinit(allocator);

    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const Pet = union(enum)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "cat: Cat") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "dog: Dog") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "raw: std.json.Value") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn jsonParseFromValue") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "source.object.get(\"type\")") != null);
}

test "extensible request structs emit extra_body merge hook" {
    const allocator = std.testing.allocator;
    var properties = std.StringHashMap(common.Schema).init(allocator);
    defer {
        var iterator = properties.iterator();
        while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
        properties.deinit();
    }
    try properties.put(try allocator.dupe(u8, "model"), stringSchema());

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    defer {
        var iterator = schemas.iterator();
        while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
        schemas.deinit();
    }
    try schemas.put(try allocator.dupe(u8, "CreateChatCompletionRequest"), .{
        .type = .object,
        .properties = properties,
        .required = try allocator.dupe([]const u8, &.{"model"}),
    });
    defer allocator.free(schemas.getPtr("CreateChatCompletionRequest").?.required.?);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    defer paths.deinit();
    const document: common.UnifiedDocument = .{
        .version = "3.1.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };

    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "extra_body: ?std.json.Value = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var iterator = extra.object.iterator()") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "try jw.objectField(entry.key_ptr.*)") != null);
}

test "model generator emits named types for structured array items" {
    const allocator = std.testing.allocator;
    const source =
        \\{
        \\  "openapi": "3.1.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {},
        \\  "components": {
        \\    "schemas": {
        \\      "Cat": {
        \\        "type": "object",
        \\        "required": ["type", "meows"],
        \\        "properties": {
        \\          "type": { "type": "string", "enum": ["cat"] },
        \\          "meows": { "type": "boolean" }
        \\        }
        \\      },
        \\      "Dog": {
        \\        "type": "object",
        \\        "required": ["type", "barks"],
        \\        "properties": {
        \\          "type": { "type": "string", "enum": ["dog"] },
        \\          "barks": { "type": "boolean" }
        \\        }
        \\      },
        \\      "Owner": {
        \\        "type": "object",
        \\        "required": ["pets", "rows"],
        \\        "properties": {
        \\          "pets": {
        \\            "type": "array",
        \\            "items": {
        \\              "oneOf": [
        \\                { "$ref": "#/components/schemas/Cat" },
        \\                { "$ref": "#/components/schemas/Dog" }
        \\              ],
        \\              "discriminator": { "propertyName": "type" }
        \\            }
        \\          },
        \\          "rows": {
        \\            "type": "array",
        \\            "items": {
        \\              "type": "object",
        \\              "required": ["name"],
        \\              "properties": { "name": { "type": "string" } }
        \\            }
        \\          }
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var parsed = try models.OpenApi31Document.parseFromJson(allocator, source);
    defer parsed.deinit(allocator);

    var converter = OpenApi31Converter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const OwnerPetsItem = union(enum)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "cat: Cat") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "dog: Dog") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pets: []const OwnerPetsItem") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const OwnerRowsItem = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "rows: []const OwnerRowsItem") != null);
}
