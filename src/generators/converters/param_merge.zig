const std = @import("std");
const document = @import("../../models/common/document.zig");

const Operation = document.Operation;
const Parameter = document.Parameter;

/// Merges path-level parameters into `op`. The OpenAPI rule: an operation sees
/// every parameter of its path item, and an operation-level parameter with the
/// same name and location overrides the path-level one.
///
/// `path_level` must be a freshly converted slice owned by the caller; this
/// function takes ownership of it and of every parameter in it. Kept path-level
/// parameters are placed before the operation's own parameters.
pub fn mergePathLevel(allocator: std.mem.Allocator, op: *Operation, path_level: []Parameter) !void {
    var kept: std.ArrayList(Parameter) = .empty;
    defer kept.deinit(allocator);
    errdefer for (kept.items) |*p| p.deinit(allocator);

    const own: []Parameter = op.parameters orelse &.{};
    for (path_level, 0..) |*param, index| {
        if (isShadowed(own, param.*)) {
            param.deinit(allocator);
        } else {
            kept.append(allocator, param.*) catch |err| {
                for (path_level[index..]) |*rest| rest.deinit(allocator);
                allocator.free(path_level);
                return err;
            };
        }
    }
    allocator.free(path_level);

    if (kept.items.len == 0) return;

    const merged = try allocator.alloc(Parameter, kept.items.len + own.len);
    @memcpy(merged[0..kept.items.len], kept.items);
    @memcpy(merged[kept.items.len..], own);
    if (op.parameters) |old| allocator.free(old);
    op.parameters = merged;
}

fn isShadowed(own: []const Parameter, candidate: Parameter) bool {
    for (own) |param| {
        if (param.location == candidate.location and std.mem.eql(u8, param.name, candidate.name)) return true;
    }
    return false;
}
