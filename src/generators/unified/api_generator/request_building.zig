const std = @import("std");
const Operation = @import("../../../models/common/document.zig").Operation;
const helpers = @import("helpers.zig");
const AuthScheme = helpers.AuthScheme;
const HeaderLocalNames = helpers.HeaderLocalNames;
const QueryPrefixInfo = helpers.QueryPrefixInfo;
const computeQueryPrefixInfo = helpers.computeQueryPrefixInfo;
const escapeZigString = helpers.escapeZigString;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

pub fn headerLocalNamesAlloc(self: *UnifiedApiGenerator, operation: Operation) std.mem.Allocator.Error!HeaderLocalNames {
    var headers = try self.allocator.dupe(u8, "operation_headers");
    errdefer self.allocator.free(headers);

    while (true) {
        const suffix = headers["operation_headers".len..];
        const values = try std.fmt.allocPrint(self.allocator, "operation_header_values{s}", .{suffix});
        defer self.allocator.free(values);

        var conflicts = false;
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (std.mem.eql(u8, parameter.name, headers) or std.mem.eql(u8, parameter.name, values)) {
                    conflicts = true;
                    break;
                }
            }
        }
        if (!conflicts) {
            return .{
                .headers = headers,
                .values = try self.allocator.dupe(u8, values),
            };
        }

        const next_headers = try std.fmt.allocPrint(self.allocator, "{s}_", .{headers});
        self.allocator.free(headers);
        headers = next_headers;
    }
}

/// Emits collision-safe local declarations required before
/// `appendHeaderParamAppends` can run.
pub fn appendHeaderLocals(self: *UnifiedApiGenerator, names: HeaderLocalNames) !void {
    try self.buffer.appendSlice(self.allocator, "    var ");
    try self.buffer.appendSlice(self.allocator, names.headers);
    try self.buffer.appendSlice(self.allocator, " = std.ArrayList(std.http.Header).empty;\n");
    try self.buffer.appendSlice(self.allocator, "    defer ");
    try self.buffer.appendSlice(self.allocator, names.headers);
    try self.buffer.appendSlice(self.allocator, ".deinit(allocator);\n");
    try self.appendHeaderValuesLocal(names);
}

/// Emits the `operation_header_values` local declaration used to own allocations
/// made while serializing header parameter values, freed once the
/// enclosing function returns.
pub fn appendHeaderValuesLocal(self: *UnifiedApiGenerator, names: HeaderLocalNames) !void {
    try self.buffer.appendSlice(self.allocator, "    var ");
    try self.buffer.appendSlice(self.allocator, names.values);
    try self.buffer.appendSlice(self.allocator, " = std.ArrayList([]u8).empty;\n");
    try self.buffer.appendSlice(self.allocator, "    defer {\n");
    try self.buffer.appendSlice(self.allocator, "        for (");
    try self.buffer.appendSlice(self.allocator, names.values);
    try self.buffer.appendSlice(self.allocator, ".items) |item| allocator.free(item);\n");
    try self.buffer.appendSlice(self.allocator, "        ");
    try self.buffer.appendSlice(self.allocator, names.values);
    try self.buffer.appendSlice(self.allocator, ".deinit(allocator);\n");
    try self.buffer.appendSlice(self.allocator, "    }\n");
}

/// Emits code that serializes every declared `in: header` parameter and
/// appends it to the in-scope `headers` ArrayList, replacing any
/// equal-named client default header. Required parameters are always
/// emitted; optional parameters are emitted only when non-null.
pub fn appendHeaderParamAppends(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, names: HeaderLocalNames) !void {
    if (operation.parameters) |parameters| {
        for (parameters, 0..) |parameter, i| {
            if (parameter.location != .header) continue;
            const escaped_name = try escapeZigString(self.allocator, parameter.name);
            defer self.allocator.free(escaped_name);
            if (parameter.required) {
                try self.buffer.appendSlice(self.allocator, "    {\n");
                try self.buffer.appendSlice(self.allocator, "        const header_value = try formatHeaderValue(allocator, ");
                try self.appendParamReference(operation, method, path, i, parameter);
                try self.buffer.appendSlice(self.allocator, ");\n");
                try self.buffer.appendSlice(self.allocator, "        errdefer allocator.free(header_value);\n");
                try self.buffer.appendSlice(self.allocator, "        try appendOrReplaceHeader(allocator, &");
                try self.buffer.appendSlice(self.allocator, names.headers);
                try self.buffer.appendSlice(self.allocator, ", \"");
                try self.buffer.appendSlice(self.allocator, escaped_name);
                try self.buffer.appendSlice(self.allocator, "\", header_value);\n");
                try self.buffer.appendSlice(self.allocator, "        try ");
                try self.buffer.appendSlice(self.allocator, names.values);
                try self.buffer.appendSlice(self.allocator, ".append(allocator, header_value);\n");
                try self.buffer.appendSlice(self.allocator, "    }\n");
            } else {
                try self.buffer.appendSlice(self.allocator, "    if (");
                try self.appendParamReference(operation, method, path, i, parameter);
                try self.buffer.appendSlice(self.allocator, ") |value| {\n");
                try self.buffer.appendSlice(self.allocator, "        const header_value = try formatHeaderValue(allocator, value);\n");
                try self.buffer.appendSlice(self.allocator, "        errdefer allocator.free(header_value);\n");
                try self.buffer.appendSlice(self.allocator, "        try appendOrReplaceHeader(allocator, &");
                try self.buffer.appendSlice(self.allocator, names.headers);
                try self.buffer.appendSlice(self.allocator, ", \"");
                try self.buffer.appendSlice(self.allocator, escaped_name);
                try self.buffer.appendSlice(self.allocator, "\", header_value);\n");
                try self.buffer.appendSlice(self.allocator, "        try ");
                try self.buffer.appendSlice(self.allocator, names.values);
                try self.buffer.appendSlice(self.allocator, ".append(allocator, header_value);\n");
                try self.buffer.appendSlice(self.allocator, "    }\n");
            }
        }
    }
}

pub fn appendAuthHeader(self: *UnifiedApiGenerator, scheme: ?AuthScheme, names: HeaderLocalNames) !void {
    if (scheme) |s| {
        switch (s) {
            .bearer => {
                try self.buffer.appendSlice(self.allocator, "    var auth_header: ?[]u8 = null;\n");
                try self.buffer.appendSlice(self.allocator, "    defer if (auth_header) |value| allocator.free(value);\n");
                try self.buffer.appendSlice(self.allocator, "    if (client.api_key.len > 0) {\n");
                try self.buffer.appendSlice(self.allocator, "        auth_header = try std.fmt.allocPrint(allocator, \"Bearer {s}\", .{client.api_key});\n");
                try self.buffer.appendSlice(self.allocator, "        try ");
                try self.buffer.appendSlice(self.allocator, names.headers);
                try self.buffer.appendSlice(self.allocator, ".append(allocator, .{ .name = \"Authorization\", .value = auth_header.? });\n");
                try self.buffer.appendSlice(self.allocator, "    }\n");
            },
            .api_key_header => |name| {
                const escaped = try escapeZigString(self.allocator, name);
                defer self.allocator.free(escaped);
                const code = try std.fmt.allocPrint(self.allocator, "    if (client.api_key.len > 0) {{\n        try {s}.append(allocator, .{{ .name = \"{s}\", .value = client.api_key }});\n    }}\n", .{ names.headers, escaped });
                defer self.allocator.free(code);
                try self.buffer.appendSlice(self.allocator, code);
            },
        }
    }
}

pub fn appendUrlConstruction(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
    var new_path = path;
    var allocated_paths = std.ArrayList([]u8).empty;
    defer {
        for (allocated_paths.items) |allocated_path| self.allocator.free(allocated_path);
        allocated_paths.deinit(self.allocator);
    }

    if (operation.parameters) |parameters| {
        for (parameters) |parameter| {
            if (parameter.location != .path) continue;
            const param = parameter.name;
            const path_type = if (parameter.schema) |schema|
                schema.type orelse .string
            else
                parameter.type orelse .string;
            const param_type = switch (path_type) {
                .string => "s",
                .integer => "d",
                .number => "d",
                else => "any",
            };
            // Substitute the braced placeholder rather than the bare name: a
            // parameter such as `repo` also occurs inside literal segments like
            // `/repos/`, which replacing the bare name would rewrite as well.
            const placeholder = try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{param});
            defer self.allocator.free(placeholder);
            const replacement = try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{param_type});
            defer self.allocator.free(replacement);

            const size = std.mem.replacementSize(u8, new_path, placeholder, replacement);
            const output = blk: {
                const out = try self.allocator.alloc(u8, size);
                errdefer self.allocator.free(out);
                try allocated_paths.append(self.allocator, out);
                break :blk out;
            };
            _ = std.mem.replace(u8, new_path, placeholder, replacement, output);
            new_path = output;
        }
    }

    var has_query_param = false;
    if (operation.parameters) |parameters| {
        for (parameters) |parameter| {
            if (parameter.location == .query) {
                has_query_param = true;
                break;
            }
        }
    }
    const query_info = if (has_query_param) computeQueryPrefixInfo(new_path) else QueryPrefixInfo{ .head = new_path, .fragment = "", .first_query_init = true };
    const escaped_query_head = try escapeZigString(self.allocator, query_info.head);
    defer self.allocator.free(escaped_query_head);

    try self.buffer.appendSlice(self.allocator, "    var uri_buf: std.Io.Writer.Allocating = .init(allocator);\n");
    try self.buffer.appendSlice(self.allocator, "    defer uri_buf.deinit();\n");
    try self.buffer.appendSlice(self.allocator, "    try uri_buf.writer.print(\"{s}");
    try self.buffer.appendSlice(self.allocator, escaped_query_head);
    try self.buffer.appendSlice(self.allocator, "\", .{");
    const has_path_param = blk: {
        if (operation.parameters) |params| {
            for (params) |p| if (p.location == .path) break :blk true;
        }
        break :blk false;
    };
    if (has_path_param) try self.buffer.appendSlice(self.allocator, " ");
    try self.buffer.appendSlice(self.allocator, "client.base_url");
    if (operation.parameters) |parameters| {
        for (parameters, 0..) |parameter, i| {
            if (parameter.location != .path) continue;
            try self.buffer.appendSlice(self.allocator, ", ");
            try self.appendParamReference(operation, method, path, i, parameter);
        }
    }
    if (has_path_param) try self.buffer.appendSlice(self.allocator, " ");
    try self.buffer.appendSlice(self.allocator, "});\n");

    if (has_query_param) {
        const first_query_literal: []const u8 = if (query_info.first_query_init) "true" else "false";
        try self.buffer.appendSlice(self.allocator, "    var first_query = ");
        try self.buffer.appendSlice(self.allocator, first_query_literal);
        try self.buffer.appendSlice(self.allocator, ";\n");
        if (operation.parameters) |parameters| {
            for (parameters, 0..) |parameter, i| {
                if (parameter.location != .query) continue;
                if (parameter.required) {
                    try self.buffer.appendSlice(self.allocator, "    try appendQueryParam(&uri_buf.writer, &first_query, \"");
                    try self.buffer.appendSlice(self.allocator, parameter.name);
                    try self.buffer.appendSlice(self.allocator, "\", ");
                    try self.appendParamReference(operation, method, path, i, parameter);
                    try self.buffer.appendSlice(self.allocator, ");\n");
                } else {
                    try self.buffer.appendSlice(self.allocator, "    if (");
                    try self.appendParamReference(operation, method, path, i, parameter);
                    try self.buffer.appendSlice(self.allocator, ") |value| {\n");
                    try self.buffer.appendSlice(self.allocator, "        try appendQueryParam(&uri_buf.writer, &first_query, \"");
                    try self.buffer.appendSlice(self.allocator, parameter.name);
                    try self.buffer.appendSlice(self.allocator, "\", value);\n");
                    try self.buffer.appendSlice(self.allocator, "    }\n");
                }
            }
        }
        if (query_info.fragment.len > 0) {
            const escaped_fragment = try escapeZigString(self.allocator, query_info.fragment);
            defer self.allocator.free(escaped_fragment);
            try self.buffer.appendSlice(self.allocator, "    try uri_buf.writer.writeAll(\"");
            try self.buffer.appendSlice(self.allocator, escaped_fragment);
            try self.buffer.appendSlice(self.allocator, "\");\n");
        }
    }
}

pub fn hasBodyParameter(self: *UnifiedApiGenerator, operation: Operation) bool {
    _ = self;
    if (operation.parameters) |params| {
        for (params) |param| {
            if (param.location == .body) return true;
        }
    }
    return false;
}
