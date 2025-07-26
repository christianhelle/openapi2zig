const std = @import("std");
const json = std.json;
const SchemaOrReference = @import("schema.zig").SchemaOrReference;
const Reference = @import("reference.zig").Reference;

pub const Example = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    value: ?json.Value = null,
    externalValue: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Example {
        const obj = value.object;
        return Example{
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .value = if (obj.get("value")) |val| val else null,
            .externalValue = if (obj.get("externalValue")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: *Example, allocator: std.mem.Allocator) void {
        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |description| allocator.free(description);
        if (self.externalValue) |externalValue| allocator.free(externalValue);
    }
};

pub const ExampleOrReference = union(enum) {
    example: Example,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ExampleOrReference {
        if (value.object.get("$ref") != null) {
            return ExampleOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return ExampleOrReference{ .example = try Example.parseFromJson(allocator, value) };
        }
    }

    pub fn deinit(self: *ExampleOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .example => |*example| example.deinit(allocator),
            .reference => |*reference| reference.deinit(allocator),
        }
    }
};

pub const HeaderOrReference = union(enum) {
    header: Header,
    reference: Reference,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!HeaderOrReference {
        if (value.object.get("$ref") != null) {
            return HeaderOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return HeaderOrReference{ .header = try Header.parseFromJson(allocator, value) };
        }
    }

    pub fn deinit(self: *HeaderOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .header => |*header| header.deinit(allocator),
            .reference => |*reference| reference.deinit(allocator),
        }
    }
};

pub const Encoding = struct {
    contentType: ?[]const u8 = null,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    style: ?[]const u8 = null, // "form", "spaceDelimited", "pipeDelimited", "deepObject"
    explode: ?bool = null,
    allowReserved: ?bool = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Encoding {
        const obj = value.object;
        var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
        if (obj.get("headers")) |headers_val| {
            for (headers_val.object.keys()) |key| {
                try headers_map.put(try allocator.dupe(u8, key), try HeaderOrReference.parseFromJson(allocator, headers_val.object.get(key).?));
            }
        }
        return Encoding{
            .contentType = if (obj.get("contentType")) |val| try allocator.dupe(u8, val.string) else null,
            .headers = if (headers_map.count() > 0) headers_map else null,
            .style = if (obj.get("style")) |val| try allocator.dupe(u8, val.string) else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
        };
    }

    pub fn deinit(self: *Encoding, allocator: std.mem.Allocator) void {
        if (self.contentType) |contentType| allocator.free(contentType);
        if (self.style) |style| allocator.free(style);

        if (self.headers) |*headers| {
            var iterator = headers.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            headers.deinit();
        }
    }
};

pub const MediaType = struct {
    schema: ?SchemaOrReference = null,
    example: ?json.Value = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    encoding: ?std.StringHashMap(Encoding) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!MediaType {
        const obj = value.object;
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(try allocator.dupe(u8, key), try ExampleOrReference.parseFromJson(allocator, examples_val.object.get(key).?));
            }
        }
        var encoding_map = std.StringHashMap(Encoding).init(allocator);
        if (obj.get("encoding")) |encoding_val| {
            for (encoding_val.object.keys()) |key| {
                try encoding_map.put(try allocator.dupe(u8, key), try Encoding.parseFromJson(allocator, encoding_val.object.get(key).?));
            }
        }

        return MediaType{
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parseFromJson(allocator, val) else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
            .encoding = if (encoding_map.count() > 0) encoding_map else null,
        };
    }

    pub fn deinit(self: *MediaType, allocator: std.mem.Allocator) void {
        if (self.schema) |*schema| {
            schema.deinit(allocator);
        }

        if (self.examples) |*examples| {
            var iterator = examples.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            examples.deinit();
        }

        if (self.encoding) |*encoding| {
            var iterator = encoding.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            encoding.deinit();
        }
    }
};

pub const Header = struct {
    description: ?[]const u8 = null,
    required: ?bool = null,
    deprecated: ?bool = null,
    allowEmptyValue: ?bool = null,
    style: ?[]const u8 = null, // "simple"
    explode: ?bool = null,
    allowReserved: ?bool = null,
    schema: ?SchemaOrReference = null,
    content: ?std.StringHashMap(MediaType) = null,
    example: ?json.Value = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Header {
        const obj = value.object;
        var content_map = std.StringHashMap(MediaType).init(allocator);
        if (obj.get("content")) |content_val| {
            for (content_val.object.keys()) |key| {
                try content_map.put(try allocator.dupe(u8, key), try MediaType.parseFromJson(allocator, content_val.object.get(key).?));
            }
        }
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(try allocator.dupe(u8, key), try ExampleOrReference.parseFromJson(allocator, examples_val.object.get(key).?));
            }
        }

        return Header{
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .required = if (obj.get("required")) |val| val.bool else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .allowEmptyValue = if (obj.get("allowEmptyValue")) |val| val.bool else null,
            .style = if (obj.get("style")) |val| try allocator.dupe(u8, val.string) else null,
            .explode = if (obj.get("explode")) |val| val.bool else null,
            .allowReserved = if (obj.get("allowReserved")) |val| val.bool else null,
            .schema = if (obj.get("schema")) |val| try SchemaOrReference.parseFromJson(allocator, val) else null,
            .content = if (content_map.count() > 0) content_map else null,
            .example = if (obj.get("example")) |val| val else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
        };
    }

    pub fn deinit(self: *Header, allocator: std.mem.Allocator) void {
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
