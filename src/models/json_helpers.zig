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
