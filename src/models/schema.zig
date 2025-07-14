const std = @import("std");
const json = std.json;
const Reference = @import("reference.zig").Reference;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const XML = struct {
    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    prefix: ?[]const u8 = null,
    attribute: ?bool = null,
    wrapped: ?bool = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!XML {
        const obj = value.object;
        return XML{
            .name = if (obj.get("name")) |val| try allocator.dupe(u8, val.string) else null,
            .namespace = if (obj.get("namespace")) |val| try allocator.dupe(u8, val.string) else null,
            .prefix = if (obj.get("prefix")) |val| try allocator.dupe(u8, val.string) else null,
            .attribute = if (obj.get("attribute")) |val| val.bool else null,
            .wrapped = if (obj.get("wrapped")) |val| val.bool else null,
        };
    }
};

pub const Discriminator = struct {
    propertyName: []const u8,
    mapping: ?std.StringHashMap([]const u8) = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Discriminator {
        const obj = value.object;
        var mapping_map = std.StringHashMap([]const u8).init(allocator);
        errdefer mapping_map.deinit();
        if (obj.get("mapping")) |map_val| {
            for (map_val.object.keys()) |key| {
                try mapping_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, map_val.object.get(key).?.string));
            }
        }
        return Discriminator{
            .propertyName = try allocator.dupe(u8, obj.get("propertyName").?.string),
            .mapping = if (mapping_map.count() > 0) mapping_map else null,
        };
    }
};

pub const AdditionalProperties = union(enum) {
    schema_or_reference: SchemaOrReference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!AdditionalProperties {
        return AdditionalProperties{ .schema_or_reference = try SchemaOrReference.parse(allocator, value) };
    }
};

pub const SchemaOrReference = union(enum) {
    schema: *Schema,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!SchemaOrReference {
        if (value.object.get("$ref") != null) {
            return SchemaOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            const schema = try allocator.create(Schema);
            errdefer allocator.destroy(schema);
            schema.* = try Schema.parse(allocator, value);
            return SchemaOrReference{ .schema = schema };
        }
    }
};

pub const Schema = struct {
    title: ?[]const u8 = null,
    multipleOf: ?f64 = null,
    maximum: ?f64 = null,
    exclusiveMaximum: ?bool = null,
    minimum: ?f64 = null,
    exclusiveMinimum: ?bool = null,
    maxLength: ?i64 = null,
    minLength: ?i64 = null,
    pattern: ?[]const u8 = null,
    maxItems: ?i64 = null,
    minItems: ?i64 = null,
    uniqueItems: ?bool = null,
    maxProperties: ?i64 = null,
    minProperties: ?i64 = null,
    required: ?[]const []const u8 = null,
    enum_values: ?[]const json.Value = null, // Can be any type
    type: ?[]const u8 = null, // "array", "boolean", "integer", "number", "object", "string"
    not: ?SchemaOrReference = null,
    allOf: ?[]const SchemaOrReference = null,
    oneOf: ?[]const SchemaOrReference = null,
    anyOf: ?[]const SchemaOrReference = null,
    items: ?SchemaOrReference = null,
    properties: ?std.StringHashMap(SchemaOrReference) = null,
    additionalProperties: ?AdditionalProperties = null,
    description: ?[]const u8 = null,
    format: ?[]const u8 = null,
    default: ?json.Value = null,
    nullable: ?bool = null,
    discriminator: ?Discriminator = null,
    readOnly: ?bool = null,
    writeOnly: ?bool = null,
    example: ?json.Value = null,
    externalDocs: ?ExternalDocumentation = null,
    deprecated: ?bool = null,
    xml: ?XML = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Schema {
        const obj = value.object;
        var required_list = std.ArrayList([]const u8).init(allocator);
        errdefer required_list.deinit();
        if (obj.get("required")) |req_val| {
            for (req_val.array.items) |item| {
                try required_list.append(try allocator.dupe(u8, item.string));
            }
        }
        var enum_list = std.ArrayList(json.Value).init(allocator);
        errdefer enum_list.deinit();
        if (obj.get("enum")) |enum_val| {
            for (enum_val.array.items) |item| {
                try enum_list.append(item);
            }
        }
        var all_of_list = std.ArrayList(SchemaOrReference).init(allocator);
        errdefer all_of_list.deinit();
        if (obj.get("allOf")) |all_of_val| {
            for (all_of_val.array.items) |item| {
                try all_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
        }
        var one_of_list = std.ArrayList(SchemaOrReference).init(allocator);
        errdefer one_of_list.deinit();
        if (obj.get("oneOf")) |one_of_val| {
            for (one_of_val.array.items) |item| {
                try one_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
        }
        var any_of_list = std.ArrayList(SchemaOrReference).init(allocator);
        errdefer any_of_list.deinit();
        if (obj.get("anyOf")) |any_of_val| {
            for (any_of_val.array.items) |item| {
                try any_of_list.append(try SchemaOrReference.parse(allocator, item));
            }
        }
        var properties_map = std.StringHashMap(SchemaOrReference).init(allocator);
        errdefer properties_map.deinit();
        if (obj.get("properties")) |props_val| {
            for (props_val.object.keys()) |key| {
                try properties_map.put(key, try SchemaOrReference.parse(allocator, props_val.object.get(key).?));
            }
        }

        return Schema{
            .title = if (obj.get("title")) |val| try allocator.dupe(u8, val.string) else null,
            .multipleOf = if (obj.get("multipleOf")) |val| val.float else null,
            .maximum = if (obj.get("maximum")) |val| val.float else null,
            .exclusiveMaximum = if (obj.get("exclusiveMaximum")) |val| val.bool else null,
            .minimum = if (obj.get("minimum")) |val| val.float else null,
            .exclusiveMinimum = if (obj.get("exclusiveMinimum")) |val| val.bool else null,
            .maxLength = if (obj.get("maxLength")) |val| val.integer else null,
            .minLength = if (obj.get("minLength")) |val| val.integer else null,
            .pattern = if (obj.get("pattern")) |val| try allocator.dupe(u8, val.string) else null,
            .maxItems = if (obj.get("maxItems")) |val| val.integer else null,
            .minItems = if (obj.get("minItems")) |val| val.integer else null,
            .uniqueItems = if (obj.get("uniqueItems")) |val| val.bool else null,
            .maxProperties = if (obj.get("maxProperties")) |val| val.integer else null,
            .minProperties = if (obj.get("minProperties")) |val| val.integer else null,
            .required = if (required_list.items.len > 0) try required_list.toOwnedSlice() else null,
            .enum_values = if (enum_list.items.len > 0) try enum_list.toOwnedSlice() else null,
            .type = if (obj.get("type")) |val| try allocator.dupe(u8, val.string) else null,
            .not = if (obj.get("not")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .allOf = if (all_of_list.items.len > 0) try all_of_list.toOwnedSlice() else null,
            .oneOf = if (one_of_list.items.len > 0) try one_of_list.toOwnedSlice() else null,
            .anyOf = if (any_of_list.items.len > 0) try any_of_list.toOwnedSlice() else null,
            .items = if (obj.get("items")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .properties = if (properties_map.count() > 0) properties_map else null,
            .additionalProperties = if (obj.get("additionalProperties")) |val| try AdditionalProperties.parse(allocator, val) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .format = if (obj.get("format")) |val| try allocator.dupe(u8, val.string) else null,
            .default = if (obj.get("default")) |val| val else null,
            .nullable = if (obj.get("nullable")) |val| val.bool else null,
            .discriminator = if (obj.get("discriminator")) |val| try Discriminator.parse(allocator, val) else null,
            .readOnly = if (obj.get("readOnly")) |val| val.bool else null,
            .writeOnly = if (obj.get("writeOnly")) |val| val.bool else null,
            .example = if (obj.get("example")) |val| val else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try @import("externaldocs.zig").ExternalDocumentation.parse(allocator, val) else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .xml = if (obj.get("xml")) |val| try XML.parse(allocator, val) else null,
        };
    }
};
