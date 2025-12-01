const std = @import("std");

pub fn getDataType(field_schema: []const u8) []const u8 {
    if (std.mem.eql(u8, field_schema, "string")) {
        return "[]const u8";
    } else if (std.mem.eql(u8, field_schema, "integer")) {
        return "i64";
    } else if (std.mem.eql(u8, field_schema, "number")) {
        return "f64";
    } else if (std.mem.eql(u8, field_schema, "boolean")) {
        return "bool";
    } else if (std.mem.eql(u8, field_schema, "array")) {
        return "[]const u8";
    } else if (std.mem.eql(u8, field_schema, "object")) {
        return "std.json.Value";
    } else {
        return "[]const u8";
    }
}
