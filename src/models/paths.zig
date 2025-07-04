const std = @import("std");
const Operation = @import("operation.zig").Operation;

pub const Paths = struct {
    items: std.AutoHashMap([]const u8, PathItem),
};

pub const PathItem = struct {
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    trace: ?Operation = null,
};
