const std = @import("std");
const json = std.json;

pub const Reference = struct {
    ref: []const u8,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Reference {
        const obj = value.object;
        return Reference{
            .ref = try allocator.dupe(u8, obj.get("$ref").?.string),
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: *Reference, allocator: std.mem.Allocator) void {
        allocator.free(self.ref);
        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |description| allocator.free(description);
    }
};
