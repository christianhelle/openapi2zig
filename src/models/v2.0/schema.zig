const std = @import("std");
const json = std.json;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Xml = struct {
    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    prefix: ?[]const u8 = null,
    attribute: ?bool = null,
    wrapped: ?bool = null,

    pub fn deinit(self: *Xml, allocator: std.mem.Allocator) void {
        if (self.name) |name| {
            allocator.free(name);
        }
        if (self.namespace) |namespace| {
            allocator.free(namespace);
        }
        if (self.prefix) |prefix| {
            allocator.free(prefix);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Xml {
        const name = if (value.object.get("name")) |val| try allocator.dupe(u8, val.string) else null;
        const namespace = if (value.object.get("namespace")) |val| try allocator.dupe(u8, val.string) else null;
        const prefix = if (value.object.get("prefix")) |val| try allocator.dupe(u8, val.string) else null;
        const attribute = if (value.object.get("attribute")) |val| val.bool else null;
        const wrapped = if (value.object.get("wrapped")) |val| val.bool else null;

        return Xml{
            .name = name,
            .namespace = namespace,
            .prefix = prefix,
            .attribute = attribute,
            .wrapped = wrapped,
        };
    }
};

pub const Schema = struct {
    // JSON Schema Core Properties
    ref: ?[]const u8 = null, // $ref
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    default: ?json.Value = null,
    type: ?[]const u8 = null,
    format: ?[]const u8 = null,

    // Numeric validation
    multipleOf: ?f64 = null,
    maximum: ?f64 = null,
    exclusiveMaximum: ?bool = null,
    minimum: ?f64 = null,
    exclusiveMinimum: ?bool = null,

    // String validation
    maxLength: ?u32 = null,
    minLength: ?u32 = null,
    pattern: ?[]const u8 = null,

    // Array validation
    maxItems: ?u32 = null,
    minItems: ?u32 = null,
    uniqueItems: ?bool = null,
    items: ?*Schema = null, // Self-reference for array items

    // Object validation
    maxProperties: ?u32 = null,
    minProperties: ?u32 = null,
    required: ?[][]const u8 = null,
    properties: ?std.StringHashMap(Schema) = null,
    additionalProperties: ?*Schema = null, // Can be schema or boolean

    // Composition
    allOf: ?[]Schema = null,

    // Enumeration
    enum_values: ?[]json.Value = null, // enum is a keyword in Zig

    // Swagger-specific
    discriminator: ?[]const u8 = null,
    readOnly: ?bool = null,
    xml: ?Xml = null,
    externalDocs: ?ExternalDocumentation = null,
    example: ?json.Value = null,

    pub fn deinit(self: *Schema, allocator: std.mem.Allocator) void {
        if (self.ref) |ref| {
            allocator.free(ref);
        }
        if (self.title) |title| {
            allocator.free(title);
        }
        if (self.description) |description| {
            allocator.free(description);
        }
        if (self.type) |type_val| {
            allocator.free(type_val);
        }
        if (self.format) |format| {
            allocator.free(format);
        }
        if (self.pattern) |pattern| {
            allocator.free(pattern);
        }
        if (self.items) |items| {
            items.deinit(allocator);
            allocator.destroy(items);
        }
        if (self.required) |required| {
            for (required) |req| {
                allocator.free(req);
            }
            allocator.free(required);
        }
        if (self.properties) |*properties| {
            var iterator = properties.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            properties.deinit();
        }
        if (self.additionalProperties) |additionalProps| {
            additionalProps.deinit(allocator);
            allocator.destroy(additionalProps);
        }
        if (self.allOf) |allOf| {
            for (allOf) |*schema| {
                schema.deinit(allocator);
            }
            allocator.free(allOf);
        }
        if (self.enum_values) |enum_vals| {
            allocator.free(enum_vals);
        }
        if (self.discriminator) |discriminator| {
            allocator.free(discriminator);
        }
        if (self.xml) |*xml| {
            xml.deinit(allocator);
        }
        if (self.externalDocs) |*external_docs| {
            external_docs.deinit(allocator);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Schema {
        const ref = if (value.object.get("$ref")) |val| try allocator.dupe(u8, val.string) else null;
        const title = if (value.object.get("title")) |val| try allocator.dupe(u8, val.string) else null;
        const description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null;
        const default = if (value.object.get("default")) |val| val else null;
        const type_val = if (value.object.get("type")) |val| try allocator.dupe(u8, val.string) else null;
        const format = if (value.object.get("format")) |val| try allocator.dupe(u8, val.string) else null;

        const multipleOf = if (value.object.get("multipleOf")) |val| val.float else null;
        const maximum = if (value.object.get("maximum")) |val| val.float else null;
        const exclusiveMaximum = if (value.object.get("exclusiveMaximum")) |val| val.bool else null;
        const minimum = if (value.object.get("minimum")) |val| val.float else null;
        const exclusiveMinimum = if (value.object.get("exclusiveMinimum")) |val| val.bool else null;

        const maxLength = if (value.object.get("maxLength")) |val| @as(u32, @intCast(val.integer)) else null;
        const minLength = if (value.object.get("minLength")) |val| @as(u32, @intCast(val.integer)) else null;
        const pattern = if (value.object.get("pattern")) |val| try allocator.dupe(u8, val.string) else null;

        const maxItems = if (value.object.get("maxItems")) |val| @as(u32, @intCast(val.integer)) else null;
        const minItems = if (value.object.get("minItems")) |val| @as(u32, @intCast(val.integer)) else null;
        const uniqueItems = if (value.object.get("uniqueItems")) |val| val.bool else null;

        const items = if (value.object.get("items")) |val| blk: {
            const schema_ptr = try allocator.create(Schema);
            schema_ptr.* = try Schema.parseFromJson(allocator, val);
            break :blk schema_ptr;
        } else null;

        const maxProperties = if (value.object.get("maxProperties")) |val| @as(u32, @intCast(val.integer)) else null;
        const minProperties = if (value.object.get("minProperties")) |val| @as(u32, @intCast(val.integer)) else null;

        const required = if (value.object.get("required")) |val| try parseStringArray(allocator, val) else null;
        const properties = if (value.object.get("properties")) |val| try parseProperties(allocator, val) else null;

        const additionalProperties = if (value.object.get("additionalProperties")) |val| blk: {
            if (val == .object) {
                const schema_ptr = try allocator.create(Schema);
                schema_ptr.* = try Schema.parseFromJson(allocator, val);
                break :blk schema_ptr;
            }
            break :blk null;
        } else null;

        const allOf = if (value.object.get("allOf")) |val| try parseSchemaArray(allocator, val) else null;
        const enum_values = if (value.object.get("enum")) |val| try parseJsonValueArray(allocator, val) else null;

        const discriminator = if (value.object.get("discriminator")) |val| try allocator.dupe(u8, val.string) else null;
        const readOnly = if (value.object.get("readOnly")) |val| val.bool else null;
        const xml = if (value.object.get("xml")) |val| try Xml.parseFromJson(allocator, val) else null;
        const externalDocs = if (value.object.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null;
        const example = if (value.object.get("example")) |val| val else null;

        return Schema{
            .ref = ref,
            .title = title,
            .description = description,
            .default = default,
            .type = type_val,
            .format = format,
            .multipleOf = multipleOf,
            .maximum = maximum,
            .exclusiveMaximum = exclusiveMaximum,
            .minimum = minimum,
            .exclusiveMinimum = exclusiveMinimum,
            .maxLength = maxLength,
            .minLength = minLength,
            .pattern = pattern,
            .maxItems = maxItems,
            .minItems = minItems,
            .uniqueItems = uniqueItems,
            .items = items,
            .maxProperties = maxProperties,
            .minProperties = minProperties,
            .required = required,
            .properties = properties,
            .additionalProperties = additionalProperties,
            .allOf = allOf,
            .enum_values = enum_values,
            .discriminator = discriminator,
            .readOnly = readOnly,
            .xml = xml,
            .externalDocs = externalDocs,
            .example = example,
        };
    }

    fn parseStringArray(allocator: std.mem.Allocator, value: json.Value) anyerror![][]const u8 {
        var array_list = std.ArrayList([]const u8).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try allocator.dupe(u8, item.string));
        }
        return array_list.toOwnedSlice();
    }

    fn parseProperties(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Schema) {
        var map = std.StringHashMap(Schema).init(allocator);
        errdefer map.deinit();

        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const schema = try Schema.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, schema);
        }
        return map;
    }

    fn parseSchemaArray(allocator: std.mem.Allocator, value: json.Value) anyerror![]Schema {
        var array_list = std.ArrayList(Schema).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try Schema.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }

    fn parseJsonValueArray(allocator: std.mem.Allocator, value: json.Value) anyerror![]json.Value {
        var array_list = std.ArrayList(json.Value).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(item);
        }
        return array_list.toOwnedSlice();
    }
};
