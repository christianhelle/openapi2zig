const std = @import("std");
const json = std.json;
const SchemaOrReference = @import("schema.zig").SchemaOrReference;
const Reference = @import("reference.zig").Reference;
const MediaType = @import("media.zig").MediaType;
const ExampleOrReference = @import("media.zig").ExampleOrReference;

pub const Parameter = struct {
    name: []const u8,
    in_field: []const u8, // Renamed 'in' to 'in_field' to avoid keyword conflict
    description: ?[]const u8 = null,
    required: ?bool = null,
    deprecated: ?bool = null,
    allowEmptyValue: ?bool = null,
    style: ?[]const u8 = null,
    explode: ?bool = null,
    allowReserved: ?bool = null,
    schema: ?SchemaOrReference = null,
    content: ?std.StringHashMap(MediaType) = null,
    example: ?json.Value = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Parameter {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            const content_obj = switch (content_val) {
                .object => |o| o,
                else => return error.ExpectedObject,
            };
            
            var iter = content_obj.iterator();
            while (iter.next()) |entry| {
                try content_map.put(try allocator.dupe(u8, entry.key_ptr.*), try MediaType.parseFromJson(allocator, entry.value_ptr.*));
            }
        }
        
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            const examples_obj = switch (examples_val) {
                .object => |o| o,
                else => return error.ExpectedObject,
            };
            
            var iter = examples_obj.iterator();
            while (iter.next()) |entry| {
                try examples_map.put(try allocator.dupe(u8, entry.key_ptr.*), try ExampleOrReference.parseFromJson(allocator, entry.value_ptr.*));
            }
        }
        
        const name_str = switch (obj.get("name") orelse return error.MissingName) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        const in_str = switch (obj.get("in") orelse return error.MissingIn) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        return Parameter{
            .name = try allocator.dupe(u8, name_str),
            .in_field = try allocator.dupe(u8, in_str),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .required = if (obj.get("required")) |val| switch (val) {
                .bool => |b| b,
                else => null,
            } else null,
            .deprecated = if (obj.get("deprecated")) |val| switch (val) {
                .bool => |b| b,
                else => null,
            } else null,
            .allowEmptyValue = if (obj.get("allowEmptyValue")) |val| switch (val) {
                .bool => |b| b,
                else => null,
            } else null,
            .style = if (obj.get("style")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .explode = if (obj.get("explode")) |val| switch (val) {
                .bool => |b| b,
                else => null,
            } else null,
            .allowReserved = if (obj.get("allowReserved")) |val| switch (val) {
                .bool => |b| b,
                else => null,
            } else null,
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parseFromJson(allocator, val) else null,
            .content = if (content_map.count() > 0) content_map else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
        };
    }

    pub fn deinit(self: *Parameter, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.in_field);
        if (self.description) |description| allocator.free(description);
        if (self.style) |style| allocator.free(style);
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }
        if (self.content) |*content| {
            var iterator = content.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            content.deinit();
        }
        if (self.examples) |*examples| {
            var iterator = examples.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            examples.deinit();
        }
    }
};

pub const ParameterOrReference = union(enum) {
    parameter: Parameter,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ParameterOrReference {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        if (obj.get("$ref") != null) {
            return ParameterOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return ParameterOrReference{ .parameter = try Parameter.parseFromJson(allocator, value) };
        }
    }

    pub fn deinit(self: *ParameterOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .parameter => |*param| param.deinit(allocator),
            .reference => |*ref| ref.deinit(allocator),
        }
    }
};
