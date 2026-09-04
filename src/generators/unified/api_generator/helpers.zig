const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const SecurityScheme = @import("../../../models/common/document.zig").SecurityScheme;
const Operation = @import("../../../models/common/document.zig").Operation;
const Parameter = @import("../../../models/common/document.zig").Parameter;
const media_type = @import("../../../media_type.zig");

pub const BodyKind = enum { none, json, binary, text, form };
pub const AuthScheme = union(enum) {
    bearer,
    api_key_header: []const u8,
};

pub const HeaderLocalNames = struct {
    headers: []const u8,
    values: []const u8,

    pub fn deinit(self: HeaderLocalNames, allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.values);
    }
};

pub fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

pub fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

pub fn escapeZigString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    for (input) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
    return try buf.toOwnedSlice(allocator);
}

pub fn classifyBody(content_type: ?[]const u8) BodyKind {
    const raw = content_type orelse return .json;
    const ct = media_type.baseMediaType(raw);
    if (ct.len == 0) return .json;
    if (std.ascii.eqlIgnoreCase(ct, "application/json")) return .json;
    if (endsWithIgnoreCase(ct, "+json")) return .json;
    if (std.ascii.eqlIgnoreCase(ct, "application/x-www-form-urlencoded")) return .form;
    if (startsWithIgnoreCase(ct, "multipart/")) return .form;
    if (startsWithIgnoreCase(ct, "text/")) return .text;
    if (std.ascii.eqlIgnoreCase(ct, "application/octet-stream")) return .binary;
    if (startsWithIgnoreCase(ct, "image/")) return .binary;
    if (startsWithIgnoreCase(ct, "audio/")) return .binary;
    if (startsWithIgnoreCase(ct, "video/")) return .binary;
    if (std.ascii.eqlIgnoreCase(ct, "*/*")) return .binary;
    if (startsWithIgnoreCase(ct, "application/")) return .binary;
    return .binary;
}

pub fn findBodyParam(operation: Operation) ?Parameter {
    if (operation.parameters) |params| {
        for (params) |p| {
            if (p.location == .body) return p;
        }
    }
    return null;
}

pub fn bodyKindFor(operation: Operation) BodyKind {
    const param = findBodyParam(operation) orelse return .none;
    return classifyBody(param.content_type);
}

pub fn hasHeaderParams(operation: Operation) bool {
    if (operation.parameters) |params| {
        for (params) |p| {
            if (p.location == .header) return true;
        }
    }
    return false;
}

pub const QueryPrefixInfo = struct {
    /// Static path text to print before any dynamically-appended query
    /// parameters. Excludes a trailing fragment (if any) and a single
    /// trailing '?'/'&' separator, both of which are handled separately.
    head: []const u8,
    /// Static path fragment (starting with '#'), or an empty slice when the
    /// path has no fragment. Printed after dynamically-appended query
    /// parameters so they remain part of the query component of the URI.
    fragment: []const u8,
    /// Initial value for the generated `first_query` separator variable.
    first_query_init: bool,
};

/// Determines how dynamically-appended query parameters should be spliced
/// into a path template that may already contain a fixed query string
/// (e.g. "/run?beta=true"), a trailing separator (e.g. "/run?" or "/run&"),
/// and/or a fragment (e.g. "/run#section"). Operations without a fixed query
/// component are unaffected: `head` equals `path`, `fragment` is empty, and
/// `first_query_init` is `true`, matching prior behavior exactly.
pub fn computeQueryPrefixInfo(path: []const u8) QueryPrefixInfo {
    const fragment_start = std.mem.indexOfScalar(u8, path, '#');
    const before_fragment = if (fragment_start) |idx| path[0..idx] else path;
    const fragment = if (fragment_start) |idx| path[idx..] else "";

    var head = before_fragment;
    if (head.len > 0 and (head[head.len - 1] == '?' or head[head.len - 1] == '&')) {
        head = head[0 .. head.len - 1];
    }
    const first_query_init = std.mem.indexOfScalar(u8, head, '?') == null;
    return .{ .head = head, .fragment = fragment, .first_query_init = first_query_init };
}

pub const OperationRef = struct {
    path: []const u8,
    method: []const u8,
    operation: Operation,
};

pub fn documentHasStreamingOperations(document: UnifiedDocument) bool {
    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        if (entry.value_ptr.post) |operation| {
            if (operation.streaming) return true;
        }
    }
    return false;
}

pub fn authSchemeFor(document: UnifiedDocument) AuthScheme {
    const schemes = document.security_schemes orelse return .bearer;

    // 1. Check operation-level security requirements
    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |path_entry| {
        const path_item = path_entry.value_ptr.*;
        const ops = [_]?Operation{
            path_item.get,
            path_item.put,
            path_item.post,
            path_item.delete,
            path_item.options,
            path_item.head,
            path_item.patch,
        };
        for (ops) |maybe_op| {
            if (maybe_op) |op| {
                if (op.security) |sec_reqs| {
                    for (sec_reqs) |sec_req| {
                        var req_iterator = sec_req.schemes.iterator();
                        while (req_iterator.next()) |scheme_entry| {
                            if (schemes.get(scheme_entry.key_ptr.*)) |s| {
                                return switch (s) {
                                    .bearer => .bearer,
                                    .api_key_header => |scheme| .{ .api_key_header = scheme.name },
                                };
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Check document-level security requirements
    if (document.security) |sec_reqs| {
        for (sec_reqs) |sec_req| {
            var req_iterator = sec_req.schemes.iterator();
            while (req_iterator.next()) |scheme_entry| {
                if (schemes.get(scheme_entry.key_ptr.*)) |s| {
                    return switch (s) {
                        .bearer => .bearer,
                        .api_key_header => |scheme| .{ .api_key_header = scheme.name },
                    };
                }
            }
        }
    }

    // 3. Fall back deterministically across document.security_schemes (alphabetical key order)
    var min_key: ?[]const u8 = null;
    var min_scheme: ?SecurityScheme = null;
    var iterator = schemes.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        if (min_key == null or std.mem.order(u8, key, min_key.?) == .lt) {
            min_key = key;
            min_scheme = entry.value_ptr.*;
        }
    }
    if (min_scheme) |s| {
        return switch (s) {
            .bearer => .bearer,
            .api_key_header => |scheme| .{ .api_key_header = scheme.name },
        };
    }

    return .bearer;
}

pub fn authSchemeForOperation(document: UnifiedDocument, operation: Operation) ?AuthScheme {
    const schemes = document.security_schemes orelse return .bearer;

    // 1. Operation-level security
    if (operation.security) |sec_reqs| {
        if (sec_reqs.len == 0) return null;
        for (sec_reqs) |sec_req| {
            if (sec_req.schemes.count() == 0) return null;
        }
        for (sec_reqs) |sec_req| {
            var min_key: ?[]const u8 = null;
            var min_scheme: ?SecurityScheme = null;
            var it = sec_req.schemes.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (schemes.get(key)) |scheme| {
                    if (min_key == null or std.mem.order(u8, key, min_key.?) == .lt) {
                        min_key = key;
                        min_scheme = scheme;
                    }
                }
            }
            if (min_scheme) |s| {
                return switch (s) {
                    .bearer => .bearer,
                    .api_key_header => |ah| .{ .api_key_header = ah.name },
                };
            }
        }
        return null;
    }

    // 2. Document-level security
    if (document.security) |sec_reqs| {
        if (sec_reqs.len == 0) return null;
        for (sec_reqs) |sec_req| {
            if (sec_req.schemes.count() == 0) return null;
        }
        for (sec_reqs) |sec_req| {
            var min_key: ?[]const u8 = null;
            var min_scheme: ?SecurityScheme = null;
            var it = sec_req.schemes.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (schemes.get(key)) |scheme| {
                    if (min_key == null or std.mem.order(u8, key, min_key.?) == .lt) {
                        min_key = key;
                        min_scheme = scheme;
                    }
                }
            }
            if (min_scheme) |s| {
                return switch (s) {
                    .bearer => .bearer,
                    .api_key_header => |ah| .{ .api_key_header = ah.name },
                };
            }
        }
        return null;
    }

    // 3. Fall back deterministically (alphabetical)
    var min_key: ?[]const u8 = null;
    var min_scheme: ?SecurityScheme = null;
    var it = schemes.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (min_key == null or std.mem.order(u8, key, min_key.?) == .lt) {
            min_key = key;
            min_scheme = entry.value_ptr.*;
        }
    }
    if (min_scheme) |s| {
        return switch (s) {
            .bearer => .bearer,
            .api_key_header => |ah| .{ .api_key_header = ah.name },
        };
    }

    return .bearer;
}

pub const ResourceWrapper = struct {
    segments: [][]const u8,
    method_name: []const u8,
    operation_id: []const u8,
    method: []const u8,
    path: []const u8,
    operation: Operation,
    collides: bool = false,
    needs_alias: bool = false,
};

pub const TagClient = struct {
    name: []const u8,
    methods: std.ArrayList(OperationRef),
};

/// Gather every operation in the document as a path/method pair. Callers that
/// need a stable order sort the result with `operationRefLessThan`, since the
/// path map iterates in hash order.
pub fn collectOperationRefs(out: *std.ArrayList(OperationRef), allocator: std.mem.Allocator, document: UnifiedDocument) !void {
    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        const path = entry.key_ptr.*;
        const path_item = entry.value_ptr.*;
        if (path_item.get) |op| try out.append(allocator, .{ .path = path, .method = "GET", .operation = op });
        if (path_item.post) |op| try out.append(allocator, .{ .path = path, .method = "POST", .operation = op });
        if (path_item.put) |op| try out.append(allocator, .{ .path = path, .method = "PUT", .operation = op });
        if (path_item.delete) |op| try out.append(allocator, .{ .path = path, .method = "DELETE", .operation = op });
        if (path_item.patch) |op| try out.append(allocator, .{ .path = path, .method = "PATCH", .operation = op });
        if (path_item.head) |op| try out.append(allocator, .{ .path = path, .method = "HEAD", .operation = op });
        if (path_item.options) |op| try out.append(allocator, .{ .path = path, .method = "OPTIONS", .operation = op });
    }
}

pub fn operationRefLessThan(_: void, lhs: OperationRef, rhs: OperationRef) bool {
    const path_order = std.mem.order(u8, lhs.path, rhs.path);
    if (path_order != .eq) return path_order == .lt;
    return std.mem.order(u8, lhs.method, rhs.method) == .lt;
}

pub fn tagClientLessThan(_: void, lhs: TagClient, rhs: TagClient) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

pub fn toPascalCaseAlloc(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var capitalize_next = true;
    for (value) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (capitalize_next) {
                try out.append(allocator, std.ascii.toUpper(c));
                capitalize_next = false;
            } else {
                try out.append(allocator, c);
            }
        } else {
            capitalize_next = true;
        }
    }
    if (out.items.len == 0 or !std.ascii.isAlphabetic(out.items[0])) try out.insert(allocator, 0, '_');
    return try out.toOwnedSlice(allocator);
}

pub fn resourceWrapperLessThan(_: void, lhs: ResourceWrapper, rhs: ResourceWrapper) bool {
    const segment_order = stringListOrder(lhs.segments, rhs.segments);
    if (segment_order != .eq) return segment_order == .lt;
    const method_order = std.mem.order(u8, lhs.method_name, rhs.method_name);
    if (method_order != .eq) return method_order == .lt;
    return std.mem.order(u8, lhs.operation_id, rhs.operation_id) == .lt;
}

pub fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub fn stringListOrder(lhs: []const []const u8, rhs: []const []const u8) std.math.Order {
    const len = @min(lhs.len, rhs.len);
    for (lhs[0..len], rhs[0..len]) |lhs_item, rhs_item| {
        const order = std.mem.order(u8, lhs_item, rhs_item);
        if (order != .eq) return order;
    }
    return std.math.order(lhs.len, rhs.len);
}

pub fn sameStringList(lhs: []const []const u8, rhs: []const []const u8) bool {
    return stringListOrder(lhs, rhs) == .eq;
}

pub fn containsString(values: []const []const u8, value: []const u8) bool {
    for (values) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}

pub fn isVersionSegment(segment: []const u8) bool {
    if (segment.len < 2 or segment[0] != 'v') return false;
    for (segment[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

pub fn isPathParam(segment: []const u8) bool {
    return segment.len >= 2 and segment[0] == '{' and segment[segment.len - 1] == '}';
}
