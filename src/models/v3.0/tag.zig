const std = @import("std");
const json = std.json;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Tag = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Tag {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };
        
        const name_str = switch (obj.get("name") orelse return error.MissingName) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        return Tag{
            .name = try allocator.dupe(u8, name_str),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null,
        };
    }

    pub fn deinit(self: Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.description) |desc| allocator.free(desc);
        if (self.externalDocs) |docs| docs.deinit(allocator);
    }
};
