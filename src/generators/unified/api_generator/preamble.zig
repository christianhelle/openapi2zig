const std = @import("std");
const helpers = @import("helpers.zig");
const escapeZigString = helpers.escapeZigString;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

pub fn generateHeader(self: *UnifiedApiGenerator) !void {
    try self.generateRuntimePreamble();
    try self.generateClientPreamble();
    try self.generateSsePreamble();
    try self.generateSseBufferConstants();
}

pub fn generateHeaderMulti(self: *UnifiedApiGenerator) !void {
    if (self.emit_imports) {
        const escaped_models = try escapeZigString(self.allocator, self.models_import);
        defer self.allocator.free(escaped_models);
        const escaped_runtime = try escapeZigString(self.allocator, self.runtime_import);
        defer self.allocator.free(escaped_runtime);
        const imports = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\const {s} = @import("{s}");
            \\const {s} = @import("{s}");
            \\
        , .{ self.models_import_alias, escaped_models, self.runtime_import_alias, escaped_runtime });
        defer self.allocator.free(imports);
        try self.buffer.appendSlice(self.allocator, imports);
        try self.generateRuntimeReexports();
    }
    try self.generateClientPreamble();
}

pub fn generateRuntimePreamble(self: *UnifiedApiGenerator) !void {
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
    );
    try self.generateHttpObserverType();
}

pub fn generateRuntimeReexports(self: *UnifiedApiGenerator) !void {
    const alias = self.runtime_import_alias;
    const exports = try std.fmt.allocPrint(self.allocator,
        \\const Owned = {s}.Owned;
        \\const HttpObserver = {s}.HttpObserver;
        \\const RawResponse = {s}.RawResponse;
        \\const ParseErrorResponse = {s}.ParseErrorResponse;
        \\const ApiResult = {s}.ApiResult;
        \\const CancellationToken = {s}.CancellationToken;
        \\const checkCancellation = {s}.checkCancellation;
        \\const CancelableReader = {s}.CancelableReader;
        \\const parseSseReader = {s}.parseSseReader;
        \\const parseSseBytes = {s}.parseSseBytes;
        \\const parseSseBytesTyped = {s}.parseSseBytesTyped;
        \\const parseSseReaderTyped = {s}.parseSseReaderTyped;
        \\const TypedSseCallback = {s}.TypedSseCallback;
        \\
    , .{ alias, alias, alias, alias, alias, alias, alias, alias, alias, alias, alias, alias, alias });
    defer self.allocator.free(exports);
    try self.buffer.appendSlice(self.allocator, exports);
}

pub fn generateClientPreamble(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
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
        \\    http_observer: ?HttpObserver = null,
        \\
        \\    /// Optional predicate polled while reading a streaming response body.
        \\    /// When it returns true, a successfully started background watcher interrupts
        \\    /// a blocked SSE socket read within about 10 ms and the stream exits with
        \\    /// error.Cancelled. A CancelableReader also checks the predicate at every read
        \\    /// boundary. If watcher startup fails, cancellation remains read-boundary only.
        \\    /// Point it at an app-level cancel flag; it composes with a CancellationToken.
        \\    /// When null (default), no watcher thread is spawned.
        \\    cancel_check: ?*const fn () bool = null,
        \\
        \\    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8) Client {
        \\        return .{
        \\            .allocator = allocator,
        \\            .io = io,
        \\            .http = .{ .allocator = allocator, .io = io },
        \\            .api_key = api_key,
        \\            .http_observer = null,
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
        \\
    );
    if (self.has_streaming_operations) try self.generateCancelWatcher();
    try self.buffer.appendSlice(self.allocator,
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
        \\/// Serializes an `in: header` parameter value to an owned string. Reuses
        \\/// the same primitive-type coverage as query parameters (string, integer,
        \\/// float, boolean, enum). The caller frees the returned slice.
        \\fn formatHeaderValue(allocator: std.mem.Allocator, value: anytype) ![]u8 {
        \\    const T = @TypeOf(value);
        \\    return switch (@typeInfo(T)) {
        \\        .pointer => |ptr| blk: {
        \\            if (ptr.size == .slice and ptr.child == u8) {
        \\                break :blk try allocator.dupe(u8, value);
        \\            }
        \\            @compileError("OpenAPI header values must be strings, numbers, booleans, or enums");
        \\        },
        \\        .@"enum" => try allocator.dupe(u8, @tagName(value)),
        \\        .int, .comptime_int, .float, .comptime_float, .bool => try std.fmt.allocPrint(allocator, "{}", .{value}),
        \\        else => @compileError("OpenAPI header values must be strings, numbers, booleans, or enums"),
        \\    };
        \\}
        \\
        \\/// Appends `value` under `name`, replacing (case-insensitively) any
        \\/// existing header of the same name. Used so a declared operation header
        \\/// parameter always wins over an equal-named client default header while
        \\/// emitting exactly one header on the wire.
        \\fn appendOrReplaceHeader(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
        \\    var i: usize = 0;
        \\    while (i < headers.items.len) {
        \\        if (std.ascii.eqlIgnoreCase(headers.items[i].name, name)) {
        \\            _ = headers.orderedRemove(i);
        \\        } else {
        \\            i += 1;
        \\        }
        \\    }
        \\    try headers.append(allocator, .{ .name = name, .value = value });
        \\}
        \\
        \\pub fn requestRaw(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8) !RawResponse {
        \\    return requestRawWithContentType(client, method, url, payload, "application/json");
        \\}
        \\
        \\pub fn requestRawWithExtraHeaders(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8, extra_headers: []const std.http.Header) !RawResponse {
        \\    return requestRawWithContentTypeAndExtraHeaders(client, method, url, payload, "application/json", extra_headers);
        \\}
        \\
        \\pub fn requestRawWithContentTypeAndExtraHeaders(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8, content_type_value: []const u8, extra_headers: []const std.http.Header) !RawResponse {
        \\    const allocator = client.allocator;
        \\    var headers = std.ArrayList(std.http.Header).empty;
        \\    defer headers.deinit(allocator);
        \\    const content_type: ?[]const u8 = if (payload != null) content_type_value else null;
        \\    try appendClientHeaders(allocator, &headers, client, content_type, "application/json");
        \\    for (extra_headers) |header| try appendOrReplaceHeader(allocator, &headers, header.name, header.value);
        \\
        \\    if (client.http_observer) |obs| {
        \\        if (obs.onRequest) |cb| cb(obs.ctx, method, url, headers.items, payload);
        \\    }
        \\
        \\    const uri = try std.Uri.parse(url);
        \\    var response_body: std.Io.Writer.Allocating = .init(allocator);
        \\    defer response_body.deinit();
        \\
        \\    const start = std.Io.Clock.awake.now(client.io);
        \\    const result = client.http.fetch(.{
        \\        .location = .{ .uri = uri },
        \\        .method = method,
        \\        .extra_headers = headers.items,
        \\        .payload = payload,
        \\        .response_writer = &response_body.writer,
        \\    }) catch |err| {
        \\        if (client.http_observer) |obs| {
        \\            if (obs.onError) |cb| cb(obs.ctx, method, url, @errorName(err));
        \\        }
        \\        return err;
        \\    };
        \\    const elapsed_ns = @as(u64, @intCast(start.untilNow(client.io, .awake).nanoseconds));
        \\
        \\    const body = try response_body.toOwnedSlice();
        \\
        \\    if (client.http_observer) |obs| {
        \\        if (obs.onResponse) |cb| cb(obs.ctx, method, url, result.status, &.{}, body, elapsed_ns);
        \\    }
        \\
        \\    return .{
        \\        .allocator = allocator,
        \\        .status = result.status,
        \\        .body = body,
        \\    };
        \\}
        \\
        \\pub fn requestRawWithContentType(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8, content_type_value: []const u8) !RawResponse {
        \\    const allocator = client.allocator;
        \\    var headers = std.ArrayList(std.http.Header).empty;
        \\    defer headers.deinit(allocator);
        \\    const content_type: ?[]const u8 = if (payload != null) content_type_value else null;
        \\    try appendClientHeaders(allocator, &headers, client, content_type, "application/json");
        \\
        \\    if (client.http_observer) |obs| {
        \\        if (obs.onRequest) |cb| cb(obs.ctx, method, url, headers.items, payload);
        \\    }
        \\
        \\    const uri = try std.Uri.parse(url);
        \\    var response_body: std.Io.Writer.Allocating = .init(allocator);
        \\    defer response_body.deinit();
        \\
        \\    const start = std.Io.Clock.awake.now(client.io);
        \\    const result = client.http.fetch(.{
        \\        .location = .{ .uri = uri },
        \\        .method = method,
        \\        .extra_headers = headers.items,
        \\        .payload = payload,
        \\        .response_writer = &response_body.writer,
        \\    }) catch |err| {
        \\        if (client.http_observer) |obs| {
        \\            if (obs.onError) |cb| cb(obs.ctx, method, url, @errorName(err));
        \\        }
        \\        return err;
        \\    };
        \\    const elapsed_ns = @as(u64, @intCast(start.untilNow(client.io, .awake).nanoseconds));
        \\
        \\    const body = try response_body.toOwnedSlice();
        \\
        \\    if (client.http_observer) |obs| {
        \\        if (obs.onResponse) |cb| cb(obs.ctx, method, url, result.status, &.{}, body, elapsed_ns);
        \\    }
        \\
        \\    return .{
        \\        .allocator = allocator,
        \\        .status = result.status,
        \\        .body = body,
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
    );
    try self.generateStreamAuthCode();
}

pub fn generateCancelWatcher(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
        \\    const CancelWatcher = struct {
        \\        connection: ?*std.http.Client.Connection,
        \\        io: std.Io,
        \\        pred: *const fn () bool,
        \\        done: *std.atomic.Value(bool),
        \\        replacement_handle: ?std.Io.net.Socket.Handle = null,
        \\        interrupted: bool = false,
        \\
        \\        const Windows = if (@import("builtin").os.tag == .windows) struct {
        \\            extern "kernel32" fn CreateEventW(event_attributes: ?*anyopaque, manual_reset: std.os.windows.BOOL, initial_state: std.os.windows.BOOL, name: ?[*:0]const u16) callconv(.winapi) ?std.os.windows.HANDLE;
        \\        } else struct {};
        \\
        \\        fn run(self: *CancelWatcher) void {
        \\            while (!self.done.load(.acquire)) {
        \\                if (self.pred()) {
        \\                    if (self.connection) |conn| {
        \\                        if (comptime @import("builtin").os.tag == .windows) {
        \\                            if (Windows.CreateEventW(null, .FALSE, .FALSE, null)) |replacement| {
        \\                                // Connection.destroy unconditionally closes the stream handle. Preserve
        \\                                // a separately owned valid handle for it before closing the socket.
        \\                                self.replacement_handle = replacement;
        \\                                self.interrupted = true;
        \\                                conn.stream_reader.stream.close(self.io);
        \\                            } else {
        \\                                self.interrupted = true;
        \\                                conn.stream_reader.stream.shutdown(self.io, .both) catch {};
        \\                            }
        \\                        } else {
        \\                            self.interrupted = true;
        \\                            conn.stream_reader.stream.shutdown(self.io, .both) catch {};
        \\                        }
        \\                    }
        \\                    return;
        \\                }
        \\                self.io.sleep(.{ .nanoseconds = 10 * std.time.ns_per_ms }, .awake) catch return;
        \\            }
        \\        }
        \\    };
        \\
    );
}

pub fn generateSsePreamble(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
        \\pub const CancellationToken = struct {
        \\    cancelled: std.atomic.Value(bool),
        \\
        \\    pub fn init() CancellationToken {
        \\        return .{ .cancelled = std.atomic.Value(bool).init(false) };
        \\    }
        \\
        \\    pub fn cancel(self: *CancellationToken) void {
        \\        self.cancelled.store(true, .seq_cst);
        \\    }
        \\
        \\    pub fn isCancelled(self: *CancellationToken) bool {
        \\        return self.cancelled.load(.seq_cst);
        \\    }
        \\};
        \\
        \\fn checkCancellation(token: ?*CancellationToken) !void {
        \\    if (token) |t| {
        \\        if (t.isCancelled()) return error.Cancelled;
        \\    }
        \\}
        \\
        \\/// Wraps an underlying reader and checks an optional cancel predicate before
        \\/// every read of the underlying reader. When the predicate returns true, the
        \\/// read fails with error.ReadFailed; callers translate that into
        \\/// error.Cancelled. Cancellation is only observed at read boundaries: a read
        \\/// already blocked inside the underlying reader (e.g. waiting for the next SSE
        \\/// chunk on the socket) is not aborted until that read returns.
        \\pub const CancelableReader = struct {
        \\    inner: *std.Io.Reader,
        \\    reader: std.Io.Reader,
        \\    should_cancel: ?*const fn () bool,
        \\
        \\    pub fn init(inner: *std.Io.Reader, buffer: []u8, should_cancel: ?*const fn () bool) CancelableReader {
        \\        return .{
        \\            .inner = inner,
        \\            .reader = .{
        \\                .buffer = buffer,
        \\                .seek = 0,
        \\                .end = 0,
        \\                .vtable = &vtable,
        \\            },
        \\            .should_cancel = should_cancel,
        \\        };
        \\    }
        \\
        \\    const vtable: std.Io.Reader.VTable = .{
        \\        .stream = stream,
        \\        .discard = std.Io.Reader.defaultDiscard,
        \\        .readVec = std.Io.Reader.defaultReadVec,
        \\        .rebase = std.Io.Reader.defaultRebase,
        \\    };
        \\
        \\    fn stream(ctx: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        \\        const self: *CancelableReader = @fieldParentPtr("reader", ctx);
        \\        if (self.should_cancel) |pred| {
        \\            if (pred()) return error.ReadFailed;
        \\        }
        \\        return self.inner.stream(w, limit);
        \\    }
        \\};
        \\
        \\pub fn parseSseBytes(allocator: std.mem.Allocator, bytes: []const u8, callback: anytype, cancellation_token: ?*CancellationToken) !void {
        \\    var reader: std.Io.Reader = .fixed(bytes);
        \\    try parseSseReader(allocator, &reader, callback, cancellation_token);
        \\}
        \\
        \\pub fn parseSseReader(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype, cancellation_token: ?*CancellationToken) !void {
        \\    var line_buf: std.Io.Writer.Allocating = .init(allocator);
        \\    defer line_buf.deinit();
        \\
        \\    var event_data: std.Io.Writer.Allocating = .init(allocator);
        \\    defer event_data.deinit();
        \\
        \\    while (true) {
        \\        try checkCancellation(cancellation_token);
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
        \\pub fn parseSseBytesTyped(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, callback: anytype, cancellation_token: ?*CancellationToken) !void {
        \\    const Callback = @TypeOf(callback.*);
        \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
        \\    try parseSseBytes(allocator, bytes, &typed_callback, cancellation_token);
        \\}
        \\
        \\pub fn parseSseReaderTyped(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype, cancellation_token: ?*CancellationToken) !void {
        \\    const Callback = @TypeOf(callback.*);
        \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
        \\    try parseSseReader(allocator, reader, &typed_callback, cancellation_token);
        \\}
        \\
    );
}

pub fn generateStreamAuthCode(self: *UnifiedApiGenerator) !void {
    if (self.has_streaming_operations) {
        try self.buffer.appendSlice(self.allocator,
            \\fn stringifyStreamRequest(allocator: std.mem.Allocator, requestBody: anytype) ![]u8 {
            \\    var buf: std.Io.Writer.Allocating = .init(allocator);
            \\    defer buf.deinit();
            \\    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &buf.writer);
            \\
            \\    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, buf.written(), .{ .ignore_unknown_fields = true });
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
            \\fn streamJsonTyped(comptime T: type, client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
            \\    return streamJsonTypedWithExtraHeaders(T, client, path, requestBody, callback, cancellation_token, &.{});
            \\}
            \\
            \\fn streamJsonTypedWithExtraHeaders(comptime T: type, client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken, extra_headers: []const std.http.Header) !void {
            \\    const Callback = @TypeOf(callback.*);
            \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = client.allocator, .callback = callback };
            \\    try streamJsonWithExtraHeaders(client, path, requestBody, &typed_callback, cancellation_token, extra_headers);
            \\}
            \\
            \\fn streamJson(client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
            \\    return streamJsonWithExtraHeaders(client, path, requestBody, callback, cancellation_token, &.{});
            \\}
            \\
            \\fn streamJsonWithExtraHeaders(client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken, extra_headers: []const std.http.Header) !void {
            \\    const allocator = client.allocator;
            \\    const payload = try stringifyStreamRequest(allocator, requestBody);
            \\    defer allocator.free(payload);
            \\
            \\    var headers = std.ArrayList(std.http.Header).empty;
            \\    defer headers.deinit(allocator);
            \\    try appendClientHeaders(allocator, &headers, client, "application/json", "text/event-stream");
            \\    for (extra_headers) |header| try appendOrReplaceHeader(allocator, &headers, header.name, header.value);
            \\
            \\    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client.base_url, path });
            \\    defer allocator.free(url);
            \\
            \\    if (client.http_observer) |obs| {
            \\        if (obs.onRequest) |cb| cb(obs.ctx, .POST, url, headers.items, payload);
            \\    }
            \\
            \\    const uri = try std.Uri.parse(url);
            \\    try checkCancellation(cancellation_token);
            \\
            \\    const start = std.Io.Clock.awake.now(client.io);
            \\    var req = client.http.request(.POST, uri, .{
            \\        .redirect_behavior = .unhandled,
            \\        .headers = .{ .accept_encoding = .{ .override = "identity" } },
            \\        .extra_headers = headers.items,
            \\    }) catch |err| {
            \\        if (client.http_observer) |obs| {
            \\            if (obs.onError) |cb| cb(obs.ctx, .POST, url, @errorName(err));
            \\        }
            \\        return err;
            \\    };
            \\    defer req.deinit();
            \\
            \\    req.transfer_encoding = .{ .content_length = payload.len };
            \\    var request_body = try req.sendBodyUnflushed(&.{});
            \\    try request_body.writer.writeAll(payload);
            \\    try request_body.end();
            \\    try req.connection.?.flush();
            \\    try checkCancellation(cancellation_token);
            \\
            \\    var response = req.receiveHead(&.{}) catch |err| {
            \\        if (client.http_observer) |obs| {
            \\            if (obs.onError) |cb| cb(obs.ctx, .POST, url, @errorName(err));
            \\        }
            \\        return err;
            \\    };
            \\    const elapsed_ns = @as(u64, @intCast(start.untilNow(client.io, .awake).nanoseconds));
            \\    if (response.head.status.class() != .success) {
            \\        if (client.http_observer) |obs| {
            \\            if (obs.onResponse) |cb| cb(obs.ctx, .POST, url, response.head.status, &.{}, "", elapsed_ns);
            \\        }
            \\        return error.ResponseError;
            \\    }
            \\
            \\    if (client.http_observer) |obs| {
            \\        if (obs.onResponse) |cb| cb(obs.ctx, .POST, url, response.head.status, &.{}, "", elapsed_ns);
            \\    }
            \\
            \\    var transfer_buffer: [8 * 1024]u8 = undefined;
            \\    const response_reader = response.reader(&transfer_buffer);
            \\    if (client.cancel_check) |pred| {
            \\        var done = std.atomic.Value(bool).init(false);
            \\        var watcher_ctx = Client.CancelWatcher{ .connection = req.connection, .io = client.io, .pred = pred, .done = &done };
            \\        const watcher_thread: ?std.Thread = std.Thread.spawn(.{}, Client.CancelWatcher.run, .{&watcher_ctx}) catch null;
            \\        defer if (watcher_thread) |thread| {
            \\            done.store(true, .release);
            \\            thread.join();
            \\            if (watcher_ctx.interrupted) {
            \\                const conn = watcher_ctx.connection.?;
            \\                if (comptime @import("builtin").os.tag == .windows) {
            \\                    if (watcher_ctx.replacement_handle) |handle| {
            \\                        conn.stream_reader.stream.socket.handle = handle;
            \\                        conn.stream_writer.stream.socket.handle = handle;
            \\                    }
            \\                }
            \\                conn.closing = true;
            \\            }
            \\        };
            \\        var cancelable_buffer: [1]u8 = undefined;
            \\        var cancelable_reader = CancelableReader.init(response_reader, &cancelable_buffer, pred);
            \\        parseSseReader(allocator, &cancelable_reader.reader, callback, cancellation_token) catch |err| switch (err) {
            \\            error.ReadFailed => {
            \\                if (pred()) return error.Cancelled;
            \\                return response.bodyErr() orelse err;
            \\            },
            \\            else => return err,
            \\        };
            \\    } else {
            \\        parseSseReader(allocator, response_reader, callback, cancellation_token) catch |err| switch (err) {
            \\            error.ReadFailed => return response.bodyErr() orelse err,
            \\            else => return err,
            \\        };
            \\    }
            \\}
            \\
        );
    }
    try self.buffer.appendSlice(self.allocator,
        \\fn appendClientHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), client: *Client, content_type: ?[]const u8, accept: []const u8) !void {
        \\    if (content_type) |ct| {
        \\        try headers.append(allocator, .{ .name = "Content-Type", .value = ct });
        \\    }
        \\    try headers.append(allocator, .{ .name = "Accept", .value = accept });
        \\    if (client.organization) |organization| {
        \\        try headers.append(allocator, .{ .name = "OpenAI-Organization", .value = organization });
        \\    }
        \\    if (client.project) |project| {
        \\        try headers.append(allocator, .{ .name = "OpenAI-Project", .value = project });
        \\    }
        \\    for (client.default_headers) |header| {
        \\        try headers.append(allocator, header);
        \\    }
        \\}
        \\
        \\
    );
}

pub fn generateSseBufferConstants(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator, "const max_sse_line_size = 256 * 1024;\nconst max_sse_event_size = 1024 * 1024;\n\n");
}

pub fn generateHttpObserverType(self: *UnifiedApiGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
        \\
        \\pub const HttpObserver = struct {
        \\    ctx: ?*anyopaque,
        \\    onRequest: ?*const fn (ctx: ?*anyopaque, method: std.http.Method, url: []const u8, headers: []const std.http.Header, body: ?[]const u8) void,
        \\    onResponse: ?*const fn (ctx: ?*anyopaque, method: std.http.Method, url: []const u8, status: std.http.Status, headers: []const std.http.Header, body: []const u8, duration_ns: u64) void,
        \\    onError: ?*const fn (ctx: ?*anyopaque, method: std.http.Method, url: []const u8, err_name: []const u8) void,
        \\};
        \\
    );
}
