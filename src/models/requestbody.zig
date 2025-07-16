const std = @import("std");
const json = std.json;
const MediaType = @import("media.zig").MediaType;
const Reference = @import("reference.zig").Reference;

pub const RequestBody = struct {
    content: std.StringHashMap(MediaType),
    description: ?[]const u8 = null,
    required: ?bool = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!RequestBody {
        const obj = value.object;
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(key, try MediaType.parseFromJson(allocator, content_val.object.get(key).?));
            }
        }
        return RequestBody{
            .content = content_map,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
        };
    }
};

pub const RequestBodyOrReference = union(enum) {
    request_body: RequestBody,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!RequestBodyOrReference {
        if (value.object.get("$ref") != null) {
            return RequestBodyOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return RequestBodyOrReference{ .request_body = try RequestBody.parseFromJson(allocator, value) };
        }
    }
};
