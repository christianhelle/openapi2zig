const std = @import("std");
const json = std.json;
const Schema = @import("schema.zig").Schema;

pub const Header = struct {
    type: []const u8,
    format: ?[]const u8 = null,
    description: ?[]const u8 = null,
    // Add other header validation properties as needed

    pub fn deinit(self: *Header, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        if (self.format) |format| {
            allocator.free(format);
        }
        if (self.description) |description| {
            allocator.free(description);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Header {
        const type_val = try allocator.dupe(u8, value.object.get("type").?.string);
        const format = if (value.object.get("format")) |val| try allocator.dupe(u8, val.string) else null;
        const description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null;

        return Header{
            .type = type_val,
            .format = format,
            .description = description,
        };
    }
};

pub const Response = struct {
    description: []const u8,
    schema: ?Schema = null,
    headers: ?std.StringHashMap(Header) = null,
    examples: ?std.StringHashMap(json.Value) = null,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }
        if (self.headers) |*headers| {
            var iterator = headers.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            headers.deinit();
        }
        if (self.examples) |*examples| {
            var iterator = examples.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                // json.Value doesn't need explicit cleanup
            }
            examples.deinit();
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Response {
        const description = try allocator.dupe(u8, value.object.get("description").?.string);
        const schema = if (value.object.get("schema")) |val| try Schema.parseFromJson(allocator, val) else null;
        const headers = if (value.object.get("headers")) |val| try parseHeaders(allocator, val) else null;
        const examples = if (value.object.get("examples")) |val| try parseExamples(allocator, val) else null;

        return Response{
            .description = description,
            .schema = schema,
            .headers = headers,
            .examples = examples,
        };
    }

    fn parseHeaders(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Header) {
        var map = std.StringHashMap(Header).init(allocator);
        errdefer map.deinit();

        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const header = try Header.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, header);
        }
        return map;
    }

    fn parseExamples(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(json.Value) {
        var map = std.StringHashMap(json.Value).init(allocator);
        errdefer map.deinit();

        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            try map.put(key, entry.value_ptr.*);
        }
        return map;
    }
};
