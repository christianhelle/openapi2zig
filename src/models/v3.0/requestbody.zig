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
                try content_map.put(try allocator.dupe(u8, key), try MediaType.parseFromJson(allocator, content_val.object.get(key).?));
            }
        }
        return RequestBody{
            .content = content_map,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
        };
    }

    pub fn deinit(self: *RequestBody, allocator: std.mem.Allocator) void {
        if (self.description) |description| allocator.free(description);

        var iterator = self.content.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.content.deinit();
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

    pub fn deinit(self: *RequestBodyOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .request_body => |*request_body| request_body.deinit(allocator),
            .reference => |*reference| reference.deinit(allocator),
        }
    }
};
