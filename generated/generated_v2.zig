const std = @import("std");

///////////////////////////////////////////
// Generated Zig structures from OpenAPI
///////////////////////////////////////////

pub const Category = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
};

pub const Pet = struct {
    status: ?[]const u8 = null,
    tags: ?[]const Tag = null,
    category: ?Category = null,
    id: ?i64 = null,
    name: []const u8,
    photoUrls: []const []const u8,
};

pub const User = struct {
    password: ?[]const u8 = null,
    userStatus: ?i64 = null,
    username: ?[]const u8 = null,
    email: ?[]const u8 = null,
    firstName: ?[]const u8 = null,
    id: ?i64 = null,
    lastName: ?[]const u8 = null,
    phone: ?[]const u8 = null,
};

pub const Tag = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
};

pub const Order = struct {
    status: ?[]const u8 = null,
    petId: ?i64 = null,
    complete: ?bool = null,
    id: ?i64 = null,
    quantity: ?i64 = null,
    shipDate: ?[]const u8 = null,
};

pub const ApiResponse = struct {
    type: ?[]const u8 = null,
    message: ?[]const u8 = null,
    code: ?i64 = null,
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
    base_url: []const u8 = "https://petstore.swagger.io/v2",
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

/////////////////
// Summary:
// Place an order for a pet
//
// Description:
//
//
pub fn placeOrder(client: *Client, requestBody: Order) !Owned(Order) {
    var result = try placeOrderResult(client, requestBody);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn placeOrderRaw(client: *Client, requestBody: Order) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/store/order", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

pub fn placeOrderResult(client: *Client, requestBody: Order) !ApiResult(Order) {
    return parseRawResponse(Order, try placeOrderRaw(client, requestBody));
}

/////////////////
// Summary:
// uploads an image
//
// Description:
//
//
pub fn uploadFile(client: *Client, petId: i64, additionalMetadata: []const u8, file: []const u8) !Owned(ApiResponse) {
    var result = try uploadFileResult(client, petId, additionalMetadata, file);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn uploadFileRaw(client: *Client, petId: i64, additionalMetadata: []const u8, file: []const u8) !RawResponse {
    const allocator = client.allocator;
    _ = additionalMetadata;
    _ = file;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/{d}/uploadImage", .{ client.base_url, petId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

pub fn uploadFileResult(client: *Client, petId: i64, additionalMetadata: []const u8, file: []const u8) !ApiResult(ApiResponse) {
    return parseRawResponse(ApiResponse, try uploadFileRaw(client, petId, additionalMetadata, file));
}

/////////////////
// Summary:
// Find pet by ID
//
// Description:
// Returns a single pet
//
pub fn getPetById(client: *Client, petId: i64) !Owned(Pet) {
    var result = try getPetByIdResult(client, petId);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn getPetByIdRaw(client: *Client, petId: i64) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/{d}", .{ client.base_url, petId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn getPetByIdResult(client: *Client, petId: i64) !ApiResult(Pet) {
    return parseRawResponse(Pet, try getPetByIdRaw(client, petId));
}

/////////////////
// Summary:
// Updates a pet in the store with form data
//
// Description:
//
//
pub fn updatePetWithForm(client: *Client, petId: i64, name: []const u8, status: []const u8) !void {
    var raw = try updatePetWithFormRaw(client, petId, name, status);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn updatePetWithFormRaw(client: *Client, petId: i64, name: []const u8, status: []const u8) !RawResponse {
    const allocator = client.allocator;
    _ = name;
    _ = status;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/{d}", .{ client.base_url, petId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Deletes a pet
//
// Description:
//
//
pub fn deletePet(client: *Client, api_key: []const u8, petId: i64) !void {
    var raw = try deletePetRaw(client, api_key, petId);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn deletePetRaw(client: *Client, api_key: []const u8, petId: i64) !RawResponse {
    const allocator = client.allocator;
    _ = api_key;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/{d}", .{ client.base_url, petId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.DELETE, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Finds Pets by tags
//
// Description:
// Multiple tags can be provided with comma separated strings. Use tag1, tag2, tag3 for testing.
//
pub fn findPetsByTags(client: *Client, tags: []const std.json.Value) !Owned([]const std.json.Value) {
    var result = try findPetsByTagsResult(client, tags);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn findPetsByTagsRaw(client: *Client, tags: []const std.json.Value) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/findByTags", .{client.base_url});
    var first_query = true;
    try appendQueryParam(&uri_buf.writer, &first_query, "tags", tags);
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn findPetsByTagsResult(client: *Client, tags: []const std.json.Value) !ApiResult([]const std.json.Value) {
    return parseRawResponse([]const std.json.Value, try findPetsByTagsRaw(client, tags));
}

/////////////////
// Summary:
// Logs user into the system
//
// Description:
//
//
pub fn loginUser(client: *Client, username: []const u8, password: []const u8) !Owned([]const u8) {
    var result = try loginUserResult(client, username, password);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn loginUserRaw(client: *Client, username: []const u8, password: []const u8) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/login", .{client.base_url});
    var first_query = true;
    try appendQueryParam(&uri_buf.writer, &first_query, "username", username);
    try appendQueryParam(&uri_buf.writer, &first_query, "password", password);
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn loginUserResult(client: *Client, username: []const u8, password: []const u8) !ApiResult([]const u8) {
    return parseRawResponse([]const u8, try loginUserRaw(client, username, password));
}

/////////////////
// Summary:
// Creates list of users with given input array
//
// Description:
//
//
pub fn createUsersWithArrayInput(client: *Client, requestBody: []const std.json.Value) !void {
    var raw = try createUsersWithArrayInputRaw(client, requestBody);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn createUsersWithArrayInputRaw(client: *Client, requestBody: []const std.json.Value) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/createWithArray", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Finds Pets by status
//
// Description:
// Multiple status values can be provided with comma separated strings
//
pub fn findPetsByStatus(client: *Client, status: []const std.json.Value) !Owned([]const std.json.Value) {
    var result = try findPetsByStatusResult(client, status);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn findPetsByStatusRaw(client: *Client, status: []const std.json.Value) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/findByStatus", .{client.base_url});
    var first_query = true;
    try appendQueryParam(&uri_buf.writer, &first_query, "status", status);
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn findPetsByStatusResult(client: *Client, status: []const std.json.Value) !ApiResult([]const std.json.Value) {
    return parseRawResponse([]const std.json.Value, try findPetsByStatusRaw(client, status));
}

/////////////////
// Summary:
// Returns pet inventories by status
//
// Description:
// Returns a map of status codes to quantities
//
pub fn getInventory(client: *Client) !Owned(std.json.Value) {
    var result = try getInventoryResult(client);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn getInventoryRaw(client: *Client) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/store/inventory", .{client.base_url});
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn getInventoryResult(client: *Client) !ApiResult(std.json.Value) {
    return parseRawResponse(std.json.Value, try getInventoryRaw(client));
}

/////////////////
// Summary:
// Get user by user name
//
// Description:
//
//
pub fn getUserByName(client: *Client, username: []const u8) !Owned(User) {
    var result = try getUserByNameResult(client, username);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn getUserByNameRaw(client: *Client, username: []const u8) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/{s}", .{ client.base_url, username });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn getUserByNameResult(client: *Client, username: []const u8) !ApiResult(User) {
    return parseRawResponse(User, try getUserByNameRaw(client, username));
}

/////////////////
// Summary:
// Updated user
//
// Description:
// This can only be done by the logged in user.
//
pub fn updateUser(client: *Client, username: []const u8, requestBody: User) !void {
    var raw = try updateUserRaw(client, username, requestBody);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn updateUserRaw(client: *Client, username: []const u8, requestBody: User) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/{s}", .{ client.base_url, username });

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.PUT, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Delete user
//
// Description:
// This can only be done by the logged in user.
//
pub fn deleteUser(client: *Client, username: []const u8) !void {
    var raw = try deleteUserRaw(client, username);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn deleteUserRaw(client: *Client, username: []const u8) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/{s}", .{ client.base_url, username });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.DELETE, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Create user
//
// Description:
// This can only be done by the logged in user.
//
pub fn createUser(client: *Client, requestBody: User) !void {
    var raw = try createUserRaw(client, requestBody);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn createUserRaw(client: *Client, requestBody: User) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Creates list of users with given input array
//
// Description:
//
//
pub fn createUsersWithListInput(client: *Client, requestBody: []const std.json.Value) !void {
    var raw = try createUsersWithListInputRaw(client, requestBody);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn createUsersWithListInputRaw(client: *Client, requestBody: []const std.json.Value) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/createWithList", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Add a new pet to the store
//
// Description:
//
//
pub fn addPet(client: *Client, requestBody: Pet) !void {
    var raw = try addPetRaw(client, requestBody);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn addPetRaw(client: *Client, requestBody: Pet) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Update an existing pet
//
// Description:
//
//
pub fn updatePet(client: *Client, requestBody: Pet) !void {
    var raw = try updatePetRaw(client, requestBody);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn updatePetRaw(client: *Client, requestBody: Pet) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.PUT, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Find purchase order by ID
//
// Description:
// For valid response try integer IDs with value >= 1 and <= 10. Other values will generated exceptions
//
pub fn getOrderById(client: *Client, orderId: i64) !Owned(Order) {
    var result = try getOrderByIdResult(client, orderId);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn getOrderByIdRaw(client: *Client, orderId: i64) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/store/order/{d}", .{ client.base_url, orderId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn getOrderByIdResult(client: *Client, orderId: i64) !ApiResult(Order) {
    return parseRawResponse(Order, try getOrderByIdRaw(client, orderId));
}

/////////////////
// Summary:
// Delete purchase order by ID
//
// Description:
// For valid response try integer IDs with positive integer value. Negative or non-integer values will generate API errors
//
pub fn deleteOrder(client: *Client, orderId: i64) !void {
    var raw = try deleteOrderRaw(client, orderId);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn deleteOrderRaw(client: *Client, orderId: i64) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/store/order/{d}", .{ client.base_url, orderId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.DELETE, uri_buf.written(), payload);
}

/////////////////
// Summary:
// Logs out current logged in user session
//
// Description:
//
//
pub fn logoutUser(client: *Client) !void {
    var raw = try logoutUserRaw(client);
    defer raw.deinit();
    if (raw.status.class() != .success) return error.ResponseError;
}

pub fn logoutUserRaw(client: *Client) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/user/logout", .{client.base_url});
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub const resources = struct {
    pub const pet = struct {
        pub fn addpet(client: *Client, requestBody: Pet) !void {
            return addPet(client, requestBody);
        }
        pub fn delete(client: *Client, api_key: []const u8, petId: i64) !void {
            return deletePet(client, api_key, petId);
        }
        pub fn get(client: *Client, petId: i64) !Owned(Pet) {
            return getPetById(client, petId);
        }
        pub fn getResult(client: *Client, petId: i64) !ApiResult(Pet) {
            return getPetByIdResult(client, petId);
        }
        pub fn updatepet_(client: *Client, requestBody: Pet) !void {
            return updatePet(client, requestBody);
        }
        pub fn updatepetwithform_(client: *Client, petId: i64, name: []const u8, status: []const u8) !void {
            return updatePetWithForm(client, petId, name, status);
        }
        pub const findbystatus = struct {
            pub fn findpetsbystatus(client: *Client, status: []const std.json.Value) !Owned([]const std.json.Value) {
                return findPetsByStatus(client, status);
            }
            pub fn findpetsbystatusResult(client: *Client, status: []const std.json.Value) !ApiResult([]const std.json.Value) {
                return findPetsByStatusResult(client, status);
            }
        };
        pub const findbytags = struct {
            pub fn findpetsbytags(client: *Client, tags: []const std.json.Value) !Owned([]const std.json.Value) {
                return findPetsByTags(client, tags);
            }
            pub fn findpetsbytagsResult(client: *Client, tags: []const std.json.Value) !ApiResult([]const std.json.Value) {
                return findPetsByTagsResult(client, tags);
            }
        };
        pub const uploadimage = struct {
            pub fn uploadfile(client: *Client, petId: i64, additionalMetadata: []const u8, file: []const u8) !Owned(ApiResponse) {
                return uploadFile(client, petId, additionalMetadata, file);
            }
            pub fn uploadfileResult(client: *Client, petId: i64, additionalMetadata: []const u8, file: []const u8) !ApiResult(ApiResponse) {
                return uploadFileResult(client, petId, additionalMetadata, file);
            }
        };
    };
    pub const store = struct {
        pub const inventory = struct {
            pub fn get(client: *Client) !Owned(std.json.Value) {
                return getInventory(client);
            }
            pub fn getResult(client: *Client) !ApiResult(std.json.Value) {
                return getInventoryResult(client);
            }
        };
        pub const order = struct {
            pub fn delete(client: *Client, orderId: i64) !void {
                return deleteOrder(client, orderId);
            }
            pub fn get(client: *Client, orderId: i64) !Owned(Order) {
                return getOrderById(client, orderId);
            }
            pub fn getResult(client: *Client, orderId: i64) !ApiResult(Order) {
                return getOrderByIdResult(client, orderId);
            }
            pub fn placeorder(client: *Client, requestBody: Order) !Owned(Order) {
                return placeOrder(client, requestBody);
            }
            pub fn placeorderResult(client: *Client, requestBody: Order) !ApiResult(Order) {
                return placeOrderResult(client, requestBody);
            }
        };
    };
    pub const user = struct {
        pub fn create(client: *Client, requestBody: User) !void {
            return createUser(client, requestBody);
        }
        pub fn delete(client: *Client, username: []const u8) !void {
            return deleteUser(client, username);
        }
        pub fn get(client: *Client, username: []const u8) !Owned(User) {
            return getUserByName(client, username);
        }
        pub fn getResult(client: *Client, username: []const u8) !ApiResult(User) {
            return getUserByNameResult(client, username);
        }
        pub fn update(client: *Client, username: []const u8, requestBody: User) !void {
            return updateUser(client, username, requestBody);
        }
        pub const createwitharray = struct {
            pub fn create(client: *Client, requestBody: []const std.json.Value) !void {
                return createUsersWithArrayInput(client, requestBody);
            }
        };
        pub const createwithlist = struct {
            pub fn create(client: *Client, requestBody: []const std.json.Value) !void {
                return createUsersWithListInput(client, requestBody);
            }
        };
        pub const login = struct {
            pub fn loginuser(client: *Client, username: []const u8, password: []const u8) !Owned([]const u8) {
                return loginUser(client, username, password);
            }
            pub fn loginuserResult(client: *Client, username: []const u8, password: []const u8) !ApiResult([]const u8) {
                return loginUserResult(client, username, password);
            }
        };
        pub const logout = struct {
            pub fn logoutuser(client: *Client) !void {
                return logoutUser(client);
            }
        };
    };
};

pub const pet = resources.pet;
pub const store = resources.store;
pub const user = resources.user;
