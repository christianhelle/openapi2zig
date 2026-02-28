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

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!XML {
        const obj = value.object;
        return XML{
            .name = if (obj.get("name")) |val| try allocator.dupe(u8, val.string) else null,
            .namespace = if (obj.get("namespace")) |val| try allocator.dupe(u8, val.string) else null,
            .prefix = if (obj.get("prefix")) |val| try allocator.dupe(u8, val.string) else null,
            .attribute = if (obj.get("attribute")) |val| val.bool else null,
            .wrapped = if (obj.get("wrapped")) |val| val.bool else null,
        };
    }

    pub fn deinit(self: *XML, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.namespace) |namespace| allocator.free(namespace);
        if (self.prefix) |prefix| allocator.free(prefix);
    }
};

pub const Discriminator = struct {
    propertyName: []const u8,
    mapping: ?std.StringHashMap([]const u8) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Discriminator {
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

    pub fn deinit(self: *Discriminator, allocator: std.mem.Allocator) void {
        allocator.free(self.propertyName);
        if (self.mapping) |*map| {
            var iterator = map.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            map.deinit();
        }
    }
};

pub const AdditionalProperties = union(enum) {
    boolean: bool,
    schema_or_reference: SchemaOrReference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!AdditionalProperties {
        switch (value) {
            .bool => |bool_val| return AdditionalProperties{ .boolean = bool_val },
            .object => return AdditionalProperties{ .schema_or_reference = try SchemaOrReference.parseFromJson(allocator, value) },
            else => return error.InvalidAdditionalPropertiesType,
        }
    }
};

pub const SchemaOrReference = union(enum) {
    schema: *Schema,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SchemaOrReference {
        if (value.object.get("$ref") != null) {
            return SchemaOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            const schema = try allocator.create(Schema);
            errdefer allocator.destroy(schema);
            schema.* = try Schema.parseFromJson(allocator, value);
            return SchemaOrReference{ .schema = schema };
        }
    }

    pub fn deinit(self: *SchemaOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .schema => |schema| {
                schema.deinit(allocator);
                allocator.destroy(schema);
            },
            .reference => |*ref| ref.deinit(allocator),
        }
    }
};

/// OpenAPI 3.1 Schema supports `type` as either a single string or an array of strings
/// (e.g. `["string", "null"]` for nullable types instead of the `nullable` boolean).
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
    enum_values: ?[]const json.Value = null,
    type: ?[]const u8 = null,
    type_array: ?[]const []const u8 = null,
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

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Schema {
        const obj = value.object;
        var required_list = std.ArrayList([]const u8){};
        errdefer required_list.deinit(allocator);
        if (obj.get("required")) |req_val| {
            for (req_val.array.items) |item| {
                try required_list.append(allocator, try allocator.dupe(u8, item.string));
            }
        }
        var enum_list = std.ArrayList(json.Value){};
        errdefer enum_list.deinit(allocator);
        if (obj.get("enum")) |enum_val| {
            for (enum_val.array.items) |item| {
                try enum_list.append(allocator, item);
            }
        }
        var all_of_list = std.ArrayList(SchemaOrReference){};
        errdefer all_of_list.deinit(allocator);
        if (obj.get("allOf")) |all_of_val| {
            for (all_of_val.array.items) |item| {
                try all_of_list.append(allocator, try SchemaOrReference.parseFromJson(allocator, item));
            }
        }
        var one_of_list = std.ArrayList(SchemaOrReference){};
        errdefer one_of_list.deinit(allocator);
        if (obj.get("oneOf")) |one_of_val| {
            for (one_of_val.array.items) |item| {
                try one_of_list.append(allocator, try SchemaOrReference.parseFromJson(allocator, item));
            }
        }
        var any_of_list = std.ArrayList(SchemaOrReference){};
        errdefer any_of_list.deinit(allocator);
        if (obj.get("anyOf")) |any_of_val| {
            for (any_of_val.array.items) |item| {
                try any_of_list.append(allocator, try SchemaOrReference.parseFromJson(allocator, item));
            }
        }
        var properties_map = std.StringHashMap(SchemaOrReference).init(allocator);
        errdefer properties_map.deinit();
        if (obj.get("properties")) |props_val| {
            for (props_val.object.keys()) |key| {
                try properties_map.put(try allocator.dupe(u8, key), try SchemaOrReference.parseFromJson(allocator, props_val.object.get(key).?));
            }
        }

        // In OpenAPI 3.1, "type" can be a string or an array of strings
        var type_str: ?[]const u8 = null;
        var type_array: ?[]const []const u8 = null;
        if (obj.get("type")) |type_val| {
            switch (type_val) {
                .string => |s| {
                    type_str = try allocator.dupe(u8, s);
                },
                .array => |arr| {
                    var type_list = std.ArrayList([]const u8){};
                    errdefer type_list.deinit(allocator);
                    for (arr.items) |item| {
                        try type_list.append(allocator, try allocator.dupe(u8, item.string));
                    }
                    type_array = try type_list.toOwnedSlice(allocator);
                },
                else => {},
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
            .required = if (required_list.items.len > 0) try required_list.toOwnedSlice(allocator) else null,
            .enum_values = if (enum_list.items.len > 0) try enum_list.toOwnedSlice(allocator) else null,
            .type = type_str,
            .type_array = type_array,
            .not = if (obj.get("not")) |val| try SchemaOrReference.parseFromJson(allocator, val) else null,
            .allOf = if (all_of_list.items.len > 0) try all_of_list.toOwnedSlice(allocator) else null,
            .oneOf = if (one_of_list.items.len > 0) try one_of_list.toOwnedSlice(allocator) else null,
            .anyOf = if (any_of_list.items.len > 0) try any_of_list.toOwnedSlice(allocator) else null,
            .items = if (obj.get("items")) |val| try SchemaOrReference.parseFromJson(allocator, val) else null,
            .properties = if (properties_map.count() > 0) properties_map else null,
            .additionalProperties = if (obj.get("additionalProperties")) |val| try AdditionalProperties.parseFromJson(allocator, val) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .format = if (obj.get("format")) |val| try allocator.dupe(u8, val.string) else null,
            .default = if (obj.get("default")) |val| val else null,
            .nullable = if (obj.get("nullable")) |val| val.bool else null,
            .discriminator = if (obj.get("discriminator")) |val| try Discriminator.parseFromJson(allocator, val) else null,
            .readOnly = if (obj.get("readOnly")) |val| val.bool else null,
            .writeOnly = if (obj.get("writeOnly")) |val| val.bool else null,
            .example = if (obj.get("example")) |val| val else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .xml = if (obj.get("xml")) |val| try XML.parseFromJson(allocator, val) else null,
        };
    }

    pub fn deinit(self: *Schema, allocator: std.mem.Allocator) void {
        if (self.title) |title| allocator.free(title);
        if (self.pattern) |pattern| allocator.free(pattern);
        if (self.type) |type_val| allocator.free(type_val);
        if (self.type_array) |type_arr| {
            for (type_arr) |t| {
                allocator.free(t);
            }
            allocator.free(type_arr);
        }
        if (self.description) |description| allocator.free(description);
        if (self.format) |format| allocator.free(format);
        if (self.properties) |props| {
            var iterator = props.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            var mutable_props = @constCast(&props);
            mutable_props.deinit();
        }
        if (self.items) |*items| {
            items.deinit(allocator);
        }
        if (self.required) |req| {
            for (req) |item| {
                allocator.free(item);
            }
            allocator.free(req);
        }
        if (self.allOf) |allOf| {
            for (allOf) |*item| {
                var mutable_item = @constCast(item);
                mutable_item.deinit(allocator);
            }
            allocator.free(allOf);
        }
        if (self.oneOf) |oneOf| {
            for (oneOf) |*item| {
                var mutable_item = @constCast(item);
                mutable_item.deinit(allocator);
            }
            allocator.free(oneOf);
        }
        if (self.anyOf) |anyOf| {
            for (anyOf) |*item| {
                var mutable_item = @constCast(item);
                mutable_item.deinit(allocator);
            }
            allocator.free(anyOf);
        }
        if (self.not) |*not| {
            not.deinit(allocator);
        }
        if (self.additionalProperties) |*additionalProperties| {
            switch (additionalProperties.*) {
                .schema_or_reference => |*schema_ref| schema_ref.deinit(allocator),
                .boolean => {},
            }
        }
        if (self.discriminator) |*discriminator| {
            discriminator.deinit(allocator);
        }
        if (self.externalDocs) |*externalDocs| {
            externalDocs.deinit(allocator);
        }
        if (self.enum_values) |enum_values| {
            allocator.free(enum_values);
        }
        if (self.xml) |*xml| {
            xml.deinit(allocator);
        }
    }
};
