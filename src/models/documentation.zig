const std = @import("std");
const json = std.json;

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!ExternalDocumentation {
        const obj = value.object;
        return ExternalDocumentation{
            .url = try allocator.dupe(u8, obj.get("url").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: ExternalDocumentation, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
    }
};
