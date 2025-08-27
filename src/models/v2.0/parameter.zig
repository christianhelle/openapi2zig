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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        const type_str = switch (obj.get("type") orelse return error.MissingType) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        const type_val = PrimitiveType.fromString(type_str) orelse return error.InvalidParameterType;
        
        const format = if (obj.get("format")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const items = if (obj.get("items")) |val| blk: {
            const items_ptr = try allocator.create(Items);
            items_ptr.* = try Items.parseFromJson(allocator, val);
            break :blk items_ptr;
        } else null;
        
        const collectionFormat_str = if (obj.get("collectionFormat")) |val| switch (val) {
            .string => |str| str,
            else => "csv",
        } else "csv";
        const collectionFormat = CollectionFormat.fromString(collectionFormat_str);
        
        const default = if (obj.get("default")) |val| val else null;
        
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
        
        const enum_values = if (obj.get("enum")) |val| try parseJsonValueArray(allocator, val) else null;
        
        const multipleOf = if (obj.get("multipleOf")) |val| switch (val) {
            .float => |f| f,
            .integer => |i| @as(f64, @floatFromInt(i)),
            else => null,
        } else null;
        const multipleOf = if (obj.get("multipleOf")) |val| switch (val) {
            .float => |f| f,
            .integer => |i| @as(f64, @floatFromInt(i)),
            else => null,
        } else null;
        
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        const name_str = switch (obj.get("name") orelse return error.MissingName) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        const name = try allocator.dupe(u8, name_str);
        
        const in_str = switch (obj.get("in") orelse return error.MissingIn) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        const in_location = ParameterLocation.fromString(in_str) orelse return error.InvalidParameterLocation;
        
        const description = if (obj.get("description")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const required = if (obj.get("required")) |val| switch (val) {
            .bool => |b| b,
            else => false,
        } else false;
        
        if (in_location == .body) {
            const schema = if (obj.get("schema")) |val| try Schema.parseFromJson(allocator, val) else null;
            return Parameter{
                .name = name,
                .in = in_location,
                .description = description,
                .required = required,
                .schema = schema,
            };
        } else {
            const type_str = if (obj.get("type")) |val| switch (val) {
                .string => |str| str,
                else => null,
            } else null;
            const type_val = if (type_str) |ts| PrimitiveType.fromString(ts) else null;
            
            const format = if (obj.get("format")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null;
            
            const allowEmptyValue = if (obj.get("allowEmptyValue")) |val| switch (val) {
                .bool => |b| b,
                else => null,
            } else null;
            
            const items = if (obj.get("items")) |val| try Items.parseFromJson(allocator, val) else null;
            
            const collectionFormat_str = if (obj.get("collectionFormat")) |val| switch (val) {
                .string => |str| str,
                else => "csv",
            } else "csv";
            const collectionFormat = CollectionFormat.fromString(collectionFormat_str);
            
            const default = if (obj.get("default")) |val| val else null;
            
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
            
            const enum_values = if (obj.get("enum")) |val| try parseJsonValueArray(allocator, val) else null;
            
            const multipleOf = if (obj.get("multipleOf")) |val| switch (val) {
                .float => |f| f,
                .integer => |i| @as(f64, @floatFromInt(i)),
                else => null,
            } else null;
            
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
