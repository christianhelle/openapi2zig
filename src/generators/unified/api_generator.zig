const std = @import("std");
const cli = @import("../../cli.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../models/common/document.zig").Operation;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;
const Parameter = @import("../../models/common/document.zig").Parameter;
const media_type = @import("../../media_type.zig");
const ident = @import("ident_utils.zig");

const BodyKind = enum { none, json, binary, text, form };

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

fn escapeZigString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
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

fn classifyBody(content_type: ?[]const u8) BodyKind {
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

fn findBodyParam(operation: Operation) ?Parameter {
    if (operation.parameters) |params| {
        for (params) |p| {
            if (p.location == .body) return p;
        }
    }
    return null;
}

fn bodyKindFor(operation: Operation) BodyKind {
    const param = findBodyParam(operation) orelse return .none;
    return classifyBody(param.content_type);
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
    needs_alias: bool = false,
};

const TagClient = struct {
    name: []const u8,
    methods: std.ArrayList(OperationRef),
};

fn operationRefLessThan(_: void, lhs: OperationRef, rhs: OperationRef) bool {
    const path_order = std.mem.order(u8, lhs.path, rhs.path);
    if (path_order != .eq) return path_order == .lt;
    return std.mem.order(u8, lhs.method, rhs.method) == .lt;
}

fn tagClientLessThan(_: void, lhs: TagClient, rhs: TagClient) bool {
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}

fn toPascalCaseAlloc(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
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
    /// Reserved names of generated options struct types, keyed by operation id
    /// (or by path for operations without one). Options type names are
    /// disambiguated against every top-level declaration so generated clients
    /// always compile.
    options_type_names: std.StringHashMap([]const u8),
    /// Cached options struct field names, keyed by operation identity and
    /// parameter name/location. Populated on first use so repeated parameter
    /// references don't rescan the operation's parameter list.
    options_field_names: std.StringHashMap([]const u8),
    model_prefix: []const u8 = "",
    emit_imports: bool = true,
    models_import: []const u8 = "models.zig",
    models_import_alias: []const u8 = "models",
    runtime_import: []const u8 = "runtime.zig",
    runtime_import_alias: []const u8 = "runtime",

    pub fn init(allocator: std.mem.Allocator, args: cli.CliArgs) UnifiedApiGenerator {
        return UnifiedApiGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).empty,
            .args = args,
            .options_type_names = std.StringHashMap([]const u8).init(allocator),
            .options_field_names = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn clearOptionsTypeNames(self: *UnifiedApiGenerator, allocator: std.mem.Allocator) void {
        var iterator = self.options_type_names.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.options_type_names.clearRetainingCapacity();
    }

    fn clearOptionsFieldNames(self: *UnifiedApiGenerator, allocator: std.mem.Allocator) void {
        var iterator = self.options_field_names.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.options_field_names.clearRetainingCapacity();
    }

    pub fn deinit(self: *UnifiedApiGenerator) void {
        self.buffer.deinit(self.allocator);
        self.clearOptionsTypeNames(self.allocator);
        self.options_type_names.deinit();
        self.clearOptionsFieldNames(self.allocator);
        self.options_field_names.deinit();
    }

    pub fn generate(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        self.clearOptionsTypeNames(self.allocator);
        self.clearOptionsFieldNames(self.allocator);
        try self.generateHeader();
        try self.generateApiClient(document);
        if (self.args.resource_wrappers != .none) {
            try self.generateResourceWrappers(document);
        }
        if (self.args.multiple_clients == .per_tag) {
            try self.generateTagClients(document);
        }
        if (self.args.multiple_clients == .per_endpoint) {
            try self.generateEndpointClients(document);
        }
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    pub fn generateClientOnly(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        self.clearOptionsTypeNames(self.allocator);
        self.clearOptionsFieldNames(self.allocator);
        try self.generateHeaderMulti();
        try self.generateApiClient(document);
        if (self.args.resource_wrappers != .none) {
            try self.generateResourceWrappers(document);
        }
        if (self.args.multiple_clients == .per_tag) {
            try self.generateTagClients(document);
        }
        if (self.args.multiple_clients == .per_endpoint) {
            try self.generateEndpointClients(document);
        }
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn appendIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        try ident.appendIdentifier(&self.buffer, self.allocator, name);
    }

    fn appendFieldIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        try ident.appendFieldIdentifier(&self.buffer, self.allocator, name);
    }

    fn appendEscapedIdentifier(self: *UnifiedApiGenerator, name: []const u8) !void {
        try ident.appendEscapedIdentifier(&self.buffer, self.allocator, name);
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
        try self.generateRuntimePreamble();
        try self.generateClientPreamble();
        try self.generateSsePreamble();
        try self.generateSseBufferConstants();
    }

    fn generateHeaderMulti(self: *UnifiedApiGenerator) !void {
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

    fn generateRuntimePreamble(self: *UnifiedApiGenerator) !void {
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

    fn generateRuntimeReexports(self: *UnifiedApiGenerator) !void {
        const alias = self.runtime_import_alias;
        const exports = try std.fmt.allocPrint(self.allocator,
            \\const Owned = {s}.Owned;
            \\const HttpObserver = {s}.HttpObserver;
            \\const RawResponse = {s}.RawResponse;
            \\const ParseErrorResponse = {s}.ParseErrorResponse;
            \\const ApiResult = {s}.ApiResult;
            \\const CancellationToken = {s}.CancellationToken;
            \\const checkCancellation = {s}.checkCancellation;
            \\const parseSseReader = {s}.parseSseReader;
            \\const parseSseBytes = {s}.parseSseBytes;
            \\const parseSseBytesTyped = {s}.parseSseBytesTyped;
            \\const parseSseReaderTyped = {s}.parseSseReaderTyped;
            \\const TypedSseCallback = {s}.TypedSseCallback;
            \\
        , .{ alias, alias, alias, alias, alias, alias, alias, alias, alias, alias, alias, alias });
        defer self.allocator.free(exports);
        try self.buffer.appendSlice(self.allocator, exports);
    }

    fn generateClientPreamble(self: *UnifiedApiGenerator) !void {
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
            \\    return requestRawWithContentType(client, method, url, payload, "application/json");
            \\}
            \\
            \\pub fn requestRawWithContentType(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8, content_type_value: []const u8) !RawResponse {
            \\    const allocator = client.allocator;
            \\    var headers = std.ArrayList(std.http.Header).empty;
            \\    defer headers.deinit(allocator);
            \\    const content_type: ?[]const u8 = if (payload != null) content_type_value else null;
            \\    const auth_header = try appendClientHeaders(allocator, &headers, client, content_type, "application/json");
            \\    defer if (auth_header) |value| allocator.free(value);
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

    fn generateSsePreamble(self: *UnifiedApiGenerator) !void {
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

    fn generateStreamAuthCode(self: *UnifiedApiGenerator) !void {
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
            \\    const Callback = @TypeOf(callback.*);
            \\    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = client.allocator, .callback = callback };
            \\    try streamJson(client, path, requestBody, &typed_callback, cancellation_token);
            \\}
            \\
            \\fn streamJson(client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
            \\    const allocator = client.allocator;
            \\    const payload = try stringifyStreamRequest(allocator, requestBody);
            \\    defer allocator.free(payload);
            \\
            \\    var headers = std.ArrayList(std.http.Header).empty;
            \\    defer headers.deinit(allocator);
            \\    const auth_header = try appendClientHeaders(allocator, &headers, client, "application/json", "text/event-stream");
            \\    defer if (auth_header) |value| allocator.free(value);
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
            \\    const reader = response.reader(&transfer_buffer);
            \\    parseSseReader(allocator, reader, callback, cancellation_token) catch |err| switch (err) {
            \\        error.ReadFailed => return response.bodyErr() orelse err,
            \\        else => return err,
            \\    };
            \\}
            \\
            \\fn appendClientHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), client: *Client, content_type: ?[]const u8, accept: []const u8) !?[]u8 {
            \\    if (content_type) |ct| {
            \\        try headers.append(allocator, .{ .name = "Content-Type", .value = ct });
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

    fn generateSseBufferConstants(self: *UnifiedApiGenerator) !void {
        try self.buffer.appendSlice(self.allocator, "const max_sse_line_size = 256 * 1024;\nconst max_sse_event_size = 1024 * 1024;\n\n");
    }

    fn generateHttpObserverType(self: *UnifiedApiGenerator) !void {
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

    fn generateApiClient(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;
            try self.generateOperations(path, path_item, document);
        }
    }

    fn generateOperations(self: *UnifiedApiGenerator, path: []const u8, path_item: @import("../../models/common/document.zig").PathItem, document: UnifiedDocument) !void {
        if (path_item.get) |op| try self.generateOperation("GET", path, op, document);
        if (path_item.post) |op| try self.generateOperation("POST", path, op, document);
        if (path_item.put) |op| try self.generateOperation("PUT", path, op, document);
        if (path_item.delete) |op| try self.generateOperation("DELETE", path, op, document);
        if (path_item.patch) |op| try self.generateOperation("PATCH", path, op, document);
        if (path_item.head) |op| try self.generateOperation("HEAD", path, op, document);
        if (path_item.options) |op| try self.generateOperation("OPTIONS", path, op, document);
    }

    fn generateOperation(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation, document: UnifiedDocument) !void {
        try self.generateComments(operation);
        try self.generateOptionsType(operation, method, path, document);
        try self.generateFunctionSignature(method, path, operation);
        try self.generateFunctionBody(method, path, operation);
        if (operation.operationId != null) {
            try self.generateFunctionRaw(method, path, operation);
        }
        if (operation.operationId != null and self.hasReturnValue(method, operation)) {
            try self.generateFunctionResult(method, path, operation);
        }

        if (operation.streaming and std.mem.eql(u8, method, "POST")) {
            if (operation.operationId) |op_id| {
                const stream_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{op_id});
                defer self.allocator.free(stream_name);
                try self.generateStreamFunction(stream_name, path);
            }
        }
    }

    fn generateFunctionResult(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
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

    fn generateFunctionRaw(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
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

        switch (kind) {
            .json => {
                const json_ct: []const u8 = if (findBodyParam(operation)) |bp| (bp.content_type orelse "application/json") else "application/json";
                try self.buffer.appendSlice(self.allocator, "\n    var str: std.Io.Writer.Allocating = .init(allocator);\n");
                try self.buffer.appendSlice(self.allocator, "    defer str.deinit();\n");
                try self.buffer.appendSlice(self.allocator, "    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);\n");
                try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = str.written();\n");
                if (std.mem.eql(u8, json_ct, "application/json")) {
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
                try self.buffer.appendSlice(self.allocator, "\n    return requestRaw(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload);\n");
                try self.buffer.appendSlice(self.allocator, "}\n\n");
                return;
            },
            .none => {
                try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = null;\n");
                try self.buffer.appendSlice(self.allocator, "\n    return requestRaw(client, std.http.Method.");
                try self.buffer.appendSlice(self.allocator, method);
                try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), payload);\n");
                try self.buffer.appendSlice(self.allocator, "}\n\n");
                return;
            },
            .binary, .text => {},
        }

        const body_param = findBodyParam(operation) orelse unreachable;
        const ct = body_param.content_type orelse "application/octet-stream";
        try self.buffer.appendSlice(self.allocator, "    const payload: ?[]const u8 = requestBody;\n");
        try self.buffer.appendSlice(self.allocator, "\n    var headers = std.ArrayList(std.http.Header).empty;\n");
        try self.buffer.appendSlice(self.allocator, "    defer headers.deinit(allocator);\n");
        try self.buffer.appendSlice(self.allocator, "    const auth_header = try appendClientHeaders(allocator, &headers, client, \"");
        try self.buffer.appendSlice(self.allocator, ct);
        try self.buffer.appendSlice(self.allocator, "\", \"application/json\");\n");
        try self.buffer.appendSlice(self.allocator, "    defer if (auth_header) |value| allocator.free(value);\n");
        try self.buffer.appendSlice(self.allocator, "\n    if (client.http_observer) |obs| {\n");
        try self.buffer.appendSlice(self.allocator, "        if (obs.onRequest) |cb| cb(obs.ctx, std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), headers.items, payload);\n");
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
        try self.buffer.appendSlice(self.allocator, "        .extra_headers = headers.items,\n");
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

    fn appendFlatCallArguments(self: *UnifiedApiGenerator, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "(client");
        if (operation.parameters) |params| {
            if (self.args.parameters_as_struct) {
                for (params) |param| {
                    if (param.location == .body) continue;
                    try self.buffer.appendSlice(self.allocator, ", options");
                    break;
                }
            }
            for (params) |param| {
                if (self.args.parameters_as_struct and param.location != .body) continue;
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
            }
        }
        try self.buffer.appendSlice(self.allocator, ")");
    }

    /// Emit the base Zig type for a parameter, without the optional prefix or
    /// null default that callers may add.
    fn appendParamBaseType(self: *UnifiedApiGenerator, param: Parameter) !void {
        if (param.location == .body) {
            const kind = classifyBody(param.content_type);
            if (kind == .binary or kind == .text) {
                try self.buffer.appendSlice(self.allocator, "[]const u8");
            } else if (param.schema) |schema| {
                try self.appendZigTypeFromSchema(schema);
            } else {
                try self.buffer.appendSlice(self.allocator, "std.json.Value");
            }
        } else {
            if (param.schema) |schema| {
                try self.appendZigQueryTypeFromSchema(schema);
            } else if (param.type) |param_type| {
                try self.appendZigTypeFromSchemaType(param_type);
            } else {
                try self.buffer.appendSlice(self.allocator, "[]const u8");
            }
        }
    }

    /// Emit the `options` struct parameter wrapping all non-body parameters of
    /// an operation. Optional parameters become nullable fields with a `null`
    /// default; required parameters stay non-optional.
    fn appendOptionsParam(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
        var count: usize = 0;
        if (operation.parameters) |params| {
            for (params) |param| {
                if (param.location != .body) count += 1;
            }
        }
        if (count == 0) return;

        try self.buffer.appendSlice(self.allocator, ", options: ");
        try self.appendOptionsTypeName(operation, method, path);
    }

    /// Build the map key identifying an operation in options_type_names.
    /// Operation ids are namespaced separately from path-based fallback keys,
    /// and the HTTP method disambiguates fallback operations sharing a path,
    /// so distinct operations can never overwrite one another's entry.
    fn optionsTypeKeyAlloc(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) ![]const u8 {
        if (operation.operationId) |op_id| {
            return try std.fmt.allocPrint(self.allocator, "op:{s}", .{op_id});
        }
        return try std.fmt.allocPrint(self.allocator, "path:{s}:{s}", .{ method, path });
    }

    /// Emit the name of the options struct type for an operation. The name
    /// derives from the operation id so all functions of an operation share
    /// the same type; operations without an operation id use the same fallback
    /// as the flat function name, derived from the operation path. The name is
    /// reserved by generateOptionsType so every variant references the same
    /// disambiguated type.
    fn appendOptionsTypeName(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
        const key = try self.optionsTypeKeyAlloc(operation, method, path);
        defer self.allocator.free(key);
        if (self.options_type_names.get(key)) |name| {
            if (operation.operationId == null) {
                try self.appendEscapedIdentifier(name);
            } else {
                try self.appendIdentifier(name);
            }
            return;
        }
        try self.appendRawOptionsTypeName(operation, path);
    }

    fn appendRawOptionsTypeName(self: *UnifiedApiGenerator, operation: Operation, path: []const u8) !void {
        if (operation.operationId) |op_id| {
            const name = try std.fmt.allocPrint(self.allocator, "{s}Options", .{op_id});
            defer self.allocator.free(name);
            try self.appendIdentifier(name);
        } else {
            const name = try std.fmt.allocPrint(self.allocator, "operation{s}Options", .{path[1..]});
            defer self.allocator.free(name);
            try self.appendEscapedIdentifier(name);
        }
    }

    /// Emit a top-level declaration of the options struct type for an
    /// operation when parameters-as-struct is enabled and the operation has
    /// non-body parameters. The type name is reserved so it never collides
    /// with operation names, schemas, or runtime declarations.
    fn generateOptionsType(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, document: UnifiedDocument) !void {
        if (!self.args.parameters_as_struct) return;
        var count: usize = 0;
        if (operation.parameters) |params| {
            for (params) |param| {
                if (param.location != .body) count += 1;
            }
        }
        if (count == 0) return;

        var candidate = if (operation.operationId) |op_id|
            try std.fmt.allocPrint(self.allocator, "{s}Options", .{op_id})
        else
            try std.fmt.allocPrint(self.allocator, "operation{s}Options", .{path[1..]});
        defer self.allocator.free(candidate);
        while (self.topLevelNameConflicts(candidate, document)) {
            const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
            self.allocator.free(candidate);
            candidate = suffixed;
        }
        const key = try self.optionsTypeKeyAlloc(operation, method, path);
        defer self.allocator.free(key);
        if (self.options_type_names.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
        {
            const key_copy_ = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_copy_);
            const candidate_copy_ = try self.allocator.dupe(u8, candidate);
            errdefer self.allocator.free(candidate_copy_);
            try self.options_type_names.put(key_copy_, candidate_copy_);
        }

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendOptionsTypeName(operation, method, path);
        try self.buffer.appendSlice(self.allocator, " = struct {\n");
        if (operation.parameters) |params| {
            for (params, 0..) |param, i| {
                if (param.location == .body) continue;
                const field_name = try self.optionsFieldNameAlloc(operation, method, path, i);
                defer self.allocator.free(field_name);
                try self.buffer.appendSlice(self.allocator, "    ");
                try self.appendFieldIdentifier(field_name);
                try self.buffer.appendSlice(self.allocator, ": ");
                const optional = param.location != .path and !param.required;
                if (optional) try self.buffer.appendSlice(self.allocator, "?");
                try self.appendParamBaseType(param);
                if (optional) try self.buffer.appendSlice(self.allocator, " = null");
                try self.buffer.appendSlice(self.allocator, ",\n");
            }
        }
        try self.buffer.appendSlice(self.allocator, "};\n\n");
    }

    /// Emit individual `requestBody` arguments for body parameters, used after
    /// the `options` struct when parameters-as-struct is enabled.
    fn appendBodyParams(self: *UnifiedApiGenerator, params: []Parameter) !void {
        for (params) |param| {
            if (param.location != .body) continue;
            try self.buffer.appendSlice(self.allocator, ", requestBody: ");
            try self.appendParamBaseType(param);
        }
    }

    /// Compute the field name of a parameter in the options struct. When the
    /// escaped name collides with an earlier parameter, a numeric suffix is
    /// appended so generated structs never declare duplicate fields.
    /// Field-identifier escaping is injective, so comparing raw names is
    /// equivalent to comparing escaped names. Results are cached so repeated
    /// references don't rescan the operation's parameter list. `index` is the
    /// parameter's position in `operation.parameters` and uniquely identifies
    /// it, so parameters sharing a name and location never share a cache entry.
    fn optionsFieldNameAlloc(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, index: usize) ![]const u8 {
        const memo_key = try self.optionsFieldNameKeyAlloc(operation, method, path, index);
        defer self.allocator.free(memo_key);
        if (self.options_field_names.get(memo_key)) |cached| {
            return try self.allocator.dupe(u8, cached);
        }
        const field_name = try self.computeOptionsFieldName(operation, index);
        errdefer self.allocator.free(field_name);
        {
            const memo_key_copy_ = try self.allocator.dupe(u8, memo_key);
            errdefer self.allocator.free(memo_key_copy_);
            const field_name_copy_ = try self.allocator.dupe(u8, field_name);
            errdefer self.allocator.free(field_name_copy_);
            try self.options_field_names.put(memo_key_copy_, field_name_copy_);
        }
        return field_name;
    }

    /// Build the cache key identifying a parameter within an operation for
    /// options_field_names. The operation key disambiguates operations, and
    /// the index uniquely identifies the parameter within one.
    fn optionsFieldNameKeyAlloc(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, index: usize) ![]const u8 {
        const op_key = try self.optionsTypeKeyAlloc(operation, method, path);
        defer self.allocator.free(op_key);
        return try std.fmt.allocPrint(self.allocator, "{s}\x1f{d}", .{ op_key, index });
    }

    /// Scan an operation's non-body parameters to resolve the disambiguated
    /// field name of the parameter at `index`. A numeric suffix is appended
    /// when the natural name is already taken by an earlier parameter or is
    /// any other parameter's original name, so generated structs never declare
    /// duplicate fields. Field-identifier escaping is injective, so comparing
    /// raw names is equivalent to comparing escaped names.
    fn computeOptionsFieldName(self: *UnifiedApiGenerator, operation: Operation, index: usize) ![]const u8 {
        var used = std.StringHashMap(void).init(self.allocator);
        var reserved = std.StringHashMap(void).init(self.allocator);
        var allocated = std.ArrayList([]const u8).empty;
        defer {
            for (allocated.items) |item| self.allocator.free(item);
            allocated.deinit(self.allocator);
            used.deinit();
            reserved.deinit();
        }
        if (operation.parameters) |params| {
            for (params) |p| {
                if (p.location == .body) continue;
                try reserved.put(p.name, {});
            }
            for (params, 0..) |p, i| {
                if (p.location == .body) continue;
                var name = p.name;
                var counter: usize = 0;
                while (used.contains(name) or (reserved.contains(name) and !std.mem.eql(u8, name, p.name))) {
                    counter += 1;
                    const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ p.name, counter });
                    try allocated.append(self.allocator, suffixed);
                    name = suffixed;
                }
                if (i == index) return try self.allocator.dupe(u8, name);
                try used.put(name, {});
            }
        }
        return try self.allocator.dupe(u8, if (operation.parameters) |params| params[index].name else "");
    }

    /// Emit a reference to a parameter argument. In parameters-as-struct mode
    /// the value lives in the `options` struct and must use field escaping and
    /// duplicate-name disambiguation.
    fn appendParamReference(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, index: usize, parameter: Parameter) !void {
        if (self.args.parameters_as_struct) {
            const field_name = try self.optionsFieldNameAlloc(operation, method, path, index);
            defer self.allocator.free(field_name);
            try self.buffer.appendSlice(self.allocator, "options.");
            try self.appendFieldIdentifier(field_name);
        } else {
            try self.appendIdentifier(parameter.name);
        }
    }

    fn appendFlatOperationParameters(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
        if (operation.parameters) |params| {
            if (self.args.parameters_as_struct) {
                try self.appendOptionsParam(operation, method, path);
                try self.appendBodyParams(params);
                return;
            }
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
                try self.buffer.appendSlice(self.allocator, ": ");
                if (param.location == .query and !param.required) try self.buffer.appendSlice(self.allocator, "?");
                try self.appendParamBaseType(param);
            }
        }
    }

    fn appendUnusedParameters(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
        if (operation.parameters) |parameters| {
            for (parameters, 0..) |parameter, i| {
                if (parameter.location != .path and parameter.location != .body and parameter.location != .query) {
                    try self.buffer.appendSlice(self.allocator, "    _ = ");
                    try self.appendParamReference(operation, method, path, i, parameter);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                }
            }
        }
    }

    fn appendUrlConstruction(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
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

    fn generateStreamFunction(self: *UnifiedApiGenerator, name: []const u8, path: []const u8) !void {
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

        // Detect when wrapper method name matches its containing struct name
        // or when the derived method name equals the operation id (ambiguous reference)
        for (wrappers.items) |*wrapper| {
            const last_segment = wrapper.segments[wrapper.segments.len - 1];
            if (std.mem.eql(u8, wrapper.method_name, last_segment) or std.mem.eql(u8, wrapper.method_name, wrapper.operation_id)) {
                wrapper.collides = true;
                wrapper.needs_alias = true;
            }
        }

        // Generate aliases for operations whose wrapper needs them
        for (wrappers.items) |wrapper| {
            if (wrapper.needs_alias) {
                const alias_line = try std.fmt.allocPrint(self.allocator, "const _{s} = {s};\n", .{ wrapper.operation_id, wrapper.operation_id });
                defer self.allocator.free(alias_line);
                try self.buffer.appendSlice(self.allocator, alias_line);
                if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                    const result_line = try std.fmt.allocPrint(self.allocator, "const _{s}Result = {s}Result;\n", .{ wrapper.operation_id, wrapper.operation_id });
                    defer self.allocator.free(result_line);
                    try self.buffer.appendSlice(self.allocator, result_line);
                }
            }
        }
        if (wrappers.items.len > 0) try self.buffer.appendSlice(self.allocator, "\n");

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

    fn generateTagClients(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
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

        var groups = std.ArrayList(TagClient).empty;
        defer {
            for (groups.items) |*group| {
                self.allocator.free(group.name);
                group.methods.deinit(self.allocator);
            }
            groups.deinit(self.allocator);
        }

        for (operations.items) |op_ref| {
            const struct_name = try self.tagClientNameAlloc(op_ref.operation);

            var group_index: ?usize = null;
            for (groups.items, 0..) |group, i| {
                if (std.mem.eql(u8, group.name, struct_name)) {
                    group_index = i;
                    break;
                }
            }

            if (group_index) |idx| {
                self.allocator.free(struct_name);
                try groups.items[idx].methods.append(self.allocator, op_ref);
            } else {
                errdefer self.allocator.free(struct_name);
                var methods = std.ArrayList(OperationRef).empty;
                errdefer methods.deinit(self.allocator);
                try methods.append(self.allocator, op_ref);
                try groups.append(self.allocator, .{ .name = struct_name, .methods = methods });
            }
        }

        std.mem.sort(TagClient, groups.items, {}, tagClientLessThan);

        // Emit file-scope aliases for operations whose tag-client method name
        // matches the flat function it delegates to. Without the alias, the
        // unqualified call inside the method (e.g. `return listPets(self.client)`)
        // is an ambiguous reference between the struct method and the flat fn.
        var alias_count: usize = 0;
        for (operations.items) |op_ref| {
            const op_id = op_ref.operation.operationId orelse continue;
            const prospective = try self.tagClientMethodNameAlloc(op_id);
            defer self.allocator.free(prospective);
            if (!std.mem.eql(u8, prospective, op_id)) continue;

            // The alias target is the flat function name, which may be a Zig
            // keyword (e.g. operationId "if" → @"if") and so must be quoted.
            const main_alias = try std.fmt.allocPrint(self.allocator, "const _{s} = ", .{op_id});
            defer self.allocator.free(main_alias);
            try self.buffer.appendSlice(self.allocator, main_alias);
            try self.appendIdentifier(op_id);
            try self.buffer.appendSlice(self.allocator, ";\n");
            const raw_alias = try std.fmt.allocPrint(self.allocator, "const _{s}Raw = {s}Raw;\n", .{ op_id, op_id });
            defer self.allocator.free(raw_alias);
            try self.buffer.appendSlice(self.allocator, raw_alias);
            if (self.hasReturnValue(op_ref.method, op_ref.operation)) {
                const result_alias = try std.fmt.allocPrint(self.allocator, "const _{s}Result = {s}Result;\n", .{ op_id, op_id });
                defer self.allocator.free(result_alias);
                try self.buffer.appendSlice(self.allocator, result_alias);
            }
            if (op_ref.operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
                const stream_alias = try std.fmt.allocPrint(self.allocator, "const _{s}Streaming = {s}Streaming;\n", .{ op_id, op_id });
                defer self.allocator.free(stream_alias);
                try self.buffer.appendSlice(self.allocator, stream_alias);
            }
            alias_count += 1;
        }
        if (alias_count > 0) try self.buffer.appendSlice(self.allocator, "\n");

        var used_struct_names = std.StringHashMap(void).init(self.allocator);
        defer {
            var name_iterator = used_struct_names.keyIterator();
            while (name_iterator.next()) |key| self.allocator.free(key.*);
            used_struct_names.deinit();
        }

        for (groups.items) |group| {
            const struct_name = try self.uniqueTagClientStructNameAlloc(group.name, document, used_struct_names);
            used_struct_names.put(struct_name, {}) catch {
                self.allocator.free(struct_name);
                return error.OutOfMemory;
            };

            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.buffer.appendSlice(self.allocator, " = struct {\n");
            try self.buffer.appendSlice(self.allocator, "    client: *Client,\n\n");
            try self.buffer.appendSlice(self.allocator, "    pub fn init(client: *Client) ");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.buffer.appendSlice(self.allocator, " {\n");
            try self.buffer.appendSlice(self.allocator, "        return .{ .client = client };\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");

            var used_method_names = std.StringHashMap(void).init(self.allocator);
            defer {
                var method_iterator = used_method_names.keyIterator();
                while (method_iterator.next()) |key| self.allocator.free(key.*);
                used_method_names.deinit();
            }

            for (group.methods.items) |op_ref| {
                const method_name = try self.uniqueTagClientMethodNameAlloc(op_ref, used_method_names);
                try self.registerTagClientMethodNames(method_name, op_ref, &used_method_names);
                try self.generateTagClientMethod(struct_name, method_name, op_ref);
            }

            try self.buffer.appendSlice(self.allocator, "};\n\n");
        }
    }

    fn generateEndpointClients(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
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

        var used_struct_names = std.StringHashMap(void).init(self.allocator);
        defer {
            var name_iterator = used_struct_names.keyIterator();
            while (name_iterator.next()) |key| self.allocator.free(key.*);
            used_struct_names.deinit();
        }

        for (operations.items) |op_ref| {
            const struct_name = try self.endpointClientNameAlloc(op_ref, document, used_struct_names);
            used_struct_names.put(struct_name, {}) catch {
                self.allocator.free(struct_name);
                return error.OutOfMemory;
            };
            try self.generateEndpointClient(struct_name, op_ref);
        }
    }

    fn endpointFallbackNameAlloc(self: *UnifiedApiGenerator, method: []const u8, path: []const u8) ![]const u8 {
        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(self.allocator);
        for (method) |c| try combined.append(self.allocator, std.ascii.toLower(c));
        try combined.appendSlice(self.allocator, path);
        return toPascalCaseAlloc(self.allocator, combined.items);
    }

    fn endpointClientNameAlloc(self: *UnifiedApiGenerator, op_ref: OperationRef, document: UnifiedDocument, used_names: std.StringHashMap(void)) ![]const u8 {
        var candidate = if (op_ref.operation.operationId) |op_id|
            try toPascalCaseAlloc(self.allocator, op_id)
        else
            try self.endpointFallbackNameAlloc(op_ref.method, op_ref.path);
        errdefer self.allocator.free(candidate);
        while (self.topLevelNameConflicts(candidate, document) or used_names.contains(candidate)) {
            const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
            self.allocator.free(candidate);
            candidate = suffixed;
        }
        return candidate;
    }

    fn generateEndpointClient(self: *UnifiedApiGenerator, struct_name: []const u8, op_ref: OperationRef) !void {
        const method = op_ref.method;
        const operation = op_ref.operation;
        const has_return = self.hasReturnValue(method, operation);

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.buffer.appendSlice(self.allocator, " = struct {\n");
        try self.buffer.appendSlice(self.allocator, "    client: *Client,\n\n");
        try self.buffer.appendSlice(self.allocator, "    pub fn init(client: *Client) ");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.buffer.appendSlice(self.allocator, "        return .{ .client = client };\n");
        try self.buffer.appendSlice(self.allocator, "    }\n\n");

        try self.buffer.appendSlice(self.allocator, "    pub fn execute(self: *");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
        if (has_return) {
            try self.buffer.appendSlice(self.allocator, ") !Owned(");
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ") {\n");
        } else {
            try self.buffer.appendSlice(self.allocator, ") !void {\n");
        }
        try self.buffer.appendSlice(self.allocator, "        return ");
        if (operation.operationId) |op_id| {
            try self.appendIdentifier(op_id);
        } else {
            try self.buffer.appendSlice(self.allocator, "@\"operation");
            try self.buffer.appendSlice(self.allocator, op_ref.path[1..]);
            try self.buffer.appendSlice(self.allocator, "\"");
        }
        try self.appendTagClientCallArguments(operation);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.buffer.appendSlice(self.allocator, "    }\n\n");

        if (operation.operationId) |op_id| {
            const raw_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{op_id});
            defer self.allocator.free(raw_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn executeRaw(self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
            try self.buffer.appendSlice(self.allocator, ") !RawResponse {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            try self.appendIdentifier(raw_operation_name);
            try self.appendTagClientCallArguments(operation);
            try self.buffer.appendSlice(self.allocator, ";\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");

            if (has_return) {
                const result_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{op_id});
                defer self.allocator.free(result_operation_name);

                try self.buffer.appendSlice(self.allocator, "    pub fn executeResult(self: *");
                try self.buffer.appendSlice(self.allocator, struct_name);
                try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
                try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
                try self.appendReturnType(method, operation);
                try self.buffer.appendSlice(self.allocator, ") {\n");
                try self.buffer.appendSlice(self.allocator, "        return ");
                try self.appendIdentifier(result_operation_name);
                try self.appendTagClientCallArguments(operation);
                try self.buffer.appendSlice(self.allocator, ";\n");
                try self.buffer.appendSlice(self.allocator, "    }\n\n");
            }

            if (operation.streaming and std.mem.eql(u8, method, "POST")) {
                const stream_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{op_id});
                defer self.allocator.free(stream_operation_name);

                try self.buffer.appendSlice(self.allocator, "    pub fn executeStreaming(self: *");
                try self.buffer.appendSlice(self.allocator, struct_name);
                try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
                try self.buffer.appendSlice(self.allocator, "        return ");
                try self.appendIdentifier(stream_operation_name);
                try self.buffer.appendSlice(self.allocator, "(self.client, requestBody, callback, cancellation_token);\n");
                try self.buffer.appendSlice(self.allocator, "    }\n\n");

                const stream_events_operation_name = try std.fmt.allocPrint(self.allocator, "{s}StreamingEvents", .{op_id});
                defer self.allocator.free(stream_events_operation_name);

                try self.buffer.appendSlice(self.allocator, "    pub fn executeStreamingEvents(comptime Event: type, self: *");
                try self.buffer.appendSlice(self.allocator, struct_name);
                try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
                try self.buffer.appendSlice(self.allocator, "        return ");
                try self.appendIdentifier(stream_events_operation_name);
                try self.buffer.appendSlice(self.allocator, "(Event, self.client, requestBody, callback, cancellation_token);\n");
                try self.buffer.appendSlice(self.allocator, "    }\n\n");
            }
        }

        try self.buffer.appendSlice(self.allocator, "};\n\n");
    }

    fn topLevelNameConflicts(self: *UnifiedApiGenerator, name: []const u8, document: UnifiedDocument) bool {
        const runtime_names = [_][]const u8{
            "Client",        "Owned",                     "RawResponse",        "ParseErrorResponse",  "ApiResult",        "HttpObserver",  "CancellationToken",
            "requestRaw",    "requestRawWithContentType", "getRaw",             "postJsonRaw",         "parseRawResponse", "getJsonResult", "postJsonResult",
            "parseSseBytes", "parseSseReader",            "parseSseBytesTyped", "parseSseReaderTyped",
        };
        for (runtime_names) |runtime_name| {
            if (std.mem.eql(u8, name, runtime_name)) return true;
        }

        var options_iterator = self.options_type_names.valueIterator();
        while (options_iterator.next()) |options_name| {
            if (std.mem.eql(u8, options_name.*, name)) return true;
        }

        if (document.schemas) |schemas| {
            var schema_iterator = schemas.iterator();
            while (schema_iterator.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, name)) return true;
            }
        }

        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path_item = entry.value_ptr.*;
            if (operationDeclaresTopLevelName(self, path_item.get, "GET", name)) return true;
            if (operationDeclaresTopLevelName(self, path_item.post, "POST", name)) return true;
            if (operationDeclaresTopLevelName(self, path_item.put, "PUT", name)) return true;
            if (operationDeclaresTopLevelName(self, path_item.delete, "DELETE", name)) return true;
            if (operationDeclaresTopLevelName(self, path_item.patch, "PATCH", name)) return true;
            if (operationDeclaresTopLevelName(self, path_item.head, "HEAD", name)) return true;
            if (operationDeclaresTopLevelName(self, path_item.options, "OPTIONS", name)) return true;
        }
        return false;
    }

    fn uniqueTagClientStructNameAlloc(self: *UnifiedApiGenerator, name: []const u8, document: UnifiedDocument, used_names: std.StringHashMap(void)) ![]const u8 {
        var candidate = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(candidate);
        while (self.topLevelNameConflicts(candidate, document) or used_names.contains(candidate)) {
            const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
            self.allocator.free(candidate);
            candidate = suffixed;
        }
        return candidate;
    }

    fn isReservedTagClientMethod(name: []const u8) bool {
        return ident.isReservedIdent(name) or
            std.mem.eql(u8, name, "init") or
            std.mem.eql(u8, name, "client") or
            std.mem.eql(u8, name, "deinit");
    }

    fn uniqueTagClientMethodNameAlloc(self: *UnifiedApiGenerator, op_ref: OperationRef, used_names: std.StringHashMap(void)) ![]const u8 {
        var candidate = if (op_ref.operation.operationId) |op_id|
            try self.tagClientMethodNameAlloc(op_id)
        else
            try self.tagClientFallbackMethodNameAlloc(op_ref);
        errdefer self.allocator.free(candidate);
        while (try self.tagClientMethodNamesCollide(candidate, op_ref, used_names)) {
            const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
            self.allocator.free(candidate);
            candidate = suffixed;
        }
        return candidate;
    }

    // True when any struct member name the tag-client method for op_ref emits
    // (the main name plus its Raw/Result/Streaming variants) collides with a
    // name already claimed by a sibling method or a reserved identifier.
    fn tagClientMethodNamesCollide(self: *UnifiedApiGenerator, candidate: []const u8, op_ref: OperationRef, used_names: std.StringHashMap(void)) !bool {
        if (isReservedTagClientMethod(candidate) or used_names.contains(candidate)) return true;
        if (op_ref.operation.operationId == null) return false;

        const raw = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{candidate});
        defer self.allocator.free(raw);
        if (used_names.contains(raw)) return true;

        if (self.hasReturnValue(op_ref.method, op_ref.operation)) {
            const result = try std.fmt.allocPrint(self.allocator, "{s}Result", .{candidate});
            defer self.allocator.free(result);
            if (used_names.contains(result)) return true;
        }
        if (op_ref.operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
            const streaming = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{candidate});
            defer self.allocator.free(streaming);
            if (used_names.contains(streaming)) return true;
            const stream_events = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{candidate});
            defer self.allocator.free(stream_events);
            if (used_names.contains(stream_events)) return true;
        }
        return false;
    }

    // Registers every struct member name the tag-client method for op_ref will
    // emit, transferring ownership of each to used_names.
    fn registerTagClientMethodNames(self: *UnifiedApiGenerator, method_name: []const u8, op_ref: OperationRef, used_names: *std.StringHashMap(void)) !void {
        try self.registerTagClientMethodName(method_name, used_names);
        if (op_ref.operation.operationId == null) return;

        try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}Raw", .{method_name}), used_names);
        if (self.hasReturnValue(op_ref.method, op_ref.operation)) {
            try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}Result", .{method_name}), used_names);
        }
        if (op_ref.operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
            try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{method_name}), used_names);
            try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{method_name}), used_names);
        }
    }

    fn registerTagClientMethodName(self: *UnifiedApiGenerator, name: []const u8, used_names: *std.StringHashMap(void)) !void {
        used_names.put(name, {}) catch {
            self.allocator.free(name);
            return error.OutOfMemory;
        };
    }

    fn tagClientFallbackMethodNameAlloc(self: *UnifiedApiGenerator, op_ref: OperationRef) ![]const u8 {
        const pascal = try self.endpointFallbackNameAlloc(op_ref.method, op_ref.path);
        defer self.allocator.free(pascal);
        const method = try self.allocator.dupe(u8, pascal);
        if (method.len > 0) method[0] = std.ascii.toLower(method[0]);
        return method;
    }

    fn tagClientNameAlloc(self: *UnifiedApiGenerator, operation: Operation) ![]const u8 {
        const tag: []const u8 = if (operation.tags) |tags| (if (tags.len > 0) tags[0] else "") else "";
        if (tag.len == 0) return try self.allocator.dupe(u8, "DefaultClient");
        const pascal = try toPascalCaseAlloc(self.allocator, tag);
        defer self.allocator.free(pascal);
        return try std.fmt.allocPrint(self.allocator, "{s}Client", .{pascal});
    }

    fn tagClientMethodNameAlloc(self: *UnifiedApiGenerator, operation_id: []const u8) ![]const u8 {
        const pascal = try toPascalCaseAlloc(self.allocator, operation_id);
        defer self.allocator.free(pascal);
        const method = try self.allocator.dupe(u8, pascal);
        if (method.len > 0) method[0] = std.ascii.toLower(method[0]);
        return method;
    }

    fn generateTagClientMethod(self: *UnifiedApiGenerator, struct_name: []const u8, method_name: []const u8, op_ref: OperationRef) !void {
        const operation = op_ref.operation;
        const op_id = operation.operationId;
        const has_return = self.hasReturnValue(op_ref.method, operation);

        // When the method name matches the operation id, the unqualified
        // delegation call inside the method would be an ambiguous reference to
        // the file-scope flat function. Route through the `_` aliases emitted
        // by generateTagClients instead. Operations without an operationId
        // delegate to the raw @"operation{path}" flat fallback, which never
        // matches the derived method name, so no alias is needed.
        const needs_alias = if (op_id) |id| blk: {
            const prospective_name = try self.tagClientMethodNameAlloc(id);
            defer self.allocator.free(prospective_name);
            break :blk std.mem.eql(u8, prospective_name, id);
        } else false;

        try self.buffer.appendSlice(self.allocator, "    pub fn ");
        try self.buffer.appendSlice(self.allocator, method_name);
        try self.buffer.appendSlice(self.allocator, "(self: *");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
        if (has_return) {
            try self.buffer.appendSlice(self.allocator, ") !Owned(");
            try self.appendReturnType(op_ref.method, operation);
            try self.buffer.appendSlice(self.allocator, ") {\n");
        } else {
            try self.buffer.appendSlice(self.allocator, ") !void {\n");
        }
        try self.buffer.appendSlice(self.allocator, "        return ");
        if (op_id) |id| {
            if (needs_alias) {
                // The alias name is the literal `_` + operationId, which stays a
                // valid bare identifier even when the operationId is a Zig keyword.
                try self.buffer.appendSlice(self.allocator, "_");
                try self.buffer.appendSlice(self.allocator, id);
            } else {
                try self.appendIdentifier(id);
            }
        } else {
            try self.buffer.appendSlice(self.allocator, "@\"operation");
            try self.buffer.appendSlice(self.allocator, op_ref.path[1..]);
            try self.buffer.appendSlice(self.allocator, "\"");
        }
        try self.appendTagClientCallArguments(operation);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.buffer.appendSlice(self.allocator, "    }\n\n");

        if (op_id) |id| {
            const raw_method_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{method_name});
            defer self.allocator.free(raw_method_name);
            const raw_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{id});
            defer self.allocator.free(raw_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn ");
            try self.buffer.appendSlice(self.allocator, raw_method_name);
            try self.buffer.appendSlice(self.allocator, "(self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
            try self.buffer.appendSlice(self.allocator, ") !RawResponse {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            if (needs_alias) try self.buffer.appendSlice(self.allocator, "_");
            try self.appendIdentifier(raw_operation_name);
            try self.appendTagClientCallArguments(operation);
            try self.buffer.appendSlice(self.allocator, ";\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");

            if (has_return) {
                const result_method_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{method_name});
                defer self.allocator.free(result_method_name);
                const result_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{id});
                defer self.allocator.free(result_operation_name);

                try self.buffer.appendSlice(self.allocator, "    pub fn ");
                try self.buffer.appendSlice(self.allocator, result_method_name);
                try self.buffer.appendSlice(self.allocator, "(self: *");
                try self.buffer.appendSlice(self.allocator, struct_name);
                try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
                try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
                try self.appendReturnType(op_ref.method, operation);
                try self.buffer.appendSlice(self.allocator, ") {\n");
                try self.buffer.appendSlice(self.allocator, "        return ");
                if (needs_alias) try self.buffer.appendSlice(self.allocator, "_");
                try self.appendIdentifier(result_operation_name);
                try self.appendTagClientCallArguments(operation);
                try self.buffer.appendSlice(self.allocator, ";\n");
                try self.buffer.appendSlice(self.allocator, "    }\n\n");
            }

            if (operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
                const stream_method_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{method_name});
                defer self.allocator.free(stream_method_name);
                const stream_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{id});
                defer self.allocator.free(stream_operation_name);

                try self.buffer.appendSlice(self.allocator, "    pub fn ");
                try self.buffer.appendSlice(self.allocator, stream_method_name);
                try self.buffer.appendSlice(self.allocator, "(self: *");
                try self.buffer.appendSlice(self.allocator, struct_name);
                try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
                try self.buffer.appendSlice(self.allocator, "        return ");
                if (needs_alias) try self.buffer.appendSlice(self.allocator, "_");
                try self.appendIdentifier(stream_operation_name);
                try self.buffer.appendSlice(self.allocator, "(self.client, requestBody, callback, cancellation_token);\n");
                try self.buffer.appendSlice(self.allocator, "    }\n\n");

                const stream_events_method_name = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{method_name});
                defer self.allocator.free(stream_events_method_name);
                const stream_events_operation_name = try std.fmt.allocPrint(self.allocator, "{s}StreamingEvents", .{id});
                defer self.allocator.free(stream_events_operation_name);

                try self.buffer.appendSlice(self.allocator, "    pub fn ");
                try self.buffer.appendSlice(self.allocator, stream_events_method_name);
                try self.buffer.appendSlice(self.allocator, "(comptime Event: type, self: *");
                try self.buffer.appendSlice(self.allocator, struct_name);
                try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
                try self.buffer.appendSlice(self.allocator, "        return ");
                try self.appendIdentifier(stream_events_operation_name);
                try self.buffer.appendSlice(self.allocator, "(Event, self.client, requestBody, callback, cancellation_token);\n");
                try self.buffer.appendSlice(self.allocator, "    }\n\n");
            }
        }
    }

    fn appendTagClientCallArguments(self: *UnifiedApiGenerator, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "(self.client");
        if (operation.parameters) |params| {
            if (self.args.parameters_as_struct) {
                for (params) |param| {
                    if (param.location == .body) continue;
                    try self.buffer.appendSlice(self.allocator, ", options");
                    break;
                }
            }
            for (params) |param| {
                if (self.args.parameters_as_struct and param.location != .body) continue;
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendIdentifier(name);
            }
        }
        try self.buffer.appendSlice(self.allocator, ")");
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

        // Detect wrapper method name collision with ancestor/child struct names
        for (wrappers) |*wrapper_at_depth| {
            if (wrapper_at_depth.segments.len == depth and containsString(declarations.items, wrapper_at_depth.method_name)) {
                wrapper_at_depth.collides = true;
            }
        }

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
                if (wrapper.operation.streaming) {
                    const stream_decl_name = try std.fmt.allocPrint(self.allocator, "{s}Stream", .{wrapper.operation_id});
                    try declarations.append(self.allocator, stream_decl_name);
                    try allocated_declarations.append(self.allocator, stream_decl_name);
                    const events_decl_name = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{wrapper.operation_id});
                    try declarations.append(self.allocator, events_decl_name);
                    try allocated_declarations.append(self.allocator, events_decl_name);
                }
            }
        }

        for (wrappers) |wrapper| {
            if (wrapper.segments.len == depth) {
                try self.generateResourceMethod(wrapper, declarations.items, indent);
                if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                    try self.generateResourceResultMethod(wrapper, declarations.items, indent);
                }
                if (wrapper.operation.streaming) {
                    const stream_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{wrapper.operation_id});
                    defer self.allocator.free(stream_name);
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
        try self.appendWrapperSignatureAndReturn(wrapper.method, wrapper.operation, forbidden_names, wrapper.path);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        if (wrapper.needs_alias) try self.buffer.appendSlice(self.allocator, "_");
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
        try self.appendWrapperResultSignature(wrapper.method, wrapper.operation, forbidden_names, wrapper.path);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        if (wrapper.needs_alias) try self.buffer.appendSlice(self.allocator, "_");
        try self.appendIdentifier(operation_result_name);
        try self.appendWrapperCallArguments(wrapper.operation, forbidden_names);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    fn appendWrapperResultSignature(self: *UnifiedApiGenerator, method: []const u8, operation: Operation, forbidden_names: []const []const u8, path: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        try self.appendOperationParameters(operation, forbidden_names, method, path);
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
        const stream_method_name = try std.fmt.allocPrint(self.allocator, "{s}Stream", .{wrapper.operation_id});
        defer self.allocator.free(stream_method_name);
        const events_method_name = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{wrapper.operation_id});
        defer self.allocator.free(events_method_name);

        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.buffer.appendSlice(self.allocator, stream_method_name);
        try self.buffer.appendSlice(self.allocator, "(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        try self.buffer.appendSlice(self.allocator, stream_name);
        try self.buffer.appendSlice(self.allocator, "(client, requestBody, callback, cancellation_token);\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");

        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub fn ");
        try self.buffer.appendSlice(self.allocator, events_method_name);
        try self.buffer.appendSlice(self.allocator, "(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
        try self.appendIndent(indent + 1);
        try self.buffer.appendSlice(self.allocator, "return ");
        try self.buffer.appendSlice(self.allocator, stream_name);
        try self.buffer.appendSlice(self.allocator, "Events(Event, client, requestBody, callback, cancellation_token);\n");
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "}\n");
    }

    fn appendWrapperSignatureAndReturn(self: *UnifiedApiGenerator, method: []const u8, operation: Operation, forbidden_names: []const []const u8, path: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "(client: *Client");
        try self.appendOperationParameters(operation, forbidden_names, method, path);
        if (self.hasReturnValue(method, operation)) {
            try self.buffer.appendSlice(self.allocator, ") !Owned(");
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ")");
        } else {
            try self.buffer.appendSlice(self.allocator, ") !void");
        }
    }

    fn appendOperationParameters(self: *UnifiedApiGenerator, operation: Operation, forbidden_names: []const []const u8, method: []const u8, path: []const u8) !void {
        if (operation.parameters) |params| {
            if (self.args.parameters_as_struct) {
                try self.appendOptionsParam(operation, method, path);
                try self.appendBodyParams(params);
                return;
            }
            for (params) |param| {
                try self.buffer.appendSlice(self.allocator, ", ");
                const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
                try self.appendParameterName(name, forbidden_names);
                try self.buffer.appendSlice(self.allocator, ": ");
                if (param.location == .query and !param.required) {
                    try self.buffer.appendSlice(self.allocator, "?");
                }
                try self.appendParamBaseType(param);
            }
        }
    }

    fn appendWrapperCallArguments(self: *UnifiedApiGenerator, operation: Operation, forbidden_names: []const []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "(client");
        if (operation.parameters) |params| {
            if (self.args.parameters_as_struct) {
                for (params) |param| {
                    if (param.location == .body) continue;
                    try self.buffer.appendSlice(self.allocator, ", options");
                    break;
                }
            }
            for (params) |param| {
                if (self.args.parameters_as_struct and param.location != .body) continue;
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

    fn resourceAliasConflicts(self: *UnifiedApiGenerator, alias: []const u8, document: UnifiedDocument) bool {
        const reserved_aliases = [_][]const u8{ "organization", "project", "value" };
        for (reserved_aliases) |reserved_alias| {
            if (std.mem.eql(u8, alias, reserved_alias)) return true;
        }

        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path_item = entry.value_ptr.*;
            if (operationHasParameterNamed(self, path_item.get, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.get, "GET", alias)) return true;
            if (operationHasParameterNamed(self, path_item.post, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.post, "POST", alias)) return true;
            if (operationHasParameterNamed(self, path_item.put, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.put, "PUT", alias)) return true;
            if (operationHasParameterNamed(self, path_item.delete, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.delete, "DELETE", alias)) return true;
            if (operationHasParameterNamed(self, path_item.patch, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.patch, "PATCH", alias)) return true;
            if (operationHasParameterNamed(self, path_item.head, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.head, "HEAD", alias)) return true;
            if (operationHasParameterNamed(self, path_item.options, alias)) return true;
            if (operationDeclaresTopLevelName(self, path_item.options, "OPTIONS", alias)) return true;
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

    fn operationDeclaresTopLevelName(self: *UnifiedApiGenerator, maybe_operation: ?Operation, method: []const u8, name: []const u8) bool {
        const operation = maybe_operation orelse return false;
        const operation_id = operation.operationId orelse return false;
        if (std.mem.eql(u8, operation_id, name)) return true;

        const raw_name = std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id}) catch return true;
        defer self.allocator.free(raw_name);
        if (std.mem.eql(u8, raw_name, name)) return true;

        if (self.hasReturnValue(method, operation)) {
            const result_name = std.fmt.allocPrint(self.allocator, "{s}Result", .{operation_id}) catch return true;
            defer self.allocator.free(result_name);
            if (std.mem.eql(u8, result_name, name)) return true;
        }

        if (operation.streaming) {
            const stream_name = std.fmt.allocPrint(self.allocator, "{s}Streaming", .{operation_id}) catch return true;
            defer self.allocator.free(stream_name);
            if (std.mem.eql(u8, stream_name, name)) return true;

            const events_name = std.fmt.allocPrint(self.allocator, "{s}Events", .{stream_name}) catch return true;
            defer self.allocator.free(events_name);
            if (std.mem.eql(u8, events_name, name)) return true;
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
            const valid = if (i == 0) ident.isIdentStart(lower) else ident.isIdentContinue(lower);
            try out.append(self.allocator, if (valid) lower else '_');
        }
        if (out.items.len == 0 or !ident.isIdentStart(out.items[0])) try out.insert(self.allocator, 0, '_');
        if (ident.isReservedIdent(out.items)) try out.appendSlice(self.allocator, "_");
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
        try self.appendFlatOperationParameters(operation, method, path);

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
                if (parameter.location != .path and parameter.location != .body and parameter.location != .query) {
                    try self.buffer.appendSlice(self.allocator, "    _ = ");
                    try self.appendParamReference(operation, method, path, i, parameter);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                }
            }
        }

        try self.buffer.appendSlice(self.allocator, "    var headers = std.ArrayList(std.http.Header).empty;\n");
        try self.buffer.appendSlice(self.allocator, "    defer headers.deinit(allocator);\n");
        try self.buffer.appendSlice(self.allocator, "    const auth_header = try appendClientHeaders(allocator, &headers, client, ");
        if (has_body_param) {
            try self.buffer.appendSlice(self.allocator, "\"");
            try self.buffer.appendSlice(self.allocator, direct_ct);
            try self.buffer.appendSlice(self.allocator, "\"");
        } else {
            try self.buffer.appendSlice(self.allocator, "null");
        }
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
        try self.buffer.appendSlice(self.allocator, ", uri_buf.written(), headers.items, ");
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
        try self.buffer.appendSlice(self.allocator, "        .extra_headers = headers.items,\n");
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

test "BodyKind :: classifyBody routes media types correctly" {
    const t = std.testing;
    try t.expectEqual(BodyKind.json, classifyBody(null));
    try t.expectEqual(BodyKind.json, classifyBody(""));
    try t.expectEqual(BodyKind.json, classifyBody("application/json"));
    try t.expectEqual(BodyKind.json, classifyBody("application/vnd.api+json"));
    try t.expectEqual(BodyKind.binary, classifyBody("application/octet-stream"));
    try t.expectEqual(BodyKind.binary, classifyBody("image/png"));
    try t.expectEqual(BodyKind.binary, classifyBody("audio/mpeg"));
    try t.expectEqual(BodyKind.binary, classifyBody("video/mp4"));
    try t.expectEqual(BodyKind.binary, classifyBody("*/*"));
    try t.expectEqual(BodyKind.binary, classifyBody("application/xml"));
    try t.expectEqual(BodyKind.binary, classifyBody("application/pdf"));
    try t.expectEqual(BodyKind.text, classifyBody("text/plain"));
    try t.expectEqual(BodyKind.text, classifyBody("text/csv"));
    try t.expectEqual(BodyKind.form, classifyBody("application/x-www-form-urlencoded"));
    try t.expectEqual(BodyKind.form, classifyBody("multipart/form-data"));
    // Media types with parameters must be classified by their base type.
    try t.expectEqual(BodyKind.json, classifyBody("application/json; charset=utf-8"));
    try t.expectEqual(BodyKind.json, classifyBody("application/vnd.api+json; charset=utf-8"));
    try t.expectEqual(BodyKind.text, classifyBody("text/plain; charset=utf-8"));
    try t.expectEqual(BodyKind.form, classifyBody("multipart/form-data; boundary=abc"));
}
