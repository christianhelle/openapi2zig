const std = @import("std");
const json = std.json;

pub const Reference = struct {
    ref: []const u8,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Reference {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };
        
        const ref_str = switch (obj.get("$ref") orelse return error.MissingRef) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
        
        return Reference{ .ref = try allocator.dupe(u8, ref_str) };
    }

    pub fn deinit(self: *Reference, allocator: std.mem.Allocator) void {
        allocator.free(self.ref);
    }
};
