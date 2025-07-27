const std = @import("std");
const json = std.json;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;
pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Tag {
        const obj = value.object;
        return Tag{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null,
        };
    }
    pub fn deinit(self: Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |desc| allocator.free(desc);
        if (self.externalDocs) |docs| docs.deinit(allocator);
    }
};
