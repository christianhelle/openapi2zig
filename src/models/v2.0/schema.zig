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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        const name = if (obj.get("name")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const namespace = if (obj.get("namespace")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const prefix = if (obj.get("prefix")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const attribute = if (obj.get("attribute")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
        const wrapped = if (obj.get("wrapped")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
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
    ref: ?[]const u8 = null, // $ref
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    default: ?json.Value = null,
    type: ?[]const u8 = null,
    format: ?[]const u8 = null,
    multipleOf: ?f64 = null,
    maximum: ?f64 = null,
    exclusiveMaximum: ?bool = null,
    minimum: ?f64 = null,
    exclusiveMinimum: ?bool = null,
    maxLength: ?u32 = null,
    minLength: ?u32 = null,
    pattern: ?[]const u8 = null,
    maxItems: ?u32 = null,
    minItems: ?u32 = null,
    uniqueItems: ?bool = null,
    items: ?*Schema = null, // Self-reference for array items
    maxProperties: ?u32 = null,
    minProperties: ?u32 = null,
    required: ?[][]const u8 = null,
    properties: ?std.StringHashMap(Schema) = null,
    additionalProperties: ?*Schema = null, // Can be schema or boolean
    allOf: ?[]Schema = null,
    enum_values: ?[]json.Value = null, // enum is a keyword in Zig
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        const ref = if (obj.get("$ref")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const title = if (obj.get("title")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const description = if (obj.get("description")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const default = if (obj.get("default")) |val| val else null;
        
        const type_val = if (obj.get("type")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const format = if (obj.get("format")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const multipleOf = if (obj.get("multipleOf")) |val| switch (val) {
            .float => |f| f,
            .integer => |i| @as(f64, @floatFromInt(i)),
            else => null,
        } else null;
        
        const maximum = if (obj.get("maximum")) |val| switch (val) {
            .float => |f| f,
            .integer => |i| @as(f64, @floatFromInt(i)),
            else => null,
        } else null;
        
        const exclusiveMaximum = if (obj.get("exclusiveMaximum")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
        const minimum = if (obj.get("minimum")) |val| switch (val) {
            .float => |f| f,
            .integer => |i| @as(f64, @floatFromInt(i)),
            else => null,
        } else null;
        
        const exclusiveMinimum = if (obj.get("exclusiveMinimum")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
        const maxLength = if (obj.get("maxLength")) |val| switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            else => null,
        } else null;
        
        const minLength = if (obj.get("minLength")) |val| switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            else => null,
        } else null;
        
        const pattern = if (obj.get("pattern")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const maxItems = if (obj.get("maxItems")) |val| switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            else => null,
        } else null;
        
        const minItems = if (obj.get("minItems")) |val| switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            else => null,
        } else null;
        
        const uniqueItems = if (obj.get("uniqueItems")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
        const items = if (obj.get("items")) |val| blk: {
            const schema_ptr = try allocator.create(Schema);
            schema_ptr.* = try Schema.parseFromJson(allocator, val);
            break :blk schema_ptr;
        } else null;
        
        const maxProperties = if (obj.get("maxProperties")) |val| switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            else => null,
        } else null;
        
        const minProperties = if (obj.get("minProperties")) |val| switch (val) {
            .integer => |i| @as(u32, @intCast(i)),
            else => null,
        } else null;
        
        const required = if (obj.get("required")) |val| try parseStringArray(allocator, val) else null;
        const properties = if (obj.get("properties")) |val| try parseProperties(allocator, val) else null;
        
        const additionalProperties = if (obj.get("additionalProperties")) |val| blk: {
            switch (val) {
                .object => {
                    const schema_ptr = try allocator.create(Schema);
                    schema_ptr.* = try Schema.parseFromJson(allocator, val);
                    break :blk schema_ptr;
                },
                else => break :blk null,
            }
        } else null;
        
        const allOf = if (obj.get("allOf")) |val| try parseSchemaArray(allocator, val) else null;
        const enum_values = if (obj.get("enum")) |val| try parseJsonValueArray(allocator, val) else null;
        
        const discriminator = if (obj.get("discriminator")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const readOnly = if (obj.get("readOnly")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
        const xml = if (obj.get("xml")) |val| try Xml.parseFromJson(allocator, val) else null;
        const externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null;
        const example = if (obj.get("example")) |val| val else null;
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
        const arr = switch (value) {
            .array => |a| a,
            else => return error.ExpectedArray,
        };

        var array_list = std.ArrayList([]const u8).init(allocator);
        errdefer array_list.deinit();
        for (arr.items) |item| {
            const str = switch (item) {
                .string => |s| s,
                else => return error.ExpectedString,
            };
            try array_list.append(try allocator.dupe(u8, str));
        }
        return array_list.toOwnedSlice();
    }
    
    fn parseProperties(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Schema) {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var map = std.StringHashMap(Schema).init(allocator);
        errdefer map.deinit();
        var iterator = obj.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const schema = try Schema.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, schema);
        }
        return map;
    }
    
    fn parseSchemaArray(allocator: std.mem.Allocator, value: json.Value) anyerror![]Schema {
        const arr = switch (value) {
            .array => |a| a,
            else => return error.ExpectedArray,
        };

        var array_list = std.ArrayList(Schema).init(allocator);
        errdefer array_list.deinit();
        for (arr.items) |item| {
            try array_list.append(try Schema.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }
    
    fn parseJsonValueArray(allocator: std.mem.Allocator, value: json.Value) anyerror![]json.Value {
        const arr = switch (value) {
            .array => |a| a,
            else => return error.ExpectedArray,
        };

        var array_list = std.ArrayList(json.Value).init(allocator);
        errdefer array_list.deinit();
        for (arr.items) |item| {
            try array_list.append(item);
        }
        return array_list.toOwnedSlice();
    }
};
