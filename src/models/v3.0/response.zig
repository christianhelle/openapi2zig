const std = @import("std");
const json = std.json;
const MediaType = @import("media.zig").MediaType;
const HeaderOrReference = @import("media.zig").HeaderOrReference;
const LinkOrReference = @import("link.zig").LinkOrReference;
const Reference = @import("reference.zig").Reference;

pub const Response = struct {
    description: []const u8,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    content: ?std.StringHashMap(MediaType) = null,
    links: ?std.StringHashMap(LinkOrReference) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Response {
        const obj = value.object;
        var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
        if (obj.get("headers")) |headers_val| {
            for (headers_val.object.keys()) |key| {
                try headers_map.put(try allocator.dupe(u8, key), try HeaderOrReference.parseFromJson(allocator, headers_val.object.get(key).?));
            }
        }
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(try allocator.dupe(u8, key), try MediaType.parseFromJson(allocator, content_val.object.get(key).?));
            }
        }
        var links_map = std.StringHashMap(LinkOrReference).init(allocator);
        if (obj.get("links")) |links_val| {
            for (links_val.object.keys()) |key| {
                try links_map.put(try allocator.dupe(u8, key), try LinkOrReference.parseFromJson(allocator, links_val.object.get(key).?));
            }
        }
        return Response{
            .description = try allocator.dupe(u8, obj.get("description").?.string),
            .headers = if (headers_map.count() > 0) headers_map else null,
            .content = if (content_map.count() > 0) content_map else null,
            .links = if (links_map.count() > 0) links_map else null,
        };
    }

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        if (self.headers) |*headers| {
            var iterator = headers.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            headers.deinit();
        }
        if (self.content) |*content| {
            var iterator = content.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            content.deinit();
        }
        if (self.links) |*links| {
            var iterator = links.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            links.deinit();
        }
    }
};

pub const ResponseOrReference = union(enum) {
    response: Response,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ResponseOrReference {
        if (value.object.get("$ref") != null) {
            return ResponseOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return ResponseOrReference{ .response = try Response.parseFromJson(allocator, value) };
        }
    }

    pub fn deinit(self: *ResponseOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .response => |*response| response.deinit(allocator),
            .reference => |*reference| reference.deinit(allocator),
        }
    }
};

pub const Responses = struct {
    default: ?ResponseOrReference = null,
    status_codes: std.StringHashMap(ResponseOrReference),

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Responses {
        var status_codes_map = std.StringHashMap(ResponseOrReference).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            if (std.ascii.isDigit(key[0])) { // Status codes are numeric
                try status_codes_map.put(try allocator.dupe(u8, key), try ResponseOrReference.parseFromJson(allocator, obj.get(key).?));
            }
        }
        return Responses{
            .default = if (obj.get("default")) |val| try ResponseOrReference.parseFromJson(allocator, val) else null,
            .status_codes = status_codes_map,
        };
    }

    pub fn deinit(self: *Responses, allocator: std.mem.Allocator) void {
        if (self.default) |*default| {
            default.deinit(allocator);
        }
        var iterator = self.status_codes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.status_codes.deinit();
    }
};
