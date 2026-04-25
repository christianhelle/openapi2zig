const std = @import("std");

///////////////////////////////////////////
// Generated Zig structures from OpenAPI
///////////////////////////////////////////

pub const Pet = struct {
    tag: ?[]const u8 = null,
    id: i64,
    name: []const u8,
};

///////////////////////////////////////////
// Generated Zig API client from OpenAPI
///////////////////////////////////////////

pub fn Owned(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        body: []u8,
        parsed: std.json.Parsed(T),

        pub fn deinit(self: *@This()) void {
            self.parsed.deinit();
            self.allocator.free(self.body);
        }

        pub fn value(self: *@This()) *T {
            return &self.parsed.value;
        }
    };
}

pub const RawResponse = struct {
    allocator: std.mem.Allocator,
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.body);
    }
};

pub const ParseErrorResponse = struct {
    raw: RawResponse,
    error_name: []const u8,
};

pub fn ApiResult(comptime T: type) type {
    return union(enum) {
        ok: Owned(T),
        api_error: RawResponse,
        parse_error: ParseErrorResponse,

        pub fn deinit(self: *@This()) void {
            switch (self.*) {
                .ok => |*value| value.deinit(),
                .api_error => |*value| value.deinit(),
                .parse_error => |*value| value.raw.deinit(),
            }
        }
    };
}

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    http: std.http.Client,
    api_key: []const u8,
    base_url: []const u8 = "",
    organization: ?[]const u8 = null,
    project: ?[]const u8 = null,
    default_headers: []const std.http.Header = &.{},

    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8) Client {
        return .{
            .allocator = allocator,
            .io = io,
            .http = .{ .allocator = allocator, .io = io },
            .api_key = api_key,
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
    }

    pub fn withBaseUrl(self: *Client, base_url: []const u8) void {
        self.base_url = base_url;
    }
};

fn isQueryChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or switch (c) {
        '-', '.', '_', '~' => true,
        else => false,
    };
}

fn writeQueryComponent(writer: *std.Io.Writer, value: []const u8) !void {
    try std.Uri.Component.percentEncode(writer, value, isQueryChar);
}

fn writeQueryValue(writer: *std.Io.Writer, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writeQueryComponent(writer, value);
            } else {
                try std.json.Stringify.value(value, .{}, writer);
            }
        },
        .int, .comptime_int, .float, .comptime_float, .bool => try writer.print("{}", .{value}),
        .@"enum" => try writeQueryComponent(writer, @tagName(value)),
        else => try std.json.Stringify.value(value, .{}, writer),
    }
}

fn appendQueryParam(writer: *std.Io.Writer, first_query: *bool, name: []const u8, value: anytype) !void {
    if (first_query.*) {
        try writer.writeByte('?');
        first_query.* = false;
    } else {
        try writer.writeByte('&');
    }
    try writeQueryComponent(writer, name);
    try writer.writeByte('=');
    try writeQueryValue(writer, value);
}

pub fn requestRaw(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8) !RawResponse {
    const allocator = client.allocator;
    var headers = std.ArrayList(std.http.Header).empty;
    defer headers.deinit(allocator);
    const auth_header = try appendClientHeaders(allocator, &headers, client, payload != null, "application/json");
    defer if (auth_header) |value| allocator.free(value);

    const uri = try std.Uri.parse(url);
    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = try client.http.fetch(.{
        .location = .{ .uri = uri },
        .method = method,
        .extra_headers = headers.items,
        .payload = payload,
        .response_writer = &response_body.writer,
    });

    return .{
        .allocator = allocator,
        .status = result.status,
        .body = try response_body.toOwnedSlice(),
    };
}

pub fn getRaw(client: *Client, path: []const u8) !RawResponse {
    const url = try std.fmt.allocPrint(client.allocator, "{s}{s}", .{ client.base_url, path });
    defer client.allocator.free(url);
    return requestRaw(client, .GET, url, null);
}

pub fn postJsonRaw(client: *Client, path: []const u8, payload: anytype) !RawResponse {
    const allocator = client.allocator;
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(payload, .{ .emit_null_optional_fields = false }, &str.writer);

    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client.base_url, path });
    defer allocator.free(url);
    return requestRaw(client, .POST, url, str.written());
}

pub fn parseRawResponse(comptime T: type, raw: RawResponse) !ApiResult(T) {
    if (raw.status.class() != .success) return .{ .api_error = raw };
    const parsed = std.json.parseFromSlice(T, raw.allocator, raw.body, .{ .ignore_unknown_fields = true }) catch |err| {
        return .{ .parse_error = .{ .raw = raw, .error_name = @errorName(err) } };
    };
    return .{ .ok = .{ .allocator = raw.allocator, .body = raw.body, .parsed = parsed } };
}

pub fn getJsonResult(comptime T: type, client: *Client, path: []const u8) !ApiResult(T) {
    return parseRawResponse(T, try getRaw(client, path));
}

pub fn postJsonResult(comptime T: type, client: *Client, path: []const u8, payload: anytype) !ApiResult(T) {
    return parseRawResponse(T, try postJsonRaw(client, path, payload));
}

const max_sse_line_size = 256 * 1024;
const max_sse_event_size = 1024 * 1024;

pub fn parseSseBytes(allocator: std.mem.Allocator, bytes: []const u8, callback: anytype) !void {
    var reader: std.Io.Reader = .fixed(bytes);
    try parseSseReader(allocator, &reader, callback);
}

pub fn parseSseReader(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype) !void {
    var line_buf: std.Io.Writer.Allocating = .init(allocator);
    defer line_buf.deinit();

    var event_data: std.Io.Writer.Allocating = .init(allocator);
    defer event_data.deinit();

    while (true) {
        line_buf.clearRetainingCapacity();

        _ = reader.streamDelimiterLimit(&line_buf.writer, '\n', .limited(max_sse_line_size)) catch |err| switch (err) {
            error.StreamTooLong => return error.SseLineTooLong,
            error.ReadFailed => return err,
            error.WriteFailed => return err,
        };

        const ended_with_delimiter = blk: {
            const byte = reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => break :blk false,
                error.ReadFailed => return err,
            };
            if (byte == '\n') {
                _ = try reader.takeByte();
                break :blk true;
            }
            break :blk false;
        };

        if (try processSseLine(&event_data, line_buf.written(), callback)) return;
        if (!ended_with_delimiter) break;
    }

    _ = try dispatchSseEvent(&event_data, callback);
}

fn processSseLine(event_data: *std.Io.Writer.Allocating, raw_line: []const u8, callback: anytype) !bool {
    const line = std.mem.trimEnd(u8, raw_line, "\r");
    if (line.len == 0) return try dispatchSseEvent(event_data, callback);
    if (line[0] == ':') return false;

    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return false;
    const field = line[0..colon];
    if (!std.mem.eql(u8, field, "data")) return false;

    var value = line[colon + 1 ..];
    if (value.len > 0 and value[0] == ' ') value = value[1..];
    const separator_len: usize = if (event_data.written().len == 0) 0 else 1;
    if (event_data.written().len + separator_len + value.len > max_sse_event_size) return error.SseEventTooLong;
    if (separator_len != 0) try event_data.writer.writeByte('\n');
    try event_data.writer.writeAll(value);
    return false;
}

fn dispatchSseEvent(event_data: *std.Io.Writer.Allocating, callback: anytype) !bool {
    const data = event_data.written();
    if (data.len == 0) return false;
    defer event_data.clearRetainingCapacity();

    if (std.mem.eql(u8, data, "[DONE]")) return true;
    try callback.event(data);
    return false;
}

fn TypedSseCallback(comptime T: type, comptime Callback: type) type {
    return struct {
        allocator: std.mem.Allocator,
        callback: *Callback,

        pub fn event(self: *@This(), data: []const u8) !void {
            var parsed = try std.json.parseFromSlice(T, self.allocator, data, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();
            try self.callback.event(&parsed.value);
        }
    };
}

pub fn parseSseBytesTyped(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, callback: anytype) !void {
    const Callback = @TypeOf(callback.*);
    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
    try parseSseBytes(allocator, bytes, &typed_callback);
}

pub fn parseSseReaderTyped(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype) !void {
    const Callback = @TypeOf(callback.*);
    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
    try parseSseReader(allocator, reader, &typed_callback);
}

fn stringifyStreamRequest(allocator: std.mem.Allocator, requestBody: anytype) ![]u8 {
    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, str.written(), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    if (parsed.value == .object) {
        try parsed.value.object.put(parsed.arena.allocator(), "stream", .{ .bool = true });
    }

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .emit_null_optional_fields = false }, &out.writer);
    return try out.toOwnedSlice();
}

fn streamJsonTyped(comptime T: type, client: *Client, path: []const u8, requestBody: anytype, callback: anytype) !void {
    const Callback = @TypeOf(callback.*);
    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = client.allocator, .callback = callback };
    try streamJson(client, path, requestBody, &typed_callback);
}

fn streamJson(client: *Client, path: []const u8, requestBody: anytype, callback: anytype) !void {
    const allocator = client.allocator;
    const payload = try stringifyStreamRequest(allocator, requestBody);
    defer allocator.free(payload);

    var headers = std.ArrayList(std.http.Header).empty;
    defer headers.deinit(allocator);
    const auth_header = try appendClientHeaders(allocator, &headers, client, true, "text/event-stream");
    defer if (auth_header) |value| allocator.free(value);

    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client.base_url, path });
    defer allocator.free(url);
    const uri = try std.Uri.parse(url);

    var req = try client.http.request(.POST, uri, .{
        .redirect_behavior = .unhandled,
        .headers = .{ .accept_encoding = .{ .override = "identity" } },
        .extra_headers = headers.items,
    });
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = payload.len };
    var body = try req.sendBodyUnflushed(&.{});
    try body.writer.writeAll(payload);
    try body.end();
    try req.connection.?.flush();

    var response = try req.receiveHead(&.{});
    if (response.head.status.class() != .success) return error.ResponseError;

    var transfer_buffer: [8 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    parseSseReader(allocator, reader, callback) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr() orelse err,
        else => return err,
    };
}

fn appendClientHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), client: *Client, include_content_type: bool, accept: []const u8) !?[]u8 {
    if (include_content_type) {
        try headers.append(allocator, .{ .name = "Content-Type", .value = "application/json" });
    }
    try headers.append(allocator, .{ .name = "Accept", .value = accept });

    var auth_header: ?[]u8 = null;
    if (client.api_key.len > 0) {
        auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{client.api_key});
        try headers.append(allocator, .{ .name = "Authorization", .value = auth_header.? });
    }
    if (client.organization) |organization| {
        try headers.append(allocator, .{ .name = "OpenAI-Organization", .value = organization });
    }
    if (client.project) |project| {
        try headers.append(allocator, .{ .name = "OpenAI-Project", .value = project });
    }
    for (client.default_headers) |header| {
        try headers.append(allocator, header);
    }
    return auth_header;
}

pub const resources = struct {};
