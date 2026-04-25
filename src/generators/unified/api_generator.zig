const std = @import("std");
const cli = @import("../../cli.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../models/common/document.zig").Operation;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isReservedIdent(name: []const u8) bool {
    const reserved = [_][]const u8{
        "addrspace", "align",    "allowzero", "and",       "anyerror", "anyframe",    "anyopaque", "anytype",
        "asm",       "async",    "await",     "bool",      "break",    "callconv",    "catch",     "comptime",
        "const",     "continue", "defer",     "else",      "enum",     "errdefer",    "error",     "export",
        "extern",    "false",    "fn",        "for",       "if",       "inline",      "isize",     "linksection",
        "noalias",   "noreturn", "nosuspend", "null",      "opaque",   "or",          "orelse",    "packed",
        "pub",       "resume",   "return",    "struct",    "suspend",  "switch",      "test",      "threadlocal",
        "true",      "try",      "type",      "undefined", "union",    "unreachable", "usize",     "usingnamespace",
        "var",       "void",     "volatile",  "while",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn isBareIdentifier(name: []const u8) bool {
    if (name.len == 0 or !isIdentStart(name[0]) or isReservedIdent(name)) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return true;
}

const OperationRef = struct {
    path: []const u8,
    method: []const u8,
    operation: Operation,
};

const ResourceWrapper = struct {
    segments: [][]const u8,
    method_name: []const u8,
    operation_id: []const u8,
    method: []const u8,
    path: []const u8,
    operation: Operation,
    collides: bool = false,
};

fn operationRefLessThan(_: void, lhs: OperationRef, rhs: OperationRef) bool {
    const path_order = std.mem.order(u8, lhs.path, rhs.path);
    if (path_order != .eq) return path_order == .lt;
    return std.mem.order(u8, lhs.method, rhs.method) == .lt;
}

fn resourceWrapperLessThan(_: void, lhs: ResourceWrapper, rhs: ResourceWrapper) bool {
    const segment_order = stringListOrder(lhs.segments, rhs.segments);
    if (segment_order != .eq) return segment_order == .lt;
    const method_order = std.mem.order(u8, lhs.method_name, rhs.method_name);
    if (method_order != .eq) return method_order == .lt;
    return std.mem.order(u8, lhs.operation_id, rhs.operation_id) == .lt;
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn stringListOrder(lhs: []const []const u8, rhs: []const []const u8) std.math.Order {
    const len = @min(lhs.len, rhs.len);
    for (lhs[0..len], rhs[0..len]) |lhs_item, rhs_item| {
        const order = std.mem.order(u8, lhs_item, rhs_item);
        if (order != .eq) return order;
    }
    return std.math.order(lhs.len, rhs.len);
}

fn sameStringList(lhs: []const []const u8, rhs: []const []const u8) bool {
    return stringListOrder(lhs, rhs) == .eq;
}

fn containsString(values: []const []const u8, value: []const u8) bool {
    for (values) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}

fn isVersionSegment(segment: []const u8) bool {
    if (segment.len < 2 or segment[0] != 'v') return false;
    for (segment[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn isPathParam(segment: []const u8) bool {
    return segment.len >= 2 and segment[0] == '{' and segment[segment.len - 1] == '}';
}

pub const UnifiedApiGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    args: cli.CliArgs,

    pub fn init(allocator: std.mem.Allocator, args: cli.CliArgs) UnifiedApiGenerator {
        return UnifiedApiGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).empty,
            .args = args,
        };
    }

    pub fn deinit(self: *UnifiedApiGenerator) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn generate(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.generateHeader();
        try self.generateApiClient(document);
        if (self.args.resource_wrappers != .none) {
            try self.generateResourceWrappers(document);
        }
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn appendIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        if (isBareIdentifier(name)) {
            try self.buffer.appendSlice(self.allocator, name);
            return;
        }

        try self.buffer.appendSlice(self.allocator, "@\"");
        for (name) |c| {
            switch (c) {
                '\\', '"' => {
                    try self.buffer.append(self.allocator, '\\');
                    try self.buffer.append(self.allocator, c);
                },
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
        try self.buffer.appendSlice(self.allocator, "\"");
    }

    fn appendLineComment(self: *UnifiedApiGenerator, text: []const u8) !void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            try self.buffer.appendSlice(self.allocator, "// ");
            try self.buffer.appendSlice(self.allocator, std.mem.trim(u8, line, "\r"));
            try self.buffer.appendSlice(self.allocator, "\n");
        }
    }

    fn generateHeader(self: *UnifiedApiGenerator) !void {
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n");
        try self.buffer.appendSlice(self.allocator, "// Generated Zig API client from OpenAPI\n");
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n\n");
        try self.buffer.appendSlice(self.allocator,
            \\
            \\pub fn Owned(comptime T: type) type {
            \\    return struct {
            \\        allocator: std.mem.Allocator,
            \\        body: []u8,
            \\        parsed: std.json.Parsed(T),
            \\
            \\        pub fn deinit(self: *@This()) void {
            \\            self.parsed.deinit();
            \\            self.allocator.free(self.body);
            \\        }
            \\
            \\        pub fn value(self: *@This()) *T {
            \\            return &self.parsed.value;
            \\        }
            \\    };
            \\}
            \\
            \\pub const RawResponse = struct {
            \\    allocator: std.mem.Allocator,
            \\    status: std.http.Status,
            \\    body: []u8,
            \\
            \\    pub fn deinit(self: *@This()) void {
            \\        self.allocator.free(self.body);
            \\    }
            \\};
            \\
            \\pub const ParseErrorResponse = struct {
            \\    raw: RawResponse,
            \\    error_name: []const u8,
            \\};
            \\
            \\pub fn ApiResult(comptime T: type) type {
            \\    return union(enum) {
            \\        ok: Owned(T),
            \\        api_error: RawResponse,
            \\        parse_error: ParseErrorResponse,
            \\
            \\        pub fn deinit(self: *@This()) void {
            \\            switch (self.*) {
            \\                .ok => |*value| value.deinit(),
            \\                .api_error => |*value| value.deinit(),
            \\                .parse_error => |*value| value.raw.deinit(),
            \\            }
            \\        }
            \\    };
            \\}
            \\
            \\pub const Client = struct {
            \\    allocator: std.mem.Allocator,
            \\    io: std.Io,
            \\    http: std.http.Client,
            \\    api_key: []const u8,
            \\    base_url: []const u8 = "
        );
        if (self.args.base_url) |base_url| try self.buffer.appendSlice(self.allocator, base_url);
        try self.buffer.appendSlice(self.allocator,
            \\",
            \\    organization: ?[]const u8 = null,
            \\    project: ?[]const u8 = null,
            \\    default_headers: []const std.http.Header = &.{},
            \\
            \\    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8) Client {
            \\        return .{
            \\            .allocator = allocator,
            \\            .io = io,
            \\            .http = .{ .allocator = allocator, .io = io },
            \\            .api_key = api_key,
            \\        };
            \\    }
            \\
            \\    pub fn deinit(self: *Client) void {
            \\        self.http.deinit();
            \\    }
            \\
            \\    pub fn withBaseUrl(self: *Client, base_url: []const u8) void {
            \\        self.base_url = base_url;
            \\    }
            \\};
            \\
            \\fn isQueryChar(c: u8) bool {
            \\    return std.ascii.isAlphanumeric(c) or switch (c) {
            \\        '-', '.', '_', '~' => true,
            \\        else => false,
            \\    };
            \\}
            \\
            \\fn writeQueryComponent(writer: *std.Io.Writer, value: []const u8) !void {
            \\    try std.Uri.Component.percentEncode(writer, value, isQueryChar);
            \\}
            \\
            \\fn writeQueryValue(writer: *std.Io.Writer, value: anytype) !void {
            \\    const T = @TypeOf(value);
            \\    switch (@typeInfo(T)) {
            \\        .pointer => |ptr| {
            \\            if (ptr.size == .slice and ptr.child == u8) {
            \\                try writeQueryComponent(writer, value);
            \\            } else {
            \\                try std.json.Stringify.value(value, .{}, writer);
            \\            }
            \\        },
            \\        .int, .comptime_int, .float, .comptime_float, .bool => try writer.print("{}", .{value}),
            \\        .@"enum" => try writeQueryComponent(writer, @tagName(value)),
            \\        else => try std.json.Stringify.value(value, .{}, writer),
            \\    }
            \\}
            \\
            \\fn appendQueryParam(writer: *std.Io.Writer, first_query: *bool, name: []const u8, value: anytype) !void {
            \\    if (first_query.*) {
            \\        try writer.writeByte('?');
            \\        first_query.* = false;
            \\    } else {
            \\        try writer.writeByte('&');
            \\    }
            \\    try writeQueryComponent(writer, name);
            \\    try writer.writeByte('=');
            \\    try writeQueryValue(writer, value);
            \\}
            \\
            \\pub fn requestRaw(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8) !RawResponse {
            \\    const allocator = client.allocator;
            \\    var headers = std.ArrayList(std.http.Header).empty;
            \\    defer headers.deinit(allocator);
            \\    const auth_header = try appendClientHeaders(allocator, &headers, client, payload != null, "application/json");
            \\    defer if (auth_header) |value| allocator.free(value);
            \\
            \\    const uri = try std.Uri.parse(url);
            \\    var response_body: std.Io.Writer.Allocating = .init(allocator);
            \\    defer response_body.deinit();
            \\
            \\    const result = try client.http.fetch(.{
            \\        .location = .{ .uri = uri },
            \\        .method = method,
            \\        .extra_headers = headers.items,
            \\        .payload = payload,
            \\        .response_writer = &response_body.writer,
            \\    });
            \\
            \\    return .{
            \\        .allocator = allocator,
            \\        .status = result.status,
            \\        .body = try response_body.toOwnedSlice(),
            \\    };
            \\}
            \\
            \\pub fn getRaw(client: *Client, path: []const u8) !RawResponse {
            \\    const url = try std.fmt.allocPrint(client.allocator, "{s}{s}", .{ client.base_url, path });
            \\    defer client.allocator.free(url);
            \\    return requestRaw(client, .GET, url, null);
            \\}
            \\
            \\pub fn postJsonRaw(client: *Client, path: []const u8, payload: anytype) !RawResponse {
            \\    const allocator = client.allocator;
            \\    var str: std.Io.Writer.Allocating = .init(allocator);
            \\    defer str.deinit();
            \\    try std.json.Stringify.value(payload, .{ .emit_null_optional_fields = false }, &str.writer);
            \\
            \\    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client.base_url, path });
            \\    defer allocator.free(url);
            \\    return requestRaw(client, .POST, url, str.written());
            \\}
            \\
            \\pub fn parseRawResponse(comptime T: type, raw: RawResponse) !ApiResult(T) {
            \\    if (raw.status.class() != .success) return .{ .api_error = raw };
            \\    const parsed = std.json.parseFromSlice(T, raw.allocator, raw.body, .{ .ignore_unknown_fields = true }) catch |err| {
            \\        return .{ .parse_error = .{ .raw = raw, .error_name = @errorName(err) } };
            \\    };
            \\    return .{ .ok = .{ .allocator = raw.allocator, .body = raw.body, .parsed = parsed } };
            \\}
            \\
            \\pub fn getJsonResult(comptime T: type, client: *Client, path: []const u8) !ApiResult(T) {
            \\    return parseRawResponse(T, try getRaw(client, path));
            \\}
            \\
            \\pub fn postJsonResult(comptime T: type, client: *Client, path: []const u8, payload: anytype) !ApiResult(T) {
            \\    return parseRawResponse(T, try postJsonRaw(client, path, payload));
            \\}
            \\
            \\const max_sse_line_size = 256 * 1024;
            \\const max_sse_event_size = 1024 * 1024;
            \\
            \\pub fn parseSseBytes(allocator: std.mem.Allocator, bytes: []const u8, callback: anytype) !void {
            \\    var reader: std.Io.Reader = .fixed(bytes);
            \\    try parseSseReader(allocator, &reader, callback);
            \\}
            \\
            \\pub fn parseSseReader(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype) !void {
            \\    var line_buf: std.Io.Writer.Allocating = .init(allocator);
            \\    defer line_buf.deinit();
            \\
            \\    var event_data: std.Io.Writer.Allocating = .init(allocator);
            \\    defer event_data.deinit();
            \\
            \\    while (true) {
            \\        line_buf.clearRetainingCapacity();
            \\
            \\        _ = reader.streamDelimiterLimit(&line_buf.writer, '\n', .limited(max_sse_line_size)) catch |err| switch (err) {
            \\            error.StreamTooLong => return error.SseLineTooLong,
            \\            error.ReadFailed => return err,
            \\            error.WriteFailed => return err,
            \\        };
            \\
            \\        const ended_with_delimiter = blk: {
            \\            const byte = reader.peekByte() catch |err| switch (err) {
            \\                error.EndOfStream => break :blk false,
            \\                error.ReadFailed => return err,
            \\            };
            \\            if (byte == '\n') {
            \\                _ = try reader.takeByte();
            \\                break :blk true;
            \\            }
            \\            break :blk false;
            \\        };
            \\
            \\        if (try processSseLine(&event_data, line_buf.written(), callback)) return;
            \\        if (!ended_with_delimiter) break;
            \\    }
            \\
            \\    _ = try dispatchSseEvent(&event_data, callback);
            \\}
            \\
            \\fn processSseLine(event_data: *std.Io.Writer.Allocating, raw_line: []const u8, callback: anytype) !bool {
            \\    const line = std.mem.trimEnd(u8, raw_line, "\r");
            \\    if (line.len == 0) return try dispatchSseEvent(event_data, callback);
            \\    if (line[0] == ':') return false;
            \\
            \\    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return false;
            \\    const field = line[0..colon];
            \\    if (!std.mem.eql(u8, field, "data")) return false;
            \\
            \\    var value = line[colon + 1 ..];
            \\    if (value.len > 0 and value[0] == ' ') value = value[1..];
            \\    const separator_len: usize = if (event_data.written().len == 0) 0 else 1;
            \\    if (event_data.written().len + separator_len + value.len > max_sse_event_size) return error.SseEventTooLong;
            \\    if (separator_len != 0) try event_data.writer.writeByte('\n');
            \\    try event_data.writer.writeAll(value);
            \\    return false;
            \\}
            \\
            \\fn dispatchSseEvent(event_data: *std.Io.Writer.Allocating, callback: anytype) !bool {
            \\    const data = event_data.written();
            \\    if (data.len == 0) return false;
            \\    defer event_data.clearRetainingCapacity();
            \\
            \\    if (std.mem.eql(u8, data, "[DONE]")) return true;
            \\    try callback.event(data);
            \\    return false;
            \\}
            \\
            \\fn TypedSseCallback(comptime T: type, comptime Callback: type) type {
            \\    return struct {
            \\        allocator: std.mem.Allocator,
            \\        callback: *Callback,
            \\
            \\        pub fn event(self: *@This(), data: []const u8) !void {
            \\            var parsed = try std.json.parseFromSlice(T, self.allocator, data, .{ .ignore_unknown_fields = true });
            \\            defer parsed.deinit();
            \\            try self.callback.event(&parsed.value);
            \\        }
            \\    };
            \\}
            \\
            \\pub fn parseSseBytesTyped(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, callback: anytype) !void {
            \\    const Callback = @TypeOf(callback.*);
            \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
            \\    try parseSseBytes(allocator, bytes, &typed_callback);
            \\}
            \\
            \\pub fn parseSseReaderTyped(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype) !void {
            \\    const Callback = @TypeOf(callback.*);
            \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
            \\    try parseSseReader(allocator, reader, &typed_callback);
            \\}
            \\
            \\fn stringifyStreamRequest(allocator: std.mem.Allocator, requestBody: anytype) ![]u8 {
            \\    var str: std.Io.Writer.Allocating = .init(allocator);
            \\    defer str.deinit();
            \\    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
            \\
            \\    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, str.written(), .{ .ignore_unknown_fields = true });
            \\    defer parsed.deinit();
            \\
            \\    if (parsed.value == .object) {
            \\        try parsed.value.object.put(parsed.arena.allocator(), "stream", .{ .bool = true });
            \\    }
            \\
            \\    var out: std.Io.Writer.Allocating = .init(allocator);
            \\    errdefer out.deinit();
            \\    try std.json.Stringify.value(parsed.value, .{ .emit_null_optional_fields = false }, &out.writer);
            \\    return try out.toOwnedSlice();
            \\}
            \\
            \\fn streamJsonTyped(comptime T: type, client: *Client, path: []const u8, requestBody: anytype, callback: anytype) !void {
            \\    const Callback = @TypeOf(callback.*);
            \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = client.allocator, .callback = callback };
            \\    try streamJson(client, path, requestBody, &typed_callback);
            \\}
            \\
            \\fn streamJson(client: *Client, path: []const u8, requestBody: anytype, callback: anytype) !void {
            \\    const allocator = client.allocator;
            \\    const payload = try stringifyStreamRequest(allocator, requestBody);
            \\    defer allocator.free(payload);
            \\
            \\    var headers = std.ArrayList(std.http.Header).empty;
            \\    defer headers.deinit(allocator);
            \\    const auth_header = try appendClientHeaders(allocator, &headers, client, true, "text/event-stream");
            \\    defer if (auth_header) |value| allocator.free(value);
            \\
            \\    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client.base_url, path });
            \\    defer allocator.free(url);
            \\    const uri = try std.Uri.parse(url);
            \\
            \\    var req = try client.http.request(.POST, uri, .{
            \\        .redirect_behavior = .unhandled,
            \\        .headers = .{ .accept_encoding = .{ .override = "identity" } },
            \\        .extra_headers = headers.items,
            \\    });
            \\    defer req.deinit();
            \\
            \\    req.transfer_encoding = .{ .content_length = payload.len };
            \\    var body = try req.sendBodyUnflushed(&.{});
            \\    try body.writer.writeAll(payload);
            \\    try body.end();
            \\    try req.connection.?.flush();
            \\
            \\    var response = try req.receiveHead(&.{});
            \\    if (response.head.status.class() != .success) return error.ResponseError;
            \\
            \\    var transfer_buffer: [8 * 1024]u8 = undefined;
            \\    const reader = response.reader(&transfer_buffer);
            \\    parseSseReader(allocator, reader, callback) catch |err| switch (err) {
            \\        error.ReadFailed => return response.bodyErr() orelse err,
            \\        else => return err,
            \\    };
            \\}
            \\
            \\fn appendClientHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), client: *Client, include_content_type: bool, accept: []const u8) !?[]u8 {
            \\    if (include_content_type) {
            \\        try headers.append(allocator, .{ .name = "Content-Type", .value = "application/json" });
            \\    }
            \\    try headers.append(allocator, .{ .name = "Accept", .value = accept });
            \\
            \\    var auth_header: ?[]u8 = null;
            \\    if (client.api_key.len > 0) {
            \\        auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{client.api_key});
            \\        try headers.append(allocator, .{ .name = "Authorization", .value = auth_header.? });
            \\    }
            \\    if (client.organization) |organization| {
            \\        try headers.append(allocator, .{ .name = "OpenAI-Organization", .value = organization });
            \\    }
            \\    if (client.project) |project| {
            \\        try headers.append(allocator, .{ .name = "OpenAI-Project", .value = project });
            \\    }
            \\    for (client.default_headers) |header| {
            \\        try headers.append(allocator, header);
            \\    }
            \\    return auth_header;
            \\}
            \\
            \\
        );
    }

    fn generateApiClient(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;
            try self.generateOperations(path, path_item);
        }
    }

    fn generateOperations(self: *UnifiedApiGenerator, path: []const u8, path_item: @import("../../models/common/document.zig").PathItem) !void {
        if (path_item.get) |op| try self.generateOperation("GET", path, op);
        if (path_item.post) |op| try self.generateOperation("POST", path, op);
        if (path_item.put) |op| try self.generateOperation("PUT", path, op);
        if (path_item.delete) |op| try self.generateOperation("DELETE", path, op);
        if (path_item.patch) |op| try self.generateOperation("PATCH", path, op);
        if (path_item.head) |op| try self.generateOperation("HEAD", path, op);
        if (path_item.options) |op| try self.generateOperation("OPTIONS", path, op);
    }

    fn generateOperation(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.generateComments(operation);
        try self.generateFunctionSignature(method, path, operation);
        try self.generateFunctionBody(method, path, operation);
        if (operation.operationId != null) {
            try self.generateFunctionRaw(method, path, operation);
        }
        if (operation.operationId != null and self.hasReturnValue(method, operation)) {
            try self.generateFunctionResult(method, path, operation);
        }

        if (operation.operationId) |op_id| {
            if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, op_id, "createChatCompletion")) {
                try self.generateStreamFunction("streamChatCompletion", "CreateChatCompletionRequest", path);
            } else if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, op_id, "createResponse")) {
                try self.generateStreamFunction("streamResponse", "CreateResponse", path);
            }
        }
    }

    fn generateFunctionResult(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        _ = path;
        const operation_id = operation.operationId orelse return;
        const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{operation_id});
        defer self.allocator.free(result_name);
        const raw_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id});
        defer self.allocator.free(raw_name);

        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.appendIdentifier(result_name);
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        try self.appendFlatOperationParameters(operation);
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

    fn generateFunctionRaw(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        const operation_id = operation.operationId orelse return;
        const raw_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id});
        defer self.allocator.free(raw_name);

        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.appendIdentifier(raw_name);
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        try self.appendFlatOperationParameters(operation);
        try self.buffer.appendSlice(self.allocator, ") !RawResponse {\n");
        try self.buffer.appendSlice(self.allocator, "    const allocator = client.allocator;\n");
        try self.appendUnusedParameters(operation);
        try self.appendUrlConstruction(path, operation);

        if (self.hasBodyParameter(operation)) {
            try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
            try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n");
            try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
            try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = str.written();\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = null;\n");
        }

        try self.buffer.appendSlice(self.allocator, "\n    return requestRaw(client, std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload);\n");
        try self.buffer.appendSlice(self.allocator, "}\n\n");
    }

    fn appendFlatCallArguments(self: *UnifiedApiGenerator, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "(client");
        if (operation.parameters) |params| {
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
            }
        }
        try self.buffer.appendSlice(self.allocator, ")");
    }

    fn appendFlatOperationParameters(self: *UnifiedApiGenerator, operation: Operation) !void {
        if (operation.parameters) |params| {
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
                try self.buffer.appendSlice(self.allocator, ": ");
                if (param.location == .body) {
                    if (param.schema) |schema| {
                        try self.appendZigTypeFromSchema(schema);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "std.json.Value");
                    }
                } else {
                    if (param.location == .query and !param.required) try self.buffer.appendSlice(self.allocator, "?");
                    if (param.schema) |schema| {
                        try self.appendZigQueryTypeFromSchema(schema);
                    } else if (param.type) |param_type| {
                        try self.appendZigTypeFromSchemaType(param_type);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "[]const u8");
                    }
                }
            }
        }
    }

    fn appendUnusedParameters(self: *UnifiedApiGenerator, operation: Operation) !void {
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location != .path and parameter.location != .body and parameter.location != .query) {
                    try self.buffer.appendSlice(self.allocator, "    _ = ");
                    try self.appendIdentifier(parameter.name);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                }
            }
        }
    }

    fn appendUrlConstruction(self: *UnifiedApiGenerator, path: []const u8, operation: Operation) !void {
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
                const output = try self.allocator.alloc(u8, size);
                try allocated_paths.append(self.allocator, output);
                _ = std.mem.replace(u8, new_path, param, param_type, output);
                new_path = output;
            }
        }

        try self.buffer.appendSlice(self.allocator, "    var uri_buf: std.Io.Writer.Allocating = .init(allocator);\n");
        try self.buffer.appendSlice(self.allocator, "    defer uri_buf.deinit();\n");
        try self.buffer.appendSlice(self.allocator, "    try uri_buf.writer.print(\"{s}");
        try self.buffer.appendSlice(self.allocator, new_path);
        try self.buffer.appendSlice(self.allocator, "\", .{client.base_url");
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                try self.buffer.appendSlice(self.allocator, ", ");
                try self.appendIdentifier(parameter.name);
            }
        }
        try self.buffer.appendSlice(self.allocator, "});\n");

        var has_query_param = false;
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location == .query) {
                    has_query_param = true;
                    break;
                }
            }
        }
        if (has_query_param) {
            try self.buffer.appendSlice(self.allocator, "    var first_query = true;\n");
            if (operation.parameters) |parameters| {
                for (parameters) |parameter| {
                    if (parameter.location != .query) continue;
                    if (parameter.required) {
                        try self.buffer.appendSlice(self.allocator, "    try appendQueryParam(&uri_buf.writer, &first_query, \"");
                        try self.buffer.appendSlice(self.allocator, parameter.name);
                        try self.buffer.appendSlice(self.allocator, "\", ");
                        try self.appendIdentifier(parameter.name);
                        try self.buffer.appendSlice(self.allocator, ");\n");
                    } else {
                        try self.buffer.appendSlice(self.allocator, "    if (");
                        try self.appendIdentifier(parameter.name);
                        try self.buffer.appendSlice(self.allocator, ") |value| {\n");
                        try self.buffer.appendSlice(self.allocator, "        try appendQueryParam(&uri_buf.writer, &first_query, \"");
                        try self.buffer.appendSlice(self.allocator, parameter.name);
                        try self.buffer.appendSlice(self.allocator, "\", value);\n");
                        try self.buffer.appendSlice(self.allocator, "    }\n");
                    }
                }
            }
        }
    }

    fn hasBodyParameter(self: *UnifiedApiGenerator, operation: Operation) bool {
        _ = self;
        if (operation.parameters) |params| {
            for (params) |param| {
                if (param.location == .body) return true;
            }
        }
        return false;
    }

    fn generateStreamFunction(self: *UnifiedApiGenerator, name: []const u8, request_type: []const u8, path: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.buffer.appendSlice(self.allocator, name);
        try self.buffer.appendSlice(self.allocator, "(client: *Client, requestBody: ");
        try self.buffer.appendSlice(self.allocator, request_type);
        try self.buffer.appendSlice(self.allocator, ", callback: anytype) !void {\n");
        try self.buffer.appendSlice(self.allocator, "    return streamJson(client, \"");
        try self.buffer.appendSlice(self.allocator, path);
        try self.buffer.appendSlice(self.allocator, "\", requestBody, callback);\n");
        try self.buffer.appendSlice(self.allocator, "}\n\n");

        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.buffer.appendSlice(self.allocator, name);
        try self.buffer.appendSlice(self.allocator, "Events(comptime Event: type, client: *Client, requestBody: ");
        try self.buffer.appendSlice(self.allocator, request_type);
        try self.buffer.appendSlice(self.allocator, ", callback: anytype) !void {\n");
        try self.buffer.appendSlice(self.allocator, "    return streamJsonTyped(Event, client, \"");
        try self.buffer.appendSlice(self.allocator, path);
        try self.buffer.appendSlice(self.allocator, "\", requestBody, callback);\n");
        try self.buffer.appendSlice(self.allocator, "}\n\n");
    }

    fn generateResourceWrappers(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
        var operations = std.ArrayList(OperationRef).empty;
        defer operations.deinit(self.allocator);

        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;
            if (path_item.get) |op| try operations.append(self.allocator, .{ .path = path, .method = "GET", .operation = op });
            if (path_item.post) |op| try operations.append(self.allocator, .{ .path = path, .method = "POST", .operation = op });
            if (path_item.put) |op| try operations.append(self.allocator, .{ .path = path, .method = "PUT", .operation = op });
            if (path_item.delete) |op| try operations.append(self.allocator, .{ .path = path, .method = "DELETE", .operation = op });
            if (path_item.patch) |op| try operations.append(self.allocator, .{ .path = path, .method = "PATCH", .operation = op });
            if (path_item.head) |op| try operations.append(self.allocator, .{ .path = path, .method = "HEAD", .operation = op });
            if (path_item.options) |op| try operations.append(self.allocator, .{ .path = path, .method = "OPTIONS", .operation = op });
        }
        std.mem.sort(OperationRef, operations.items, {}, operationRefLessThan);

        var wrappers = std.ArrayList(ResourceWrapper).empty;
        defer {
            for (wrappers.items) |wrapper| {
                for (wrapper.segments) |segment| self.allocator.free(segment);
                self.allocator.free(wrapper.segments);
                self.allocator.free(wrapper.method_name);
            }
            wrappers.deinit(self.allocator);
        }

        for (operations.items) |op_ref| {
            const operation_id = op_ref.operation.operationId orelse continue;
            const segments = try self.resourceSegments(op_ref.path, op_ref.operation);
            if (segments.len == 0) {
                self.allocator.free(segments);
                continue;
            }
            errdefer {
                for (segments) |segment| self.allocator.free(segment);
                self.allocator.free(segments);
            }

            try wrappers.append(self.allocator, .{
                .segments = segments,
                .method_name = try self.resourceMethodName(operation_id, op_ref.method),
                .operation_id = operation_id,
                .method = op_ref.method,
                .path = op_ref.path,
                .operation = op_ref.operation,
            });
        }

        for (wrappers.items, 0..) |*left, i| {
            for (wrappers.items[i + 1 ..]) |*right| {
                if (sameStringList(left.segments, right.segments) and std.mem.eql(u8, left.method_name, right.method_name)) {
                    left.collides = true;
                    right.collides = true;
                }
            }
        }

        std.mem.sort(ResourceWrapper, wrappers.items, {}, resourceWrapperLessThan);

        try self.buffer.appendSlice(self.allocator, "pub const resources = struct {\n");
        try self.generateResourceLevel(wrappers.items, 0, 1, &.{});
        try self.buffer.appendSlice(self.allocator, "};\n\n");

        var top_segments = std.ArrayList([]const u8).empty;
        defer top_segments.deinit(self.allocator);
        for (wrappers.items) |wrapper| {
            const top = wrapper.segments[0];
            if (!containsString(top_segments.items, top)) try top_segments.append(self.allocator, top);
        }
        std.mem.sort([]const u8, top_segments.items, {}, stringLessThan);
        for (top_segments.items) |top| {
            if (self.resourceAliasConflicts(top, document)) continue;
            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.buffer.appendSlice(self.allocator, top);
            try self.buffer.appendSlice(self.allocator, " = resources.");
            try self.buffer.appendSlice(self.allocator, top);
            try self.buffer.appendSlice(self.allocator, ";\n");
        }
        if (top_segments.items.len > 0) try self.buffer.appendSlice(self.allocator, "\n");
    }

    fn generateResourceLevel(self: *UnifiedApiGenerator, wrappers: []ResourceWrapper, depth: usize, indent: usize, ancestor_names: []const []const u8) !void {
        var children = std.ArrayList([]const u8).empty;
        defer children.deinit(self.allocator);
        for (wrappers) |wrapper| {
            if (wrapper.segments.len > depth and !containsString(children.items, wrapper.segments[depth])) {
                try children.append(self.allocator, wrapper.segments[depth]);
            }
        }
        std.mem.sort([]const u8, children.items, {}, stringLessThan);

        var declarations = std.ArrayList([]const u8).empty;
        defer declarations.deinit(self.allocator);
        try declarations.appendSlice(self.allocator, ancestor_names);
        var allocated_declarations = std.ArrayList([]const u8).empty;
        defer {
            for (allocated_declarations.items) |name| self.allocator.free(name);
            allocated_declarations.deinit(self.allocator);
        }

        for (children.items) |child| try declarations.append(self.allocator, child);
        for (wrappers) |wrapper| {
            if (wrapper.segments.len == depth) {
                const name = try self.resourceWrapperNameAlloc(wrapper);
                try allocated_declarations.append(self.allocator, name);
                try declarations.append(self.allocator, name);
                if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                    const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{name});
                    try allocated_declarations.append(self.allocator, result_name);
                    try declarations.append(self.allocator, result_name);
                }
                if (self.streamFunctionName(wrapper.operation_id) != null) {
                    try declarations.append(self.allocator, "stream");
                    try declarations.append(self.allocator, "streamEvents");
                }
            }
        }

        for (wrappers) |wrapper| {
            if (wrapper.segments.len == depth) {
                try self.generateResourceMethod(wrapper, declarations.items, indent);
                if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                    try self.generateResourceResultMethod(wrapper, declarations.items, indent);
                }
                if (self.streamFunctionName(wrapper.operation_id)) |stream_name| {
                    try self.generateResourceStreamMethods(wrapper, stream_name, indent);
                }
            }
        }

        for (children.items) |child| {
            try self.appendIndent(indent);
            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.buffer.appendSlice(self.allocator, child);
            try self.buffer.appendSlice(self.allocator, " = struct {\n");

            var child_wrappers = std.ArrayList(ResourceWrapper).empty;
            defer child_wrappers.deinit(self.allocator);
            for (wrappers) |wrapper| {
                if (wrapper.segments.len > depth and std.mem.eql(u8, wrapper.segments[depth], child)) {
                    try child_wrappers.append(self.allocator, wrapper);
                }
            }
            try self.generateResourceLevel(child_wrappers.items, depth + 1, indent + 1, declarations.items);

            try self.appendIndent(indent);
            try self.buffer.appendSlice(self.allocator, "};\n");
        }
    }

    fn generateResourceMethod(self: *UnifiedApiGenerator, wrapper: ResourceWrapper, forbidden_names: []const []const u8, indent: usize) !void {
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub fn ");
        const wrapper_name = try self.resourceWrapperNameAlloc(wrapper);
        defer self.allocator.free(wrapper_name);
        try self.buffer.appendSlice(self.allocator, wrapper_name);
        try self.appendWrapperSignatureAndReturn(wrapper.method, wrapper.operation, forbidden_names);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        try self.appendIdentifier(wrapper.operation_id);
        try self.appendWrapperCallArguments(wrapper.operation, forbidden_names);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    fn generateResourceResultMethod(self: *UnifiedApiGenerator, wrapper: ResourceWrapper, forbidden_names: []const []const u8, indent: usize) !void {
        const wrapper_name = try self.resourceWrapperNameAlloc(wrapper);
        defer self.allocator.free(wrapper_name);
        const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{wrapper_name});
        defer self.allocator.free(result_name);
        const operation_result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{wrapper.operation_id});
        defer self.allocator.free(operation_result_name);

        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.buffer.appendSlice(self.allocator, result_name);
        try self.appendWrapperResultSignature(wrapper.method, wrapper.operation, forbidden_names);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        try self.appendIdentifier(operation_result_name);
        try self.appendWrapperCallArguments(wrapper.operation, forbidden_names);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    fn appendWrapperResultSignature(self: *UnifiedApiGenerator, method: []const u8, operation: Operation, forbidden_names: []const []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        try self.appendOperationParameters(operation, forbidden_names);
        try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
        try self.appendReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, ")");
    }

    fn resourceWrapperNameAlloc(self: *UnifiedApiGenerator, wrapper: ResourceWrapper) ![]const u8 {
        if (!wrapper.collides) return try self.allocator.dupe(u8, wrapper.method_name);
        const collision_name = try self.sanitizeIdentifierAlloc(wrapper.operation_id);
        defer self.allocator.free(collision_name);
        return try std.fmt.allocPrint(self.allocator, "{s}_", .{collision_name});
    }

    fn generateResourceStreamMethods(self: *UnifiedApiGenerator, wrapper: ResourceWrapper, stream_name: []const u8, indent: usize) !void {
        const request_type = self.bodyTypeName(wrapper.operation) orelse return;

        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub fn stream(client: *Client, requestBody: ");
        try self.buffer.appendSlice(self.allocator, request_type);
        try self.buffer.appendSlice(self.allocator, ", callback: anytype) !void {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        try self.buffer.appendSlice(self.allocator, stream_name);
        try self.buffer.appendSlice(self.allocator, "(client, requestBody, callback);\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");

        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub fn streamEvents(comptime Event: type, client: *Client, requestBody: ");
        try self.buffer.appendSlice(self.allocator, request_type);
        try self.buffer.appendSlice(self.allocator, ", callback: anytype) !void {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        try self.buffer.appendSlice(self.allocator, stream_name);
        try self.buffer.appendSlice(self.allocator, "Events(Event, client, requestBody, callback);\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    fn appendWrapperSignatureAndReturn(self: *UnifiedApiGenerator, method: []const u8, operation: Operation, forbidden_names: []const []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        try self.appendOperationParameters(operation, forbidden_names);
        if (self.hasReturnValue(method, operation)) {
            try self.buffer.appendSlice(self.allocator, ") !Owned(");
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ")");
        } else {
            try self.buffer.appendSlice(self.allocator, ") !void");
        }
    }

    fn appendOperationParameters(self: *UnifiedApiGenerator, operation: Operation, forbidden_names: []const []const u8) !void {
        if (operation.parameters) |params| {
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendParameterName(name, forbidden_names);
                try self.buffer.appendSlice(self.allocator, ": ");
                if (param.location == .body) {
                    if (param.schema) |schema| {
                        try self.appendZigTypeFromSchema(schema);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "std.json.Value");
                    }
                } else {
                    if (param.location == .query and !param.required) try self.buffer.appendSlice(self.allocator, "?");
                    if (param.schema) |schema| {
                        try self.appendZigQueryTypeFromSchema(schema);
                    } else if (param.type) |param_type| {
                        try self.appendZigTypeFromSchemaType(param_type);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "[]const u8");
                    }
                }
            }
        }
    }

    fn appendWrapperCallArguments(self: *UnifiedApiGenerator, operation: Operation, forbidden_names: []const []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "(client");
        if (operation.parameters) |params| {
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendParameterName(name, forbidden_names);
            }
        }
        try self.buffer.appendSlice(self.allocator, ")");
    }

    fn appendParameterName(self: *UnifiedApiGenerator, name: []const u8, forbidden_names: []const []const u8) !void {
        if (containsString(forbidden_names, name)) {
            const safe_name = try self.sanitizeIdentifierAlloc(name);
            defer self.allocator.free(safe_name);
            try self.buffer.appendSlice(self.allocator, safe_name);
            try self.buffer.appendSlice(self.allocator, "_param");
        } else {
            try self.appendIdentifier(name);
        }
    }

    fn bodyTypeName(self: *UnifiedApiGenerator, operation: Operation) ?[]const u8 {
        if (operation.parameters) |params| {
            for (params) |param| {
                if (param.location == .body) {
                    if (param.schema) |schema| {
                        if (schema.ref) |ref| {
                            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| return ref[last_slash + 1 ..];
                        }
                    }
                }
            }
        }
        _ = self;
        return null;
    }

    fn streamFunctionName(self: *UnifiedApiGenerator, operation_id: []const u8) ?[]const u8 {
        _ = self;
        if (std.mem.eql(u8, operation_id, "createChatCompletion")) return "streamChatCompletion";
        if (std.mem.eql(u8, operation_id, "createResponse")) return "streamResponse";
        return null;
    }

    fn resourceAliasConflicts(self: *UnifiedApiGenerator, alias: []const u8, document: UnifiedDocument) bool {
        const reserved_aliases = [_][]const u8{ "organization", "project", "value" };
        for (reserved_aliases) |reserved_alias| {
            if (std.mem.eql(u8, alias, reserved_alias)) return true;
        }

        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path_item = entry.value_ptr.*;
            if (operationHasParameterNamed(self, path_item.get, alias)) return true;
            if (operationHasParameterNamed(self, path_item.post, alias)) return true;
            if (operationHasParameterNamed(self, path_item.put, alias)) return true;
            if (operationHasParameterNamed(self, path_item.delete, alias)) return true;
            if (operationHasParameterNamed(self, path_item.patch, alias)) return true;
            if (operationHasParameterNamed(self, path_item.head, alias)) return true;
            if (operationHasParameterNamed(self, path_item.options, alias)) return true;
        }
        return false;
    }

    fn operationHasParameterNamed(self: *UnifiedApiGenerator, maybe_operation: ?Operation, name: []const u8) bool {
        const operation = maybe_operation orelse return false;
        if (operation.parameters) |params| {
            for (params) |param| {
                const param_name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                const sanitized = self.sanitizeIdentifierAlloc(param_name) catch return true;
                defer self.allocator.free(sanitized);
                if (std.mem.eql(u8, sanitized, name)) return true;
            }
        }
        return false;
    }

    fn resourceSegments(self: *UnifiedApiGenerator, path: []const u8, operation: Operation) ![][]const u8 {
        return switch (self.args.resource_wrappers) {
            .none => self.allocator.alloc([]const u8, 0),
            .paths => self.resourceSegmentsFromPath(path),
            .tags => if (operation.tags) |tags| blk: {
                if (tags.len > 0) {
                    const segments = try self.allocator.alloc([]const u8, 1);
                    segments[0] = try self.sanitizeIdentifierAlloc(tags[0]);
                    break :blk segments;
                }
                break :blk try self.resourceSegmentsFromPath(path);
            } else self.resourceSegmentsFromPath(path),
            .hybrid => self.resourceSegmentsHybrid(path, operation),
        };
    }

    fn resourceSegmentsHybrid(self: *UnifiedApiGenerator, path: []const u8, operation: Operation) ![][]const u8 {
        const path_segments = try self.resourceSegmentsFromPath(path);
        errdefer {
            for (path_segments) |segment| self.allocator.free(segment);
            self.allocator.free(path_segments);
        }

        if (operation.tags == null or operation.tags.?.len == 0) return path_segments;
        const tag = try self.sanitizeIdentifierAlloc(operation.tags.?[0]);
        errdefer self.allocator.free(tag);
        if (path_segments.len > 0 and std.mem.eql(u8, path_segments[0], tag)) {
            self.allocator.free(tag);
            return path_segments;
        }

        const segments = try self.allocator.alloc([]const u8, path_segments.len + 1);
        segments[0] = tag;
        for (path_segments, 0..) |segment, i| segments[i + 1] = segment;
        self.allocator.free(path_segments);
        return segments;
    }

    fn resourceSegmentsFromPath(self: *UnifiedApiGenerator, path: []const u8) ![][]const u8 {
        var segments = std.ArrayList([]const u8).empty;
        errdefer {
            for (segments.items) |segment| self.allocator.free(segment);
            segments.deinit(self.allocator);
        }

        var iterator = std.mem.splitScalar(u8, path, '/');
        while (iterator.next()) |raw_segment| {
            if (raw_segment.len == 0 or isVersionSegment(raw_segment) or isPathParam(raw_segment)) continue;
            try segments.append(self.allocator, try self.sanitizeIdentifierAlloc(raw_segment));
        }
        return try segments.toOwnedSlice(self.allocator);
    }

    fn resourceMethodName(self: *UnifiedApiGenerator, operation_id: []const u8, method: []const u8) ![]const u8 {
        _ = method;
        const verbs = [_]struct { prefix: []const u8, name: []const u8 }{
            .{ .prefix = "create", .name = "create" },
            .{ .prefix = "list", .name = "list" },
            .{ .prefix = "retrieve", .name = "retrieve" },
            .{ .prefix = "get", .name = "get" },
            .{ .prefix = "delete", .name = "delete" },
            .{ .prefix = "update", .name = "update" },
            .{ .prefix = "modify", .name = "update" },
            .{ .prefix = "cancel", .name = "cancel" },
        };
        for (verbs) |verb| {
            if (std.mem.startsWith(u8, operation_id, verb.prefix) and
                (operation_id.len == verb.prefix.len or std.ascii.isUpper(operation_id[verb.prefix.len])))
            {
                return try self.allocator.dupe(u8, verb.name);
            }
        }
        return self.sanitizeIdentifierAlloc(operation_id);
    }

    fn sanitizeIdentifierAlloc(self: *UnifiedApiGenerator, value: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);
        for (value, 0..) |c, i| {
            const lower = std.ascii.toLower(c);
            const valid = if (i == 0) isIdentStart(lower) else isIdentContinue(lower);
            try out.append(self.allocator, if (valid) lower else '_');
        }
        if (out.items.len == 0 or !isIdentStart(out.items[0])) try out.insert(self.allocator, 0, '_');
        if (isReservedIdent(out.items)) try out.appendSlice(self.allocator, "_");
        return try out.toOwnedSlice(self.allocator);
    }

    fn appendIndent(self: *UnifiedApiGenerator, indent: usize) !void {
        for (0..indent) |_| try self.buffer.appendSlice(self.allocator, "    ");
    }

    fn generateComments(self: *UnifiedApiGenerator, operation: Operation) !void {
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

    fn generateFunctionSignature(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "pub fn ");

        if (operation.operationId) |op_id| {
            try self.appendIdentifier(op_id);
        } else {
            try self.buffer.appendSlice(self.allocator, "@\"operation");
            try self.buffer.appendSlice(self.allocator, path[1..]);
            try self.buffer.appendSlice(self.allocator, "\"");
        }
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        if (operation.parameters) |params| {
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
                try self.buffer.appendSlice(self.allocator, ": ");
                if (param.location == .body) {
                    if (param.schema) |schema| {
                        try self.appendZigTypeFromSchema(schema);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "std.json.Value");
                    }
                } else {
                    if (param.location == .query and !param.required) {
                        try self.buffer.appendSlice(self.allocator, "?");
                    }
                    if (param.schema) |schema| {
                        try self.appendZigQueryTypeFromSchema(schema);
                    } else if (param.type) |param_type| {
                        try self.appendZigTypeFromSchemaType(param_type);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "[]const u8");
                    }
                }
            }
        }

        if (self.hasReturnValue(method, operation)) {
            try self.buffer.appendSlice(self.allocator, ") !Owned(");
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ") {\n");
        } else {
            try self.buffer.appendSlice(self.allocator, ") !void {\n");
        }
    }

    fn generateFunctionBody(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
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

    fn generateFunctionBodyDirect(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
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

        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location != .path and parameter.location != .body and parameter.location != .query) {
                    try self.buffer.appendSlice(self.allocator, "    _ = ");
                    try self.appendIdentifier(parameter.name);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                }
            }
        }

        try self.buffer.appendSlice(self.allocator, "    var headers = std.ArrayList(std.http.Header).empty;\n");
        try self.buffer.appendSlice(self.allocator, "    defer headers.deinit(allocator);\n");
        try self.buffer.appendSlice(self.allocator, "    const auth_header = try appendClientHeaders(allocator, &headers, client, ");
        try self.buffer.appendSlice(self.allocator, if (has_body_param) "true" else "false");
        try self.buffer.appendSlice(self.allocator, ", \"application/json\");\n");
        try self.buffer.appendSlice(self.allocator, "    defer if (auth_header) |value| allocator.free(value);\n\n");

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
                const output = try self.allocator.alloc(u8, size);
                try allocated_paths.append(self.allocator, output);
                _ = std.mem.replace(u8, new_path, param, param_type, output);
                new_path = output;
            }
        }

        try self.buffer.appendSlice(self.allocator, "    var uri_buf: std.Io.Writer.Allocating = .init(allocator);\n");
        try self.buffer.appendSlice(self.allocator, "    defer uri_buf.deinit();\n");
        try self.buffer.appendSlice(self.allocator, "    try uri_buf.writer.print(\"{s}");
        try self.buffer.appendSlice(self.allocator, new_path);
        try self.buffer.appendSlice(self.allocator, "\", .{client.base_url");
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                try self.buffer.appendSlice(self.allocator, ", ");
                try self.appendIdentifier(parameter.name);
            }
        }
        try self.buffer.appendSlice(self.allocator, "});\n");

        var has_query_param = false;
        if (operation.parameters) |parameters| {
            for (parameters) |parameter| {
                if (parameter.location == .query) {
                    has_query_param = true;
                    break;
                }
            }
        }
        if (has_query_param) {
            try self.buffer.appendSlice(self.allocator, "    var first_query = true;\n");
            if (operation.parameters) |parameters| {
                for (parameters) |parameter| {
                    if (parameter.location != .query) continue;
                    if (parameter.required) {
                        try self.buffer.appendSlice(self.allocator, "    try appendQueryParam(&uri_buf.writer, &first_query, \"");
                        try self.buffer.appendSlice(self.allocator, parameter.name);
                        try self.buffer.appendSlice(self.allocator, "\", ");
                        try self.appendIdentifier(parameter.name);
                        try self.buffer.appendSlice(self.allocator, ");\n");
                    } else {
                        try self.buffer.appendSlice(self.allocator, "    if (");
                        try self.appendIdentifier(parameter.name);
                        try self.buffer.appendSlice(self.allocator, ") |value| {\n");
                        try self.buffer.appendSlice(self.allocator, "        try appendQueryParam(&uri_buf.writer, &first_query, \"");
                        try self.buffer.appendSlice(self.allocator, parameter.name);
                        try self.buffer.appendSlice(self.allocator, "\", value);\n");
                        try self.buffer.appendSlice(self.allocator, "    }\n");
                    }
                }
            }
        }
        try self.buffer.appendSlice(self.allocator, "    const uri = try std.Uri.parse(uri_buf.written());\n");

        if (has_body_param) {
            try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
            try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n\n");
            try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
            try self.buffer.appendSlice(self.allocator, "    const payload = str.written();\n");
        }

        const has_return_value = self.hasReturnValue(method, operation);
        if (has_return_value) {
            try self.buffer.appendSlice(self.allocator, "\n    var response_body: std.Io.Writer.Allocating = .init(allocator);\n");
            try self.buffer.appendSlice(self.allocator, "    defer response_body.deinit();\n");
        }

        try self.buffer.appendSlice(self.allocator, "\n    const result = try client.http.fetch(.{\n");
        try self.buffer.appendSlice(self.allocator, "        .location = .{ .uri = uri },\n");
        try self.buffer.appendSlice(self.allocator, "        .method = std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ",\n");
        try self.buffer.appendSlice(self.allocator, "        .extra_headers = headers.items,\n");
        if (has_body_param) {
            try self.buffer.appendSlice(self.allocator, "        .payload = payload,\n");
        }
        if (has_return_value) {
            try self.buffer.appendSlice(self.allocator, "        .response_writer = &response_body.writer,\n");
        }
        try self.buffer.appendSlice(self.allocator, "    });\n");
        try self.buffer.appendSlice(self.allocator, "    if (result.status.class() != .success) {\n");
        try self.buffer.appendSlice(self.allocator, "        return error.ResponseError;\n");
        try self.buffer.appendSlice(self.allocator, "    }\n");

        if (has_return_value) {
            try self.buffer.appendSlice(self.allocator, "\n");
            try self.buffer.appendSlice(self.allocator, "    const body = try response_body.toOwnedSlice();\n");
            try self.buffer.appendSlice(self.allocator, "    errdefer allocator.free(body);\n");
            try self.buffer.appendSlice(self.allocator, "    const parsed = try std.json.parseFromSlice(");
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ", allocator, body, .{ .ignore_unknown_fields = true });\n");
            try self.buffer.appendSlice(self.allocator, "    return .{ .allocator = allocator, .body = body, .parsed = parsed };\n");
        }

        try self.buffer.appendSlice(self.allocator, "}\n\n");
    }

    fn hasReturnValue(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) bool {
        _ = method;
        return self.successResponseSchema(operation) != null;
    }

    fn successResponseSchema(self: *UnifiedApiGenerator, operation: Operation) ?Schema {
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

    fn appendReturnType(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) !void {
        _ = method;
        if (self.successResponseSchema(operation)) |schema| {
            try self.appendZigTypeFromSchema(schema);
            return;
        }
        try self.buffer.appendSlice(self.allocator, "void");
    }

    fn appendZigQueryTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) !void {
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

    fn appendZigTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) !void {
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

    fn appendZigTypeFromSchemaType(self: *UnifiedApiGenerator, schema_type: SchemaType) !void {
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
};
