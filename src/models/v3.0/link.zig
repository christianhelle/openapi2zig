const std = @import("std");
const json = std.json;
const Server = @import("server.zig").Server;
const Reference = @import("reference.zig").Reference;

pub const Link = struct {
    operationId: ?[]const u8 = null,
    operationRef: ?[]const u8 = null,
    parameters: ?std.StringHashMap(json.Value) = null, // Can be any type
    requestBody: ?json.Value = null, // Can be any type
    description: ?[]const u8 = null,
    server: ?Server = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Link {
        const obj = value.object;
        var parameters_map = std.StringHashMap(json.Value).init(allocator);
        if (obj.get("parameters")) |params_val| {
            for (params_val.object.keys()) |key| {
                try parameters_map.put(key, params_val.object.get(key).?);
            }
        }
        return Link{
            .operationId = if (obj.get("operationId")) |val| try allocator.dupe(u8, val.string) else null,
            .operationRef = if (obj.get("operationRef")) |val| try allocator.dupe(u8, val.string) else null,
            .parameters = if (parameters_map.count() > 0) parameters_map else null,
            .requestBody = if (obj.get("requestBody")) |val| val else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .server = if (obj.get("server")) |val| try Server.parseFromJson(allocator, val) else null,
        };
    }
};

pub const LinkOrReference = union(enum) {
    link: Link,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!LinkOrReference {
        if (value.object.get("$ref") != null) {
            return LinkOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return LinkOrReference{ .link = try Link.parseFromJson(allocator, value) };
        }
    }
};
