const std = @import("std");
const json = std.json;

pub const Reference = struct {
    ref: []const u8,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Reference {
        const obj = value.object;
        return Reference{ .ref = try allocator.dupe(u8, obj.get("$ref").?.string) };
    }

    pub fn deinit(self: *Reference, allocator: std.mem.Allocator) void {
        allocator.free(self.ref);
    }
};
