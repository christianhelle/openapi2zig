const std = @import("std");

/// Some provider specifications omit this required OpenAPI metadata.
/// Keep generation usable without inventing an API version.
pub fn parse(info: std.json.ObjectMap) ![]const u8 {
    const value = info.get("version") orelse {
        if (!@import("builtin").is_test) std.log.warn("OpenAPI info.version is missing; using 'unknown' metadata", .{});
        return "unknown";
    };
    return switch (value) {
        .string => |text| text,
        else => error.InvalidInfoVersion,
    };
}
