const std = @import("std");
const common = @import("models/common/document.zig");

/// Returns true when the operation carries at least one of the requested tags.
fn operationMatchesAnyTag(operation: common.Operation, include_tags: []const []const u8) bool {
    const tags = operation.tags orelse return false;
    for (tags) |op_tag| {
        for (include_tags) |wanted| {
            if (std.mem.eql(u8, op_tag, wanted)) return true;
        }
    }
    return false;
}

/// Deinitialize and null out every operation on the path item that does not
/// carry at least one of the requested tags.
fn removeNonMatchingOperations(allocator: std.mem.Allocator, path_item: *common.PathItem, include_tags: []const []const u8) void {
    inline for (std.meta.fields(common.PathItem)) |field| {
        if (field.type != ?common.Operation) continue;
        const op_ptr = &@field(path_item, field.name);
        if (op_ptr.*) |*op| {
            if (!operationMatchesAnyTag(op.*, include_tags)) {
                op.deinit(allocator);
                op_ptr.* = null;
            }
        }
    }
}

fn pathItemHasOperations(path_item: common.PathItem) bool {
    inline for (std.meta.fields(common.PathItem)) |field| {
        if (field.type != ?common.Operation) continue;
        if (@field(path_item, field.name) != null) return true;
    }
    return false;
}

/// Filters the document in place so only operations carrying at least one of
/// the requested tags remain. Paths left without operations are removed.
/// When include_tags is empty the document is left untouched.
pub fn filterByTags(allocator: std.mem.Allocator, doc: *common.UnifiedDocument, include_tags: []const []const u8) !void {
    if (include_tags.len == 0) return;

    var paths_to_remove = std.ArrayList([]const u8).empty;
    defer paths_to_remove.deinit(allocator);

    var path_iterator = doc.paths.iterator();
    while (path_iterator.next()) |entry| {
        removeNonMatchingOperations(allocator, entry.value_ptr, include_tags);
        if (!pathItemHasOperations(entry.value_ptr.*)) {
            try paths_to_remove.append(allocator, entry.key_ptr.*);
        }
    }

    for (paths_to_remove.items) |path| {
        if (doc.paths.fetchRemove(path)) |removed| {
            var kv = removed;
            allocator.free(kv.key);
            kv.value.deinit(allocator);
        }
    }
}
