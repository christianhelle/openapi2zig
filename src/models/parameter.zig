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

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Parameter {
        const obj = value.object;
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parse(allocator, content_val.object.get(key).?));
            }
        }
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parse(allocator, examples_val.object.get(key).?));
            }
        }

        return Parameter{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .in_field = try allocator.dupe(u8, obj.get("in").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .allowEmptyValue = if (obj.get("allowEmptyValue")) |val| val.bool else null,
            .style = if (obj.get("style")) |val| try allocator.dupe(u8, val.string) else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parse(allocator, val) else null,
            .content = if (content_map.count() > 0) content_map else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
        };
    }
};

pub const ParameterOrReference = union(enum) {
    parameter: Parameter,
    reference: Reference,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ParameterOrReference {
        if (value.object.get("$ref") != null) {
            return ParameterOrReference{ .reference = try Reference.parse(allocator, value) };
        } else {
            return ParameterOrReference{ .parameter = try Parameter.parse(allocator, value) };
        }
    }
};
