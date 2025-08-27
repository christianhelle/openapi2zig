const std = @import("std");
const json = std.json;

pub const ExternalDocumentation = struct {
    url: []const u8,
    description: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ExternalDocumentation {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };
        
        const url_str = switch (obj.get("url") orelse return error.MissingUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        return ExternalDocumentation{
            .url = try allocator.dupe(u8, url_str),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
        };
    }

    pub fn deinit(self: ExternalDocumentation, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
    }
};
