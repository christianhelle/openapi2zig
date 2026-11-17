const std = @import("std");
const document = @import("../../../models/common/document.zig");
const Operation = document.Operation;
const Schema = document.Schema;
const UnifiedDocument = document.UnifiedDocument;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

/// Emits `ApiError`, the model most error responses of the API use, and
/// `parseApiError` to decode an error response body into it. Only emitted when
/// typed errors are requested and the description declares an error model.
pub fn generateTypedErrors(self: *UnifiedApiGenerator, doc: UnifiedDocument) !void {
    if (!self.args.typed_errors) return;
    const error_schema = (try mostCommonErrorSchema(self, doc)) orelse return;

    try self.buffer.appendSlice(self.allocator, "/// The error body most error responses of this API use.\npub const ApiError = ");
    try self.appendZigTypeFromSchema(error_schema);
    try self.buffer.appendSlice(self.allocator,
        \\;
        \\
        \\/// Decodes the body of an error response. The result owns its memory.
        \\pub fn parseApiError(allocator: std.mem.Allocator, raw: RawResponse) !std.json.Parsed(ApiError) {
        \\    return std.json.parseFromSlice(ApiError, allocator, raw.body, .{ .ignore_unknown_fields = true });
        \\}
        \\
        \\
    );
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
