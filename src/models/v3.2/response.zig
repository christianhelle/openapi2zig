const std = @import("std");
const json = std.json;
const MediaType = @import("media.zig").MediaType;
const HeaderOrReference = @import("media.zig").HeaderOrReference;
const LinkOrReference = @import("link.zig").LinkOrReference;
const Reference = @import("reference.zig").Reference;

fn deinitHeadersMap(map: *std.StringHashMap(HeaderOrReference), allocator: std.mem.Allocator) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(allocator);
    }
    map.deinit();
}

fn deinitContentMap(map: *std.StringHashMap(MediaType), allocator: std.mem.Allocator) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(allocator);
    }
    map.deinit();
}

fn deinitLinksMap(map: *std.StringHashMap(LinkOrReference), allocator: std.mem.Allocator) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(allocator);
    }
    map.deinit();
}

pub const Response = struct {
    description: []const u8,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    content: ?std.StringHashMap(MediaType) = null,
    links: ?std.StringHashMap(LinkOrReference) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Response {
        const obj = value.object;
        var headers_map: ?std.StringHashMap(HeaderOrReference) = null;
        if (obj.get("headers")) |headers_val| {
            var map = std.StringHashMap(HeaderOrReference).init(allocator);
            errdefer deinitHeadersMap(&map, allocator);
            for (headers_val.object.keys()) |key| {
                try map.put(try allocator.dupe(u8, key), try HeaderOrReference.parseFromJson(allocator, headers_val.object.get(key).?));
            }
            if (map.count() > 0) {
                headers_map = map;
            } else {
                map.deinit();
            }
        }
        var content_map: ?std.StringHashMap(MediaType) = null;
        if (obj.get("content")) |content_val| {
            var map = std.StringHashMap(MediaType).init(allocator);
            errdefer deinitContentMap(&map, allocator);
            for (content_val.object.keys()) |key| {
                try map.put(try allocator.dupe(u8, key), try MediaType.parseFromJson(allocator, content_val.object.get(key).?));
            }
            if (map.count() > 0) {
                content_map = map;
            } else {
                map.deinit();
            }
        }
        var links_map: ?std.StringHashMap(LinkOrReference) = null;
        if (obj.get("links")) |links_val| {
            var map = std.StringHashMap(LinkOrReference).init(allocator);
            errdefer deinitLinksMap(&map, allocator);
            for (links_val.object.keys()) |key| {
                try map.put(try allocator.dupe(u8, key), try LinkOrReference.parseFromJson(allocator, links_val.object.get(key).?));
            }
            if (map.count() > 0) {
                links_map = map;
            } else {
                map.deinit();
            }
        }
        return Response{
            .description = try allocator.dupe(u8, obj.get("description").?.string),
            .headers = headers_map,
            .content = content_map,
            .links = links_map,
        };
    }

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        if (self.headers) |*headers| {
            deinitHeadersMap(headers, allocator);
        }
        if (self.content) |*content| {
            deinitContentMap(content, allocator);
        }
        if (self.links) |*links| {
            deinitLinksMap(links, allocator);
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
        errdefer {
            var iterator = status_codes_map.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            status_codes_map.deinit();
        }
        const obj = value.object;
        for (obj.keys()) |key| {
            if (key.len > 0 and std.ascii.isDigit(key[0])) {
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
