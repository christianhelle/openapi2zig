const std = @import("std");
const Operation = @import("../../../models/common/document.zig").Operation;
const Document = @import("../../../models/common/document.zig").UnifiedDocument;
const Generator = @import("../api_generator.zig").UnifiedApiGenerator;
const helpers = @import("helpers.zig");

pub fn hasParameters(operation: Operation) bool {
    if (operation.parameters) |parameters| {
        for (parameters) |parameter| if (parameter.location != .body) return true;
    }
    return false;
}

/// Streaming keeps an anytype body so callers can use partial request structs.
/// Non-body parameters follow the same contract as ordinary operations.
pub fn appendParameters(self: *Generator, operation: Operation, path: []const u8) !void {
    if (hasParameters(operation)) {
        if (self.args.parameters_as_struct) {
            try self.appendOptionsParam(operation, "POST", path);
        } else if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location == .body) continue;
                try self.buffer.appendSlice(self.allocator, ", ");
                try self.appendFlatParamIdentifier(parameter.name);
                try self.buffer.appendSlice(self.allocator, ": ");
                if ((parameter.location == .header or parameter.location == .query) and !parameter.required) try self.buffer.appendSlice(self.allocator, "?");
                try self.appendParamBaseType(parameter);
            }
        }
    }
    try self.buffer.appendSlice(self.allocator, ", requestBody: anytype");
}

pub fn appendCall(self: *Generator, operation: Operation, receiver: []const u8, typed: bool) !void {
    try self.buffer.appendSlice(self.allocator, if (typed) "(Event, " else "(");
    try self.buffer.appendSlice(self.allocator, receiver);
    if (hasParameters(operation)) {
        if (self.args.parameters_as_struct) {
            try self.buffer.appendSlice(self.allocator, ", options");
        } else if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location == .body) continue;
                try self.buffer.appendSlice(self.allocator, ", ");
                try self.appendFlatParamIdentifier(parameter.name);
            }
        }
    }
    try self.buffer.appendSlice(self.allocator, ", requestBody, callback, cancellation_token)");
}

pub fn generateFunction(self: *Generator, name: []const u8, path: []const u8, operation: Operation, document: Document) !void {
    for ([_]bool{ false, true }) |typed| {
        const function_name = if (typed) try std.fmt.allocPrint(self.allocator, "{s}Events", .{name}) else try self.allocator.dupe(u8, name);
        defer self.allocator.free(function_name);
        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.appendIdentifier(function_name);
        try self.buffer.appendSlice(self.allocator, if (typed) "(comptime Event: type, client: *Client" else "(client: *Client");
        try appendParameters(self, operation, path);
        try self.buffer.appendSlice(self.allocator, ", callback: anytype, cancellation_token: ?*CancellationToken) !void {\n    const allocator = client.allocator;\n");
        try self.appendUnusedParameters(operation, "POST", path);
        try self.appendUrlConstruction("POST", path, operation);
        const names = try self.headerLocalNamesAlloc(operation);
        defer names.deinit(self.allocator);
        try self.appendHeaderLocals(names);
        try self.appendAuthHeader(helpers.authSchemeForOperation(document, operation), names);
        try self.appendHeaderParamAppends(operation, "POST", path, names);
        try self.buffer.appendSlice(self.allocator, if (typed) "    return streamJsonTypedWithExtraHeaders(Event, client, " else "    return streamJsonWithExtraHeaders(client, ");
        // appendUrlConstruction starts with client.base_url. The shared stream
        // transport expects a relative path and adds that same base exactly once.
        try self.buffer.appendSlice(self.allocator, "uri_buf.written()[client.base_url.len..], requestBody, callback, cancellation_token, ");
        try self.buffer.appendSlice(self.allocator, names.headers);
        try self.buffer.appendSlice(self.allocator, ".items);\n}\n\n");
    }
}
