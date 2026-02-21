const std = @import("std");

const Document = struct {
    openapi: ?[]const u8 = null,
    swagger: ?[]const u8 = null,
};

pub const OpenApiVersion = enum {
    Unsupported,
    v2_0,
    v3_0,
    v3_1,
    v3_2,
};

pub fn getOpenApiVersionString(version: OpenApiVersion) []const u8 {
    return switch (version) {
        .Unsupported => "Unsupported",
        .v2_0 => "v2.0",
        .v3_0 => "v3.0",
        .v3_1 => "v3.1",
        .v3_2 => "v3.2",
    };
}

pub fn getOpenApiVersion(allocator: std.mem.Allocator, json: []const u8) !OpenApiVersion {
    const parsed = try std.json.parseFromSlice(Document, allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const root = parsed.value;

    if (root.openapi) |version| {
        if (std.mem.startsWith(u8, version, "3.2")) {
            return OpenApiVersion.v3_2;
        } else if (std.mem.startsWith(u8, version, "3.1")) {
            return OpenApiVersion.v3_1;
        } else if (std.mem.startsWith(u8, version, "3.0")) {
            return OpenApiVersion.v3_0;
        }
    }

    if (root.swagger) |version| {
        if (std.mem.startsWith(u8, version, "2.0")) {
            return OpenApiVersion.v2_0;
        }
    }

    return OpenApiVersion.Unsupported;
}
