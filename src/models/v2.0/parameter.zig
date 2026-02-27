const std = @import("std");
const json = std.json;
const Schema = @import("schema.zig").Schema;
pub const ParameterLocation = enum {
    query,
    header,
    path,
    formData,
    body,
    pub fn fromString(str: []const u8) ?ParameterLocation {
        if (std.mem.eql(u8, str, "query")) return .query;
        if (std.mem.eql(u8, str, "header")) return .header;
        if (std.mem.eql(u8, str, "path")) return .path;
        if (std.mem.eql(u8, str, "formData")) return .formData;
        if (std.mem.eql(u8, str, "body")) return .body;
        return null;
    }
};
pub const PrimitiveType = enum {
    string,
    number,
    integer,
    boolean,
    array,
    file,
    pub fn fromString(str: []const u8) ?PrimitiveType {
        if (std.mem.eql(u8, str, "string")) return .string;
        if (std.mem.eql(u8, str, "number")) return .number;
        if (std.mem.eql(u8, str, "integer")) return .integer;
        if (std.mem.eql(u8, str, "boolean")) return .boolean;
        if (std.mem.eql(u8, str, "array")) return .array;
        if (std.mem.eql(u8, str, "file")) return .file;
        return null;
    }
};
pub const CollectionFormat = enum {
    csv,
    ssv,
    tsv,
    pipes,
    multi,
    pub fn fromString(str: []const u8) ?CollectionFormat {
        if (std.mem.eql(u8, str, "csv")) return .csv;
        if (std.mem.eql(u8, str, "ssv")) return .ssv;
        if (std.mem.eql(u8, str, "tsv")) return .tsv;
        if (std.mem.eql(u8, str, "pipes")) return .pipes;
        if (std.mem.eql(u8, str, "multi")) return .multi;
        return null;
    }
};
pub const Items = struct {
    type: PrimitiveType,
    format: ?[]const u8 = null,
    items: ?*Items = null, // For nested arrays
    collectionFormat: ?CollectionFormat = null,
    default: ?json.Value = null,
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
    enum_values: ?[]json.Value = null,
    multipleOf: ?f64 = null,

    pub fn deinit(self: *Items, allocator: std.mem.Allocator) void {
        if (self.format) |format| {
            allocator.free(format);
        }
        if (self.items) |items| {
            items.deinit(allocator);
            allocator.destroy(items);
        }
        if (self.pattern) |pattern| {
            allocator.free(pattern);
        }
        if (self.enum_values) |enum_vals| {
            allocator.free(enum_vals);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Items {
        const type_str = value.object.get("type").?.string;
        const type_val = PrimitiveType.fromString(type_str) orelse return error.InvalidParameterType;
        const format = if (value.object.get("format")) |val| try allocator.dupe(u8, val.string) else null;
        const items = if (value.object.get("items")) |val| blk: {
            const items_ptr = try allocator.create(Items);
            items_ptr.* = try Items.parseFromJson(allocator, val);
            break :blk items_ptr;
        } else null;
        const collectionFormat_str = if (value.object.get("collectionFormat")) |val| val.string else "csv";
        const collectionFormat = CollectionFormat.fromString(collectionFormat_str);
        const default = if (value.object.get("default")) |val| val else null;
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
        const enum_values = if (value.object.get("enum")) |val| try parseJsonValueArray(allocator, val) else null;
        const multipleOf = if (value.object.get("multipleOf")) |val| val.float else null;
        return Items{
            .type = type_val,
            .format = format,
            .items = items,
            .collectionFormat = collectionFormat,
            .default = default,
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
            .enum_values = enum_values,
            .multipleOf = multipleOf,
        };
    }
    fn parseJsonValueArray(allocator: std.mem.Allocator, value: json.Value) anyerror![]json.Value {
        var array_list = std.ArrayList(json.Value){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, item);
        }
        return array_list.toOwnedSlice(allocator);
    }
};
pub const Parameter = struct {
    name: []const u8,
    in: ParameterLocation,
    description: ?[]const u8 = null,
    required: bool = false,
    type: ?PrimitiveType = null,
    format: ?[]const u8 = null,
    allowEmptyValue: ?bool = null,
    items: ?Items = null,
    collectionFormat: ?CollectionFormat = null,
    default: ?json.Value = null,
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
    enum_values: ?[]json.Value = null,
    multipleOf: ?f64 = null,
    schema: ?Schema = null,

    pub fn deinit(self: *Parameter, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |description| {
            allocator.free(description);
        }
        if (self.format) |format| {
            allocator.free(format);
        }
        if (self.items) |*items| {
            items.deinit(allocator);
        }
        if (self.pattern) |pattern| {
            allocator.free(pattern);
        }
        if (self.enum_values) |enum_vals| {
            allocator.free(enum_vals);
        }
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Parameter {
        const name = try allocator.dupe(u8, value.object.get("name").?.string);
        const in_str = value.object.get("in").?.string;
        const in_location = ParameterLocation.fromString(in_str) orelse return error.InvalidParameterLocation;
        const description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null;
        const required = if (value.object.get("required")) |val| val.bool else false;
        if (in_location == .body) {
            const schema = if (value.object.get("schema")) |val| try Schema.parseFromJson(allocator, val) else null;
            return Parameter{
                .name = name,
                .in = in_location,
                .description = description,
                .required = required,
                .schema = schema,
            };
        } else {
            const type_str = if (value.object.get("type")) |val| val.string else null;
            const type_val = if (type_str) |ts| PrimitiveType.fromString(ts) else null;
            const format = if (value.object.get("format")) |val| try allocator.dupe(u8, val.string) else null;
            const allowEmptyValue = if (value.object.get("allowEmptyValue")) |val| val.bool else null;
            const items = if (value.object.get("items")) |val| try Items.parseFromJson(allocator, val) else null;
            const collectionFormat_str = if (value.object.get("collectionFormat")) |val| val.string else "csv";
            const collectionFormat = CollectionFormat.fromString(collectionFormat_str);
            const default = if (value.object.get("default")) |val| val else null;
            const maximum = if (value.object.get("maximum")) |val| val.float else null;
            const exclusiveMaximum = if (value.object.get("exclusiveMaximum")) |val| val.bool else null;
            const minimum = if (value.object.get("minimum")) |val| switch (val) {
                .integer => |i| @as(f64, @floatFromInt(i)),
                .float => |f| f,
                else => null,
            } else null;
            const exclusiveMinimum = if (value.object.get("exclusiveMinimum")) |val| val.bool else null;
            const maxLength = if (value.object.get("maxLength")) |val| @as(u32, @intCast(val.integer)) else null;
            const minLength = if (value.object.get("minLength")) |val| @as(u32, @intCast(val.integer)) else null;
            const pattern = if (value.object.get("pattern")) |val| try allocator.dupe(u8, val.string) else null;
            const maxItems = if (value.object.get("maxItems")) |val| @as(u32, @intCast(val.integer)) else null;
            const minItems = if (value.object.get("minItems")) |val| @as(u32, @intCast(val.integer)) else null;
            const uniqueItems = if (value.object.get("uniqueItems")) |val| val.bool else null;
            const enum_values = if (value.object.get("enum")) |val| try parseJsonValueArray(allocator, val) else null;
            const multipleOf = if (value.object.get("multipleOf")) |val| val.float else null;
            return Parameter{
                .name = name,
                .in = in_location,
                .description = description,
                .required = required,
                .type = type_val,
                .format = format,
                .allowEmptyValue = allowEmptyValue,
                .items = items,
                .collectionFormat = collectionFormat,
                .default = default,
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
                .enum_values = enum_values,
                .multipleOf = multipleOf,
            };
        }
    }
    fn parseJsonValueArray(allocator: std.mem.Allocator, value: json.Value) anyerror![]json.Value {
        var array_list = std.ArrayList(json.Value){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, item);
        }
        return array_list.toOwnedSlice(allocator);
    }
};
