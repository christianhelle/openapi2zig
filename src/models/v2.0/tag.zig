const std = @import("std");
const json = std.json;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Tag {
        return Tag{
            .name = try allocator.dupe(u8, value.object.get("name").?.string),
            .description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .externalDocs = if (value.object.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null,
        };
    }

    pub fn deinit(self: *Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |description| allocator.free(description);
        if (self.externalDocs) |*external_docs| external_docs.deinit(allocator);
    }
};
