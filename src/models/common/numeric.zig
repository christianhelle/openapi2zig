const std = @import("std");
const json = std.json;

pub fn toOptionalFloat(value: json.Value) ?f64 {
    return switch (value) {
        .integer => |integer_value| @as(f64, @floatFromInt(integer_value)),
        .float => |float_value| float_value,
        else => null,
    };
}
