const std = @import("std");
const json = std.json;

pub fn optionalFloat(value: ?json.Value) ?f64 {
    const val = value orelse return null;
    return switch (val) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        .number_string => |s| std.fmt.parseFloat(f64, s) catch null,
        else => null,
    };
}

/// Copies the heap-backed parts of a scalar JSON value (strings and number
/// strings) so it can outlive the DOM it was parsed from. Containers are shared
/// as is; enum members are scalars.
pub fn cloneScalar(allocator: std.mem.Allocator, value: json.Value) !json.Value {
    return switch (value) {
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        else => value,
    };
}

/// Releases what `cloneScalar` allocated.
pub fn deinitScalar(allocator: std.mem.Allocator, value: json.Value) void {
    switch (value) {
        .string => |s| allocator.free(s),
        .number_string => |s| allocator.free(s),
        else => {},
    }
}
