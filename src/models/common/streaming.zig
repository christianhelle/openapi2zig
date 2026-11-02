const std = @import("std");
const common = @import("document.zig");

/// Some specifications describe only the non-streaming response. A boolean
/// stream switch in a POST body also advertises the streaming request mode.
/// Existing explicit SSE response detection remains authoritative.
pub fn detectRequestStreaming(allocator: std.mem.Allocator, paths: std.StringHashMap(common.PathItem), schemas: ?std.StringHashMap(common.Schema)) !void {
    var iterator = paths.valueIterator();
    while (iterator.next()) |item| {
        const operation = if (item.post) |*post| post else continue;
        if (operation.streaming) continue;
        if (operation.parameters) |parameters| {
            for (parameters) |*parameter| {
                if (parameter.location != .body) continue;
                if (parameter.schema) |*schema| {
                    if (try hasStreamSwitch(allocator, schema, schemas)) {
                        operation.streaming = true;
                        break;
                    }
                }
            }
        }
    }
}

const Query = enum { body, boolean };
const Node = struct { schema: *const common.Schema, query: Query };

fn enqueue(allocator: std.mem.Allocator, pending: *std.ArrayList(Node), visited: *std.AutoHashMap(Node, void), node: Node) !void {
    if ((try visited.getOrPut(node)).found_existing) return;
    try pending.append(allocator, node);
}

fn permitsTrue(schema: common.Schema) bool {
    if (schema.enum_values) |values| {
        for (values) |value| {
            if (value == .bool and value.bool) return true;
        }
        return false;
    }
    return true;
}

fn hasStreamSwitch(allocator: std.mem.Allocator, root: *const common.Schema, schemas: ?std.StringHashMap(common.Schema)) !bool {
    var pending: std.ArrayList(Node) = .empty;
    defer pending.deinit(allocator);
    var visited = std.AutoHashMap(Node, void).init(allocator);
    defer visited.deinit();
    try enqueue(allocator, &pending, &visited, .{ .schema = root, .query = .body });

    // Each (schema, query) is expanded at most once per root. This is graph
    // reachability, not schema satisfiability: composition branches advertise
    // possible request shapes. Never cache a negative result from a cycle for
    // another root, and never impose a depth limit on acyclic component refs.
    while (pending.pop()) |node| {
        const schema = node.schema;
        if (node.query == .boolean) {
            if (!permitsTrue(schema.*)) continue;
            if (schema.type == .boolean) return true;
        } else if (schema.properties) |properties| {
            if (properties.getPtr("stream")) |field| {
                try enqueue(allocator, &pending, &visited, .{ .schema = field, .query = .boolean });
            }
        }
        if (schema.ref) |ref| {
            const prefix = if (std.mem.startsWith(u8, ref, "#/components/schemas/"))
                "#/components/schemas/"
            else if (std.mem.startsWith(u8, ref, "#/definitions/"))
                "#/definitions/"
            else
                "";
            if (prefix.len > 0) {
                if (schemas) |map| {
                    if (map.getPtr(ref[prefix.len..])) |target| {
                        try enqueue(allocator, &pending, &visited, .{ .schema = target, .query = node.query });
                    }
                }
            }
        }
        if (schema.one_of) |variants| {
            for (variants) |*variant| try enqueue(allocator, &pending, &visited, .{ .schema = variant, .query = node.query });
        }
        if (schema.any_of) |variants| {
            for (variants) |*variant| try enqueue(allocator, &pending, &visited, .{ .schema = variant, .query = node.query });
        }
    }
    return false;
}
