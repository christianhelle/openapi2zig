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

fn refName(ref: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, ref, "/")) |slash| return ref[slash + 1 ..];
    return ref;
}

/// Add a schema reference and transitively everything it points to to the
/// keep set. References to names absent from the schemas map are ignored.
fn keepRef(allocator: std.mem.Allocator, schemas: ?*const std.StringHashMap(common.Schema), keep: *std.StringHashMap(void), ref: []const u8) anyerror!void {
    const schemas_map = schemas orelse return;
    const name = refName(ref);
    if (keep.contains(name)) return;
    if (schemas_map.getPtr(name)) |target| {
        try keep.put(name, {});
        try collectSchemaRefs(allocator, schemas, keep, target.*);
    }
}

/// Walk a schema tree and add every reachable schema name to the keep set.
fn collectSchemaRefs(allocator: std.mem.Allocator, schemas: ?*const std.StringHashMap(common.Schema), keep: *std.StringHashMap(void), schema: common.Schema) anyerror!void {
    if (schema.ref) |ref| try keepRef(allocator, schemas, keep, ref);
    if (schema.items) |items| try collectSchemaRefs(allocator, schemas, keep, items.*);
    if (schema.properties) |properties| {
        var iterator = properties.iterator();
        while (iterator.next()) |entry| {
            try collectSchemaRefs(allocator, schemas, keep, entry.value_ptr.*);
        }
    }
    if (schema.one_of_refs) |refs| for (refs) |ref| try keepRef(allocator, schemas, keep, ref);
    if (schema.any_of_refs) |refs| for (refs) |ref| try keepRef(allocator, schemas, keep, ref);
    if (schema.one_of) |variants| for (variants) |variant| try collectSchemaRefs(allocator, schemas, keep, variant);
    if (schema.any_of) |variants| for (variants) |variant| try collectSchemaRefs(allocator, schemas, keep, variant);
}

/// Add every schema name referenced by the operation to the keep set.
fn collectOperationRefs(allocator: std.mem.Allocator, schemas: ?*const std.StringHashMap(common.Schema), keep: *std.StringHashMap(void), operation: common.Operation) !void {
    if (operation.parameters) |params| {
        for (params) |param| {
            if (param.schema) |schema| try collectSchemaRefs(allocator, schemas, keep, schema);
        }
    }
    var response_iterator = operation.responses.iterator();
    while (response_iterator.next()) |entry| {
        const response = entry.value_ptr.*;
        if (response.schema) |schema| try collectSchemaRefs(allocator, schemas, keep, schema);
        if (response.headers) |headers| {
            var header_iterator = headers.iterator();
            while (header_iterator.next()) |header_entry| {
                if (header_entry.value_ptr.schema) |schema| try collectSchemaRefs(allocator, schemas, keep, schema);
            }
        }
    }
}

fn collectPathItemRefs(allocator: std.mem.Allocator, schemas: ?*const std.StringHashMap(common.Schema), keep: *std.StringHashMap(void), path_item: common.PathItem) !void {
    if (path_item.parameters) |params| {
        for (params) |param| {
            if (param.schema) |schema| try collectSchemaRefs(allocator, schemas, keep, schema);
        }
    }
    inline for (std.meta.fields(common.PathItem)) |field| {
        if (field.type != ?common.Operation) continue;
        if (@field(path_item, field.name)) |operation| {
            try collectOperationRefs(allocator, schemas, keep, operation);
        }
    }
}

/// Remove schemas from the document that are no longer referenced by the
/// remaining operations, following references transitively.
fn trimUnreferencedSchemas(allocator: std.mem.Allocator, doc: *common.UnifiedDocument) !void {
    const schemas = &(doc.schemas orelse return);

    var keep = std.StringHashMap(void).init(allocator);
    defer keep.deinit();

    var path_iterator = doc.paths.iterator();
    while (path_iterator.next()) |entry| {
        try collectPathItemRefs(allocator, schemas, &keep, entry.value_ptr.*);
    }

    var to_remove = std.ArrayList([]const u8).empty;
    defer to_remove.deinit(allocator);

    var schema_iterator = schemas.iterator();
    while (schema_iterator.next()) |entry| {
        if (!keep.contains(entry.key_ptr.*)) {
            try to_remove.append(allocator, entry.key_ptr.*);
        }
    }

    for (to_remove.items) |name| {
        if (schemas.fetchRemove(name)) |removed| {
            var kv = removed;
            allocator.free(kv.key);
            kv.value.deinit(allocator);
        }
    }
}

/// Filters the document in place so only operations carrying at least one of
/// the requested tags remain. Paths left without operations and schemas no
/// longer referenced by the kept operations are removed.
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

    try trimUnreferencedSchemas(allocator, doc);
}
