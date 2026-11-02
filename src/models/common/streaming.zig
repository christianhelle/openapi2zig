const std = @import("std");
const common = @import("document.zig");

/// Some specifications describe only the non-streaming response. A boolean
/// stream switch in a POST body also advertises the streaming request mode.
/// Existing explicit SSE response detection remains authoritative.
pub fn detectRequestStreaming(paths: std.StringHashMap(common.PathItem), schemas: ?std.StringHashMap(common.Schema)) void {
    var iterator = paths.valueIterator();
    while (iterator.next()) |item| {
        const operation = if (item.post) |*post| post else continue;
        if (operation.streaming) continue;
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location != .body) continue;
                if (parameter.schema) |schema| {
                    if (hasStreamSwitch(schema, schemas, 0)) operation.streaming = true;
                }
            }
        }
    }
}

fn hasStreamSwitch(schema: common.Schema, schemas: ?std.StringHashMap(common.Schema), depth: usize) bool {
    if (depth >= 64) return false;
    if (schema.ref) |ref| {
        if (!std.mem.startsWith(u8, ref, "#/")) return false;
        const name = ref[(std.mem.lastIndexOfScalar(u8, ref, '/') orelse return false) + 1 ..];
        return hasStreamSwitch((schemas orelse return false).get(name) orelse return false, schemas, depth + 1);
    }
    if (schema.properties) |properties| {
        if (properties.get("stream")) |field| return isBoolean(field, schemas, depth + 1);
    }
    if (schema.one_of orelse schema.any_of) |variants| {
        for (variants) |variant| if (hasStreamSwitch(variant, schemas, depth + 1)) return true;
    }
    return false;
}

fn isBoolean(schema: common.Schema, schemas: ?std.StringHashMap(common.Schema), depth: usize) bool {
    if (depth >= 64) return false;
    if (schema.type == .boolean) return true;
    if (schema.ref) |ref| {
        if (!std.mem.startsWith(u8, ref, "#/")) return false;
        const name = ref[(std.mem.lastIndexOfScalar(u8, ref, '/') orelse return false) + 1 ..];
        return isBoolean((schemas orelse return false).get(name) orelse return false, schemas, depth + 1);
    }
    if (schema.one_of orelse schema.any_of) |variants| {
        for (variants) |variant| if (isBoolean(variant, schemas, depth + 1)) return true;
    }
    return false;
}
