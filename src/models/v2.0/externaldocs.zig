const std = @import("std");
const json = std.json;

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ExternalDocumentation {
        return ExternalDocumentation{
            .url = try allocator.dupe(u8, value.object.get("url").?.string),
            .description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: *ExternalDocumentation, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |description| allocator.free(description);
    }
};
