const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../../models/common/document.zig").Operation;
const Schema = @import("../../../models/common/document.zig").Schema;
const SchemaType = @import("../../../models/common/document.zig").SchemaType;
const PathItem = @import("../../../models/common/document.zig").PathItem;
const helpers = @import("helpers.zig");
const QueryPrefixInfo = helpers.QueryPrefixInfo;
const computeQueryPrefixInfo = helpers.computeQueryPrefixInfo;
const escapeZigString = helpers.escapeZigString;
const bodyKindFor = helpers.bodyKindFor;
const findBodyParam = helpers.findBodyParam;
const hasHeaderParams = helpers.hasHeaderParams;
const authSchemeForOperation = helpers.authSchemeForOperation;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

pub fn generateApiClient(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        const path = entry.key_ptr.*;
        const path_item = entry.value_ptr.*;
        try self.generateOperations(path, path_item, document);
    }
}

pub fn generateOperations(self: *UnifiedApiGenerator, path: []const u8, path_item: @import("../../../models/common/document.zig").PathItem, document: UnifiedDocument) !void {
    if (path_item.get) |op| try self.generateOperation("GET", path, op, document);
    if (path_item.post) |op| try self.generateOperation("POST", path, op, document);
    if (path_item.put) |op| try self.generateOperation("PUT", path, op, document);
    if (path_item.delete) |op| try self.generateOperation("DELETE", path, op, document);
    if (path_item.patch) |op| try self.generateOperation("PATCH", path, op, document);
    if (path_item.head) |op| try self.generateOperation("HEAD", path, op, document);
    if (path_item.options) |op| try self.generateOperation("OPTIONS", path, op, document);
}

pub fn generateOperation(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation, document: UnifiedDocument) !void {
    try self.generateComments(operation);
    try self.generateOptionsType(operation, method, path, document);
    try self.generateFunctionSignature(method, path, operation);
    try self.generateFunctionBody(method, path, operation);
    if (operation.operationId != null) {
        try self.generateFunctionRaw(method, path, operation, document);
    }
    if (operation.operationId != null and self.hasReturnValue(method, operation)) {
        try self.generateFunctionResult(method, path, operation);
    }

    if (operation.streaming and std.mem.eql(u8, method, "POST")) {
        if (operation.operationId) |op_id| {
            const stream_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{op_id});
            defer self.allocator.free(stream_name);
            try self.generateStreamFunction(stream_name, path, operation, document);
        }
    }
}

pub fn generateFunctionResult(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
    const operation_id = operation.operationId orelse return;
    const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{operation_id});
    defer self.allocator.free(result_name);
    const raw_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id});
    defer self.allocator.free(raw_name);

    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.appendIdentifier(result_name);
    try self.buffer.appendSlice(self.allocator, "(client: *Client");
    try self.appendFlatOperationParameters(operation, method, path);
    try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
    try self.appendReturnType(method, operation);
    try self.buffer.appendSlice(self.allocator, ") {\n");
    try self.buffer.appendSlice(self.allocator, "    return parseRawResponse(");
    try self.appendReturnType(method, operation);
    try self.buffer.appendSlice(self.allocator, ", try ");
    try self.appendIdentifier(raw_name);
    try self.appendFlatCallArguments(operation);
    try self.buffer.appendSlice(self.allocator, ");\n");
    try self.buffer.appendSlice(self.allocator, "}\n\n");
}

pub fn generateFunctionRaw(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation, document: UnifiedDocument) !void {
    const operation_id = operation.operationId orelse return;
    const raw_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id});
    defer self.allocator.free(raw_name);

    const kind = bodyKindFor(operation);

    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.appendIdentifier(raw_name);
    try self.buffer.appendSlice(self.allocator, "(client: *Client");
    try self.appendFlatOperationParameters(operation, method, path);
    try self.buffer.appendSlice(self.allocator, ") !RawResponse {\n");
    try self.buffer.appendSlice(self.allocator, "    const allocator = client.allocator;\n");
    try self.appendUnusedParameters(operation, method, path);
    try self.appendUrlConstruction(method, path, operation);
    const raw_has_header_params = hasHeaderParams(operation);
    const header_local_names = try self.headerLocalNamesAlloc(operation);
    defer header_local_names.deinit(self.allocator);
    const scheme = authSchemeForOperation(document, operation);
    const needs_auth = scheme != null;
    const needs_headers = raw_has_header_params or needs_auth;

    switch (kind) {
        .json => {
            const json_ct: []const u8 = if (findBodyParam(operation)) |bp| (bp.content_type orelse "application/json") else "application/json";
            try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
            try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n");
            try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
            try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = str.written();\n");
            if (needs_headers) {
                try self.buffer.appendSlice(self.allocator, "\n");
                try self.appendHeaderLocals(header_local_names);
                try self.appendAuthHeader(scheme, header_local_names);
                if (raw_has_header_params) {
                    try self.appendHeaderParamAppends(operation, method, path, header_local_names);
                }
                if (std.mem.eql(u8, json_ct, "application/json")) {
                    try self.buffer.appendSlice(self.allocator, "\n    return requestRawWithExtraHeaders(client, std.http.Method.");
                    try self.buffer.appendSlice(self.allocator, method);
                    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload, ");
                    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
                    try self.buffer.appendSlice(self.allocator, ".items);\n");
                } else {
                    try self.buffer.appendSlice(self.allocator, "\n    return requestRawWithContentTypeAndExtraHeaders(client, std.http.Method.");
                    try self.buffer.appendSlice(self.allocator, method);
                    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload, \"");
                    try self.buffer.appendSlice(self.allocator, json_ct);
                    try self.buffer.appendSlice(self.allocator, "\", ");
                    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
                    try self.buffer.appendSlice(self.allocator, ".items);\n");
                }
            } else if (std.mem.eql(u8, json_ct, "application/json")) {
                try self.buffer.appendSlice(self.allocator, "\n    return requestRaw(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload);\n");
            } else {
                try self.buffer.appendSlice(self.allocator, "\n    return requestRawWithContentType(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload, \"");
                try self.buffer.appendSlice(self.allocator, json_ct);
                try self.buffer.appendSlice(self.allocator, "\");\n");
            }
            try self.buffer.appendSlice(self.allocator, "}\n\n");
            return;
        },
        .form => {
            try self.buffer.appendSlice(self.allocator, "    // TODO(#53-followup): multipart/form-data and x-www-form-urlencoded request bodies are not yet supported; falling back to JSON encoding.\n");
            try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
            try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n");
            try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
            try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = str.written();\n");
            if (needs_headers) {
                try self.buffer.appendSlice(self.allocator, "\n");
                try self.appendHeaderLocals(header_local_names);
                try self.appendAuthHeader(scheme, header_local_names);
                if (raw_has_header_params) {
                    try self.appendHeaderParamAppends(operation, method, path, header_local_names);
                }
                try self.buffer.appendSlice(self.allocator, "\n    return requestRawWithExtraHeaders(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload, ");
                try self.buffer.appendSlice(self.allocator, header_local_names.headers);
                try self.buffer.appendSlice(self.allocator, ".items);\n");
            } else {
                try self.buffer.appendSlice(self.allocator, "\n    return requestRaw(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload);\n");
            }
            try self.buffer.appendSlice(self.allocator, "}\n\n");
            return;
        },
        .none => {
            try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = null;\n");
            if (needs_headers) {
                try self.buffer.appendSlice(self.allocator, "\n");
                try self.appendHeaderLocals(header_local_names);
                try self.appendAuthHeader(scheme, header_local_names);
                if (raw_has_header_params) {
                    try self.appendHeaderParamAppends(operation, method, path, header_local_names);
                }
                try self.buffer.appendSlice(self.allocator, "\n    return requestRawWithExtraHeaders(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload, ");
                try self.buffer.appendSlice(self.allocator, header_local_names.headers);
                try self.buffer.appendSlice(self.allocator, ".items);\n");
            } else {
                try self.buffer.appendSlice(self.allocator, "\n    return requestRaw(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload);\n");
            }
            try self.buffer.appendSlice(self.allocator, "}\n\n");
            return;
        },
        .binary, .text => {},
    }

    const body_param = findBodyParam(operation) orelse unreachable;
    const ct = body_param.content_type orelse "application/octet-stream";
    try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = requestBody;\n");
    try self.buffer.appendSlice(self.allocator, "\n    var ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, " = std.ArrayList(std.http.Header).empty;\n");
    try self.buffer.appendSlice(self.allocator, "    defer ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ".deinit(allocator);\n");
    try self.buffer.appendSlice(self.allocator, "    try appendClientHeaders(allocator, &");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ", client, \"");
    try self.buffer.appendSlice(self.allocator, ct);
    try self.buffer.appendSlice(self.allocator, "\", \"application/json\");\n");
    try self.appendAuthHeader(scheme, header_local_names);
    if (raw_has_header_params) {
        try self.appendHeaderValuesLocal(header_local_names);
        try self.appendHeaderParamAppends(operation, method, path, header_local_names);
    }
    try self.buffer.appendSlice(self.allocator, "\n    if (client.http_observer) |obs| {\n");
    try self.buffer.appendSlice(self.allocator, "        if (obs.onRequest) |cb| cb(obs.ctx, std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ".items, payload);\n");
    try self.buffer.appendSlice(self.allocator, "    }\n");
    try self.buffer.appendSlice(self.allocator, "\n    const uri = try std.Uri.parse(uri_buf.written());\n");
    try self.buffer.appendSlice(self.allocator, "    var response_body: std.Io.Writer.Allocating = .init(allocator);\n");
    try self.buffer.appendSlice(self.allocator, "    defer response_body.deinit();\n");
    try self.buffer.appendSlice(self.allocator, "    const start = std.Io.Clock.awake.now(client.io);\n");
    try self.buffer.appendSlice(self.allocator, "    const result = client.http.fetch(.{\n");
    try self.buffer.appendSlice(self.allocator, "        .location = .{ .uri = uri },\n");
    try self.buffer.appendSlice(self.allocator, "        .method = std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ",\n");
    try self.buffer.appendSlice(self.allocator, "        .extra_headers = ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ".items,\n");
    try self.buffer.appendSlice(self.allocator, "        .payload = payload,\n");
    try self.buffer.appendSlice(self.allocator, "        .response_writer = &response_body.writer,\n");
    try self.buffer.appendSlice(self.allocator, "    }) catch |err| {\n");
    try self.buffer.appendSlice(self.allocator, "        if (client.http_observer) |obs| {\n");
    try self.buffer.appendSlice(self.allocator, "            if (obs.onError) |cb| cb(obs.ctx, std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), @errorName(err));\n");
    try self.buffer.appendSlice(self.allocator, "        }\n");
    try self.buffer.appendSlice(self.allocator, "        return err;\n");
    try self.buffer.appendSlice(self.allocator, "    };\n");
    try self.buffer.appendSlice(self.allocator, "    const elapsed_ns = @as(u64, @intCast(start.untilNow(client.io, .awake).nanoseconds));\n");
    try self.buffer.appendSlice(self.allocator, "\n    const body = try response_body.toOwnedSlice();\n");
    try self.buffer.appendSlice(self.allocator, "\n    if (client.http_observer) |obs| {\n");
    try self.buffer.appendSlice(self.allocator, "        if (obs.onResponse) |cb| cb(obs.ctx, std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), result.status, &.{}, body, elapsed_ns);\n");
    try self.buffer.appendSlice(self.allocator, "    }\n");
    try self.buffer.appendSlice(self.allocator, "\n    return .{\n");
    try self.buffer.appendSlice(self.allocator, "        .allocator = allocator,\n");
    try self.buffer.appendSlice(self.allocator, "        .status = result.status,\n");
    try self.buffer.appendSlice(self.allocator, "        .body = body,\n");
    try self.buffer.appendSlice(self.allocator, "    };\n");
    try self.buffer.appendSlice(self.allocator, "}\n\n");
}

pub fn generateStreamFunction(self: *UnifiedApiGenerator, name: []const u8, path: []const u8, operation: Operation, document: UnifiedDocument) !void {
    const scheme = authSchemeForOperation(document, operation);
    if (scheme) |s| {
        switch (s) {
            .bearer => {
                try self.buffer.appendSlice(self.allocator, "pub fn ");
                try self.buffer.appendSlice(self.allocator, name);
                try self.buffer.appendSlice(self.allocator, "(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
                try self.buffer.appendSlice(self.allocator, "    var stream_headers = std.ArrayList(std.http.Header).empty;\n");
                try self.buffer.appendSlice(self.allocator, "    defer stream_headers.deinit(client.allocator);\n");
                try self.buffer.appendSlice(self.allocator, "    var auth_header: ?[]u8 = null;\n");
                try self.buffer.appendSlice(self.allocator, "    defer if (auth_header) |value| client.allocator.free(value);\n");
                try self.buffer.appendSlice(self.allocator, "    if (client.api_key.len > 0) {\n");
                try self.buffer.appendSlice(self.allocator, "        auth_header = try std.fmt.allocPrint(client.allocator, \"Bearer {s}\", .{client.api_key});\n");
                try self.buffer.appendSlice(self.allocator, "        try stream_headers.append(client.allocator, .{ .name = \"Authorization\", .value = auth_header.? });\n");
                try self.buffer.appendSlice(self.allocator, "    }\n");
                try self.buffer.appendSlice(self.allocator, "    return streamJsonWithExtraHeaders(client, \"");
                try self.buffer.appendSlice(self.allocator, path);
                try self.buffer.appendSlice(self.allocator, "\", requestBody, callback, cancellation_token, stream_headers.items);\n");
                try self.buffer.appendSlice(self.allocator, "}\n\n");

                try self.buffer.appendSlice(self.allocator, "pub fn ");
                try self.buffer.appendSlice(self.allocator, name);
                try self.buffer.appendSlice(self.allocator, "Events(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
                try self.buffer.appendSlice(self.allocator, "    var stream_headers = std.ArrayList(std.http.Header).empty;\n");
                try self.buffer.appendSlice(self.allocator, "    defer stream_headers.deinit(client.allocator);\n");
                try self.buffer.appendSlice(self.allocator, "    var auth_header: ?[]u8 = null;\n");
                try self.buffer.appendSlice(self.allocator, "    defer if (auth_header) |value| client.allocator.free(value);\n");
                try self.buffer.appendSlice(self.allocator, "    if (client.api_key.len > 0) {\n");
                try self.buffer.appendSlice(self.allocator, "        auth_header = try std.fmt.allocPrint(client.allocator, \"Bearer {s}\", .{client.api_key});\n");
                try self.buffer.appendSlice(self.allocator, "        try stream_headers.append(client.allocator, .{ .name = \"Authorization\", .value = auth_header.? });\n");
                try self.buffer.appendSlice(self.allocator, "    }\n");
                try self.buffer.appendSlice(self.allocator, "    return streamJsonTypedWithExtraHeaders(Event, client, \"");
                try self.buffer.appendSlice(self.allocator, path);
                try self.buffer.appendSlice(self.allocator, "\", requestBody, callback, cancellation_token, stream_headers.items);\n");
                try self.buffer.appendSlice(self.allocator, "}\n\n");
                return;
            },
            .api_key_header => |header_name| {
                const escaped = try escapeZigString(self.allocator, header_name);
                defer self.allocator.free(escaped);
                const header_code = try std.fmt.allocPrint(self.allocator, "pub fn {s}(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {{\n    var stream_headers = std.ArrayList(std.http.Header).empty;\n    defer stream_headers.deinit(client.allocator);\n    if (client.api_key.len > 0) {{\n        try stream_headers.append(client.allocator, .{{ .name = \"{s}\", .value = client.api_key }});\n    }}\n    return streamJsonWithExtraHeaders(client, \"{s}\", requestBody, callback, cancellation_token, stream_headers.items);\n}}\n\npub fn {s}Events(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {{\n    var stream_headers = std.ArrayList(std.http.Header).empty;\n    defer stream_headers.deinit(client.allocator);\n    if (client.api_key.len > 0) {{\n        try stream_headers.append(client.allocator, .{{ .name = \"{s}\", .value = client.api_key }});\n    }}\n    return streamJsonTypedWithExtraHeaders(Event, client, \"{s}\", requestBody, callback, cancellation_token, stream_headers.items);\n}}\n\n", .{ name, escaped, path, name, escaped, path });
                defer self.allocator.free(header_code);
                try self.buffer.appendSlice(self.allocator, header_code);
                return;
            },
        }
    }
    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.buffer.appendSlice(self.allocator, name);
    try self.buffer.appendSlice(self.allocator, "(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
    try self.buffer.appendSlice(self.allocator, "    return streamJson(client, \"");
    try self.buffer.appendSlice(self.allocator, path);
    try self.buffer.appendSlice(self.allocator, "\", requestBody, callback, cancellation_token);\n");
    try self.buffer.appendSlice(self.allocator, "}\n\n");

    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.buffer.appendSlice(self.allocator, name);
    try self.buffer.appendSlice(self.allocator, "Events(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
    try self.buffer.appendSlice(self.allocator, "    return streamJsonTyped(Event, client, \"");
    try self.buffer.appendSlice(self.allocator, path);
    try self.buffer.appendSlice(self.allocator, "\", requestBody, callback, cancellation_token);\n");
    try self.buffer.appendSlice(self.allocator, "}\n\n");
}

pub fn generateComments(self: *UnifiedApiGenerator, operation: Operation) !void {
    if (operation.summary) |summary| {
        try self.buffer.appendSlice(self.allocator, "/////////////////\n");
        try self.buffer.appendSlice(self.allocator, "// Summary:\n");
        try self.appendLineComment(summary);
        try self.buffer.appendSlice(self.allocator, "//\n");
    }

    if (operation.description) |description| {
        try self.buffer.appendSlice(self.allocator, "// Description:\n");
        try self.appendLineComment(description);
        try self.buffer.appendSlice(self.allocator, "//\n");
    }
}

pub fn generateFunctionSignature(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
    try self.buffer.appendSlice(self.allocator, "pub fn ");

    if (operation.operationId) |op_id| {
        try self.appendIdentifier(op_id);
    } else {
        try self.buffer.appendSlice(self.allocator, "@\"operation");
        try self.buffer.appendSlice(self.allocator, path[1..]);
        try self.buffer.appendSlice(self.allocator, "\"");
    }
    try self.buffer.appendSlice(self.allocator, "(client: *Client");
    try self.appendFlatOperationParameters(operation, method, path);

    if (self.hasReturnValue(method, operation)) {
        try self.buffer.appendSlice(self.allocator, ") !Owned(");
        try self.appendReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, ") {\n");
    } else {
        try self.buffer.appendSlice(self.allocator, ") !void {\n");
    }
}

pub fn generateFunctionBody(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
    const operation_id = operation.operationId orelse return self.generateFunctionBodyDirect(method, path, operation);
    if (self.hasReturnValue(method, operation)) {
        const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{operation_id});
        defer self.allocator.free(result_name);
        try self.buffer.appendSlice(self.allocator, "    var result = try ");
        try self.appendIdentifier(result_name);
        try self.appendFlatCallArguments(operation);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.buffer.appendSlice(self.allocator, "    switch (result) {\n");
        try self.buffer.appendSlice(self.allocator, "        .ok => |ok| return ok,\n");
        try self.buffer.appendSlice(self.allocator, "        .api_error => |*err| {\n");
        try self.buffer.appendSlice(self.allocator, "            err.deinit();\n");
        try self.buffer.appendSlice(self.allocator, "            return error.ResponseError;\n");
        try self.buffer.appendSlice(self.allocator, "        },\n");
        try self.buffer.appendSlice(self.allocator, "        .parse_error => |*err| {\n");
        try self.buffer.appendSlice(self.allocator, "            err.raw.deinit();\n");
        try self.buffer.appendSlice(self.allocator, "            return error.ResponseParseError;\n");
        try self.buffer.appendSlice(self.allocator, "        },\n");
        try self.buffer.appendSlice(self.allocator, "    }\n");
    } else {
        const raw_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id});
        defer self.allocator.free(raw_name);
        try self.buffer.appendSlice(self.allocator, "    var raw = try ");
        try self.appendIdentifier(raw_name);
        try self.appendFlatCallArguments(operation);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.buffer.appendSlice(self.allocator, "    defer raw.deinit();\n");
        try self.buffer.appendSlice(self.allocator, "    if (raw.status.class() != .success) return error.ResponseError;\n");
    }
    try self.buffer.appendSlice(self.allocator, "}\n\n");
}

pub fn generateFunctionBodyDirect(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
    try self.buffer.appendSlice(self.allocator, "    const allocator = client.allocator;\n");

    var has_body_param = false;
    if (operation.parameters) |params| {
        for (params) |param| {
            if (param.location == .body) {
                has_body_param = true;
                break;
            }
        }
    }
    const direct_kind = bodyKindFor(operation);
    const direct_body_param = findBodyParam(operation);
    // Form bodies fall back to JSON encoding (multipart/form-data and
    // x-www-form-urlencoded are not yet supported), so the Content-Type
    // header must reflect the actual JSON payload rather than the declared
    // form media type.
    const direct_ct: []const u8 = if (direct_kind == .form)
        "application/json"
    else if (direct_body_param) |p| (p.content_type orelse "application/json") else "application/json";

    if (operation.parameters) |parameters| {
        for (parameters, 0..) |parameter, i| {
            if (parameter.location != .path and parameter.location != .body and parameter.location != .query and parameter.location != .header) {
                try self.buffer.appendSlice(self.allocator, "    _ = ");
                try self.appendParamReference(operation, method, path, i, parameter);
                try self.buffer.appendSlice(self.allocator, ";\n");
            }
        }
    }

    const header_local_names = try self.headerLocalNamesAlloc(operation);
    defer header_local_names.deinit(self.allocator);
    try self.buffer.appendSlice(self.allocator, "    var ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, " = std.ArrayList(std.http.Header).empty;\n");
    try self.buffer.appendSlice(self.allocator, "    defer ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ".deinit(allocator);\n");
    try self.buffer.appendSlice(self.allocator, "    const auth_header = try appendClientHeaders(allocator, &");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ", client, ");
    if (has_body_param) {
        try self.buffer.appendSlice(self.allocator, "\"");
        try self.buffer.appendSlice(self.allocator, direct_ct);
        try self.buffer.appendSlice(self.allocator, "\"");
    } else {
        try self.buffer.appendSlice(self.allocator, "null");
    }
    try self.buffer.appendSlice(self.allocator, ", \"application/json\");\n");
    try self.buffer.appendSlice(self.allocator, "    defer if (auth_header) |value| allocator.free(value);\n");
    const direct_has_header_params = hasHeaderParams(operation);
    if (direct_has_header_params) {
        try self.appendHeaderValuesLocal(header_local_names);
        try self.appendHeaderParamAppends(operation, method, path, header_local_names);
    }
    try self.buffer.appendSlice(self.allocator, "\n");

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
            const size = std.mem.replacementSize(u8, new_path, param, param_type);
            const output = blk: {
                const out = try self.allocator.alloc(u8, size);
                errdefer self.allocator.free(out);
                try allocated_paths.append(self.allocator, out);
                break :blk out;
            };
            _ = std.mem.replace(u8, new_path, param, param_type, output);
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
    const has_path_param_direct = blk: {
        if (operation.parameters) |params| {
            for (params) |p| if (p.location == .path) break :blk true;
        }
        break :blk false;
    };
    if (has_path_param_direct) try self.buffer.appendSlice(self.allocator, " ");
    try self.buffer.appendSlice(self.allocator, "client.base_url");
    if (operation.parameters) |parameters| {
        for (parameters, 0..) |parameter, i| {
            if (parameter.location != .path) continue;
            try self.buffer.appendSlice(self.allocator, ", ");
            try self.appendParamReference(operation, method, path, i, parameter);
        }
    }
    if (has_path_param_direct) try self.buffer.appendSlice(self.allocator, " ");
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
    try self.buffer.appendSlice(self.allocator, "    const uri = try std.Uri.parse(uri_buf.written());\n");

    if (has_body_param) {
        switch (direct_kind) {
            .binary, .text => {
                try self.buffer.appendSlice(self.allocator, "\n    const payload: []const u8 = requestBody;\n");
            },
            .form => {
                try self.buffer.appendSlice(self.allocator, "    // TODO(#53-followup): multipart/form-data and x-www-form-urlencoded request bodies are not yet supported; falling back to JSON encoding.\n");
                try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
                try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n\n");

                try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
                try self.buffer.appendSlice(self.allocator, "    const payload = str.written();\n");
            },
            else => {
                try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
                try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n\n");

                try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
                try self.buffer.appendSlice(self.allocator, "    const payload = str.written();\n");
            },
        }
    }

    const has_return_value = self.hasReturnValue(method, operation);
    if (has_return_value) {
        try self.buffer.appendSlice(self.allocator, "\n    var response_body: std.Io.Writer.Allocating = .init(allocator);\n");
        try self.buffer.appendSlice(self.allocator, "    defer response_body.deinit();\n");
    }

    try self.buffer.appendSlice(self.allocator, "\n    if (client.http_observer) |obs| {\n");
    try self.buffer.appendSlice(self.allocator, "        if (obs.onRequest) |cb| cb(obs.ctx, std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ".items, ");
    if (has_body_param) {
        try self.buffer.appendSlice(self.allocator, "payload");
    } else {
        try self.buffer.appendSlice(self.allocator, "null");
    }
    try self.buffer.appendSlice(self.allocator, ");\n");
    try self.buffer.appendSlice(self.allocator, "    }\n");

    try self.buffer.appendSlice(self.allocator, "    const start = std.Io.Clock.awake.now(client.io);\n");
    try self.buffer.appendSlice(self.allocator, "    const result = client.http.fetch(.{\n");
    try self.buffer.appendSlice(self.allocator, "        .location = .{ .uri = uri },\n");
    try self.buffer.appendSlice(self.allocator, "        .method = std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ",\n");
    try self.buffer.appendSlice(self.allocator, "        .extra_headers = ");
    try self.buffer.appendSlice(self.allocator, header_local_names.headers);
    try self.buffer.appendSlice(self.allocator, ".items,\n");
    if (has_body_param) {
        try self.buffer.appendSlice(self.allocator, "        .payload = payload,\n");
    }
    if (has_return_value) {
        try self.buffer.appendSlice(self.allocator, "        .response_writer = &response_body.writer,\n");
    }
    try self.buffer.appendSlice(self.allocator, "    }) catch |err| {\n");
    try self.buffer.appendSlice(self.allocator, "        if (client.http_observer) |obs| {\n");
    try self.buffer.appendSlice(self.allocator, "            if (obs.onError) |cb| cb(obs.ctx, std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), @errorName(err));\n");
    try self.buffer.appendSlice(self.allocator, "        }\n");
    try self.buffer.appendSlice(self.allocator, "        return err;\n");
    try self.buffer.appendSlice(self.allocator, "    };\n");
    try self.buffer.appendSlice(self.allocator, "    const elapsed_ns = @as(u64, @intCast(start.untilNow(client.io, .awake).nanoseconds));\n");
    try self.buffer.appendSlice(self.allocator, "\n    if (result.status.class() != .success) {\n");
    try self.buffer.appendSlice(self.allocator, "        if (client.http_observer) |obs| {\n");
    try self.buffer.appendSlice(self.allocator, "            if (obs.onResponse) |cb| cb(obs.ctx, std.http.Method.");
    try self.buffer.appendSlice(self.allocator, method);
    try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), result.status, &.{}, \"\", elapsed_ns);\n");
    try self.buffer.appendSlice(self.allocator, "        }\n");
    try self.buffer.appendSlice(self.allocator, "        return error.ResponseError;\n");
    try self.buffer.appendSlice(self.allocator, "    }\n");

    if (has_return_value) {
        try self.buffer.appendSlice(self.allocator, "\n");
        try self.buffer.appendSlice(self.allocator, "    const body = try response_body.toOwnedSlice();\n");
        try self.buffer.appendSlice(self.allocator, "    errdefer allocator.free(body);\n");
        try self.buffer.appendSlice(self.allocator, "    const parsed = try std.json.parseFromSlice(");
        try self.appendReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, ", allocator, body, .{ .ignore_unknown_fields = true });\n");
        try self.buffer.appendSlice(self.allocator, "    if (client.http_observer) |obs| {\n");
        try self.buffer.appendSlice(self.allocator, "        if (obs.onResponse) |cb| cb(obs.ctx, std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), result.status, &.{}, body, elapsed_ns);\n");
        try self.buffer.appendSlice(self.allocator, "    }\n");
        try self.buffer.appendSlice(self.allocator, "    return .{ .allocator = allocator, .body = body, .parsed = parsed };\n");
    } else {
        try self.buffer.appendSlice(self.allocator, "    if (client.http_observer) |obs| {\n");
        try self.buffer.appendSlice(self.allocator, "        if (obs.onResponse) |cb| cb(obs.ctx, std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), result.status, &.{}, \"\", elapsed_ns);\n");
        try self.buffer.appendSlice(self.allocator, "    }\n");
    }

    try self.buffer.appendSlice(self.allocator, "}\n\n");
}

pub fn hasReturnValue(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) bool {
    _ = method;
    return self.successResponseSchema(operation) != null;
}

pub fn successResponseSchema(self: *UnifiedApiGenerator, operation: Operation) ?Schema {
    _ = self;
    const success_codes = [_][]const u8{ "200", "201", "202" };
    for (success_codes) |code| {
        if (operation.responses.get(code)) |response| {
            if (response.schema) |schema| return schema;
        }
    }

    var iterator = operation.responses.iterator();
    while (iterator.next()) |entry| {
        const code = entry.key_ptr.*;
        if (code.len == 3 and code[0] == '2') {
            if (entry.value_ptr.schema) |schema| return schema;
        }
    }

    return null;
}

pub fn appendReturnType(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) !void {
    _ = method;
    if (self.successResponseSchema(operation)) |schema| {
        try self.appendZigTypeFromSchema(schema);
        return;
    }
    try self.buffer.appendSlice(self.allocator, "void");
}

pub fn appendZigQueryTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) !void {
    if (schema.type) |schema_type| {
        switch (schema_type) {
            .string => try self.buffer.appendSlice(self.allocator, "[]const u8"),
            .integer => try self.buffer.appendSlice(self.allocator, "i64"),
            .number => try self.buffer.appendSlice(self.allocator, "f64"),
            .boolean => try self.buffer.appendSlice(self.allocator, "bool"),
            else => try self.buffer.appendSlice(self.allocator, "[]const u8"),
        }
        return;
    }
    try self.buffer.appendSlice(self.allocator, "[]const u8");
}

pub fn appendZigTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) !void {
    if (schema.discriminator_property == null) {
        const variants = schema.one_of orelse schema.any_of orelse &.{};
        if (variants.len == 2) {
            var null_count: usize = 0;
            var child: ?Schema = null;
            for (variants) |variant| {
                if (variant.type == .null) {
                    null_count += 1;
                } else {
                    child = variant;
                }
            }
            if (null_count == 1 and child != null) {
                try self.buffer.appendSlice(self.allocator, "?");
                try self.appendZigTypeFromSchema(child.?);
                return;
            }
        }
    }

    if (schema.ref) |ref| {
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
            try self.buffer.appendSlice(self.allocator, self.model_prefix);
            try self.appendIdentifier(ref[last_slash + 1 ..]);
            return;
        }
    }
    if (schema.type) |schema_type| {
        try self.appendZigTypeFromSchemaType(schema_type);
        return;
    }
    try self.buffer.appendSlice(self.allocator, "std.json.Value");
}

pub fn appendZigTypeFromSchemaType(self: *UnifiedApiGenerator, schema_type: SchemaType) !void {
    try self.buffer.appendSlice(self.allocator, switch (schema_type) {
        .string => "[]const u8",
        .integer => "i64",
        .number => "f64",
        .boolean => "bool",
        .array => "[]const std.json.Value",
        .object, .reference => "std.json.Value",
        .null => "void",
    });
}
