const std = @import("std");
const document = @import("../../../models/common/document.zig");
const Operation = document.Operation;
const Schema = document.Schema;
const UnifiedDocument = document.UnifiedDocument;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

/// Emits `ApiError`, the model most error responses of the API use, and
/// `parseApiError` to decode an error response body into it. Without a
/// referenced error model, `ApiError` is a plain JSON value, so code written
/// against these names always compiles.
pub fn generateTypedErrors(self: *UnifiedApiGenerator, doc: UnifiedDocument) !void {
    if (!self.args.typed_errors) return;

    // Name of the type that `parseApiError` returns, as written in the client.
    var target: std.ArrayList(u8) = .empty;
    defer target.deinit(self.allocator);
    var alias_name_free = true;

    if (try mostCommonErrorSchema(self, doc)) |error_schema| {
        // Render the type once to see what it is called.
        const start = self.buffer.items.len;
        try self.appendZigTypeFromSchema(error_schema);
        try target.appendSlice(self.allocator, self.buffer.items[start..]);
        self.buffer.shrinkRetainingCapacity(start);
        // A model that is already called ApiError needs no alias, and one that
        // takes the name for another model blocks it.
        alias_name_free = !self.isInlinedModelName("ApiError");
        if (std.mem.eql(u8, target.items, "ApiError") or std.mem.endsWith(u8, target.items, ".ApiError")) alias_name_free = false;
    } else {
        try target.appendSlice(self.allocator, "std.json.Value");
    }

    if (alias_name_free) {
        try self.buffer.appendSlice(self.allocator, "/// The error body most error responses of this API use.\npub const ApiError = ");
        try self.buffer.appendSlice(self.allocator, target.items);
        try self.buffer.appendSlice(self.allocator, ";\n\n");
    }
    const result_type = if (alias_name_free) "ApiError" else target.items;
    try self.buffer.appendSlice(self.allocator, "/// Decodes the body of an error response. The result owns its memory.\npub fn parseApiError(allocator: std.mem.Allocator, raw: RawResponse) !std.json.Parsed(");
    try self.buffer.appendSlice(self.allocator, result_type);
    try self.buffer.appendSlice(self.allocator, ") {\n    return std.json.parseFromSlice(");
    try self.buffer.appendSlice(self.allocator, result_type);
    try self.buffer.appendSlice(self.allocator, ", allocator, raw.body, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });\n}\n\n");
}

fn mostCommonErrorSchema(self: *UnifiedApiGenerator, doc: UnifiedDocument) !?Schema {
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    defer counts.deinit(self.allocator);
    var schemas: std.StringHashMapUnmanaged(Schema) = .empty;
    defer schemas.deinit(self.allocator);

    var path_iterator = doc.paths.iterator();
    while (path_iterator.next()) |entry| {
        const item = entry.value_ptr.*;
        const operations = [_]?Operation{ item.get, item.post, item.put, item.delete, item.patch, item.head, item.options };
        for (operations) |maybe_operation| {
            const operation = maybe_operation orelse continue;
            var response_iterator = operation.responses.iterator();
            while (response_iterator.next()) |response_entry| {
                const code = response_entry.key_ptr.*;
                if (!isErrorCode(code)) continue;
                const schema = response_entry.value_ptr.schema orelse continue;
                const ref = schema.ref orelse continue;
                const name = if (std.mem.lastIndexOfScalar(u8, ref, '/')) |slash| ref[slash + 1 ..] else ref;
                const gop = try counts.getOrPut(self.allocator, name);
                gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
                try schemas.put(self.allocator, name, schema);
            }
        }
    }

    // The highest count wins; ties go to the smaller name so output is stable.
    var best_name: ?[]const u8 = null;
    var best_count: usize = 0;
    var count_iterator = counts.iterator();
    while (count_iterator.next()) |entry| {
        const better = entry.value_ptr.* > best_count or
            (entry.value_ptr.* == best_count and best_name != null and std.mem.lessThan(u8, entry.key_ptr.*, best_name.?));
        if (better) {
            best_name = entry.key_ptr.*;
            best_count = entry.value_ptr.*;
        }
    }
    const name = best_name orelse return null;
    return schemas.get(name);
}

fn isErrorCode(code: []const u8) bool {
    if (std.mem.eql(u8, code, "default")) return true;
    return code.len > 0 and (code[0] == '4' or code[0] == '5');
}
