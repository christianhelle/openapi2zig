const std = @import("std");

///////////////////////////////////////////
// Generated Zig structures from OpenAPI
///////////////////////////////////////////

pub const LlmLoadConfig = struct {
    context_length: i64,
    flash_attention: ?bool = null,
    eval_batch_size: ?i64 = null,
    num_experts: ?i64 = null,
    offload_kv_cache_to_gpu: ?bool = null,
};

pub const UnloadModelRequest = struct {
    instance_id: []const u8,
};

pub const ReasoningOutput = struct {
    @"type": []const u8,
    content: []const u8,
};

pub const ListModelsResponse = struct {
    models: []const ModelInfo,
};

pub const DownloadModelResponse = struct {
    status: []const u8,
    job_id: ?[]const u8 = null,
    completed_at: ?[]const u8 = null,
    total_size_bytes: ?i64 = null,
    started_at: ?[]const u8 = null,
};

pub const ChatOutputItem = union(enum) {
    message: MessageOutput,
    tool_call: ToolCallOutput,
    reasoning: ReasoningOutput,
    invalid_tool_call: InvalidToolCallOutput,
    raw: std.json.Value,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        if (source != .object) return error.UnexpectedToken;        const discriminator = source.object.get("type") orelse return .{ .raw = source };
        if (discriminator != .string) return .{ .raw = source };
        if (std.mem.eql(u8, discriminator.string, "message")) {
            return .{ .message = try std.json.parseFromValueLeaky(MessageOutput, allocator, source, options) };
        }
        if (std.mem.eql(u8, discriminator.string, "tool_call")) {
            return .{ .tool_call = try std.json.parseFromValueLeaky(ToolCallOutput, allocator, source, options) };
        }
        if (std.mem.eql(u8, discriminator.string, "reasoning")) {
            return .{ .reasoning = try std.json.parseFromValueLeaky(ReasoningOutput, allocator, source, options) };
        }
        if (std.mem.eql(u8, discriminator.string, "invalid_tool_call")) {
            return .{ .invalid_tool_call = try std.json.parseFromValueLeaky(InvalidToolCallOutput, allocator, source, options) };
        }

        return .{ .raw = source };
    }

    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        switch (self) {            .message => |value| try jw.write(value),
            .tool_call => |value| try jw.write(value),
            .reasoning => |value| try jw.write(value),
            .invalid_tool_call => |value| try jw.write(value),
            .raw => |value| try jw.write(value),
        }
    }
};

pub const LoadedInstance = struct {
    id: []const u8,
    config: LoadedInstanceConfig,
};

pub const TextInput = struct {
    @"type": []const u8,
    content: []const u8,
};

pub const LoadModelRequest = struct {
    context_length: ?i64 = null,
    flash_attention: ?bool = null,
    eval_batch_size: ?i64 = null,
    num_experts: ?i64 = null,
    offload_kv_cache_to_gpu: ?bool = null,
    model: []const u8,
    echo_load_config: ?bool = null,
};

pub const ModelInfoCapabilitiesReasoning = struct {
    allowed_options: []const []const u8,
    default: []const u8,
};

pub const ModelInfoCapabilities = struct {
    trained_for_tool_use: ?bool = null,
    reasoning: ?ModelInfoCapabilitiesReasoning = null,
    vision: ?bool = null,
};

pub const ModelInfoQuantization = struct {
    name: []const u8,
    bits_per_weight: f64,
};

pub const ModelInfo = struct {
    params_string: ?[]const u8 = null,
    publisher: []const u8,
    key: []const u8,
    format: []const u8,
    variants: ?[]const []const u8 = null,
    selected_variant: ?[]const u8 = null,
    display_name: []const u8,
    size_bytes: i64,
    architecture: ?[]const u8 = null,
    max_context_length: i64,
    capabilities: ?ModelInfoCapabilities = null,
    loaded_instances: []const LoadedInstance,
    quantization: ?ModelInfoQuantization = null,
    description: ?[]const u8 = null,
    @"type": []const u8,
};

pub const EmbeddingLoadConfig = struct {
    context_length: i64,
};

pub const DownloadStatusResponse = struct {
    completed_at: ?[]const u8 = null,
    bytes_per_second: ?i64 = null,
    estimated_completion: ?[]const u8 = null,
    total_size_bytes: ?i64 = null,
    started_at: ?[]const u8 = null,
    status: []const u8,
    job_id: []const u8,
    downloaded_bytes: ?i64 = null,
};

pub const PluginIntegration = struct {
    allowed_tools: ?[]const []const u8 = null,
    id: []const u8,
    @"type": []const u8,
};

pub const ChatStats = struct {
    input_tokens: i64,
    reasoning_output_tokens: i64,
    tokens_per_second: f64,
    time_to_first_token_seconds: f64,
    total_output_tokens: i64,
    model_load_time_seconds: ?f64 = null,
};

pub const ChatResponse = struct {
    stats: ChatStats,
    response_id: ?[]const u8 = null,
    model_instance_id: []const u8,
    output: []const ChatOutputItem,
};

pub const DownloadModelRequest = struct {
    quantization: ?[]const u8 = null,
    model: []const u8,
};

pub const ChatRequestIntegrationsItemVariant0 = []const u8;

pub const ChatRequestIntegrationsItem = union(enum) {
    string: []const u8,
    plugin_integration: PluginIntegration,
    ephemeral_mcp_integration: EphemeralMcpIntegration,
    raw: std.json.Value,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {        if (std.json.parseFromValueLeaky([]const u8, allocator, source, options)) |value| {
            return .{ .string = value };
        } else |_| {}
        if (std.json.parseFromValueLeaky(PluginIntegration, allocator, source, options)) |value| {
            return .{ .plugin_integration = value };
        } else |_| {}
        if (std.json.parseFromValueLeaky(EphemeralMcpIntegration, allocator, source, options)) |value| {
            return .{ .ephemeral_mcp_integration = value };
        } else |_| {}
        return .{ .raw = source };
    }

    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        switch (self) {            .string => |value| try jw.write(value),
            .plugin_integration => |value| try jw.write(value),
            .ephemeral_mcp_integration => |value| try jw.write(value),
            .raw => |value| try jw.write(value),
        }
    }
};

pub const ChatRequestInputVariant0 = []const u8;

pub const ChatRequestInputVariant1 = []const ChatInputItem;

pub const ChatRequestInput = union(enum) {
    string: []const u8,
    chat_input_item_items: []const ChatInputItem,
    raw: std.json.Value,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {        if (std.json.parseFromValueLeaky([]const u8, allocator, source, options)) |value| {
            return .{ .string = value };
        } else |_| {}
        if (std.json.parseFromValueLeaky([]const ChatInputItem, allocator, source, options)) |value| {
            return .{ .chat_input_item_items = value };
        } else |_| {}
        return .{ .raw = source };
    }

    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        switch (self) {            .string => |value| try jw.write(value),
            .chat_input_item_items => |value| try jw.write(value),
            .raw => |value| try jw.write(value),
        }
    }
};

pub const ChatRequest = struct {
    integrations: ?[]const ChatRequestIntegrationsItem = null,
    reasoning: ?[]const u8 = null,
    temperature: ?f64 = null,
    max_output_tokens: ?i64 = null,
    store: ?bool = null,
    model: []const u8,
    stream: ?bool = null,
    context_length: ?i64 = null,
    repeat_penalty: ?f64 = null,
    top_p: ?f64 = null,
    top_k: ?i64 = null,
    min_p: ?f64 = null,
    previous_response_id: ?[]const u8 = null,
    input: ChatRequestInput,
    system_prompt: ?[]const u8 = null,
};

pub const MessageOutput = struct {
    @"type": []const u8,
    content: []const u8,
};

pub const LoadedInstanceConfig = struct {
    context_length: i64,
    num_experts: ?i64 = null,
    flash_attention: ?bool = null,
    eval_batch_size: ?i64 = null,
    parallel: ?i64 = null,
    offload_kv_cache_to_gpu: ?bool = null,
};

pub const ImageInput = struct {
    data_url: []const u8,
    @"type": []const u8,
};

pub const UnloadModelResponse = struct {
    instance_id: []const u8,
};

pub const InvalidToolCallOutputMetadata = struct {
    arguments: ?std.json.Value = null,
    tool_name: []const u8,
    @"type": []const u8,
    provider_info: ?ProviderInfo = null,
};

pub const InvalidToolCallOutput = struct {
    metadata: InvalidToolCallOutputMetadata,
    reason: []const u8,
    @"type": []const u8,
};

pub const LoadModelResponseLoadConfig = union(enum) {
    llm_load_config: LlmLoadConfig,
    embedding_load_config: EmbeddingLoadConfig,
    raw: std.json.Value,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {        if (std.json.parseFromValueLeaky(LlmLoadConfig, allocator, source, options)) |value| {
            return .{ .llm_load_config = value };
        } else |_| {}
        if (std.json.parseFromValueLeaky(EmbeddingLoadConfig, allocator, source, options)) |value| {
            return .{ .embedding_load_config = value };
        } else |_| {}
        return .{ .raw = source };
    }

    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        switch (self) {            .llm_load_config => |value| try jw.write(value),
            .embedding_load_config => |value| try jw.write(value),
            .raw => |value| try jw.write(value),
        }
    }
};

pub const LoadModelResponse = struct {
    load_time_seconds: f64,
    status: []const u8,
    instance_id: []const u8,
    load_config: ?LoadModelResponseLoadConfig = null,
    @"type": []const u8,
};

pub const ProviderInfo = struct {
    @"type": []const u8,
    plugin_id: ?[]const u8 = null,
    server_label: ?[]const u8 = null,
};

pub const ChatInputItem = union(enum) {
    message: TextInput,
    image: ImageInput,
    raw: std.json.Value,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        if (source != .object) return error.UnexpectedToken;        const discriminator = source.object.get("type") orelse return .{ .raw = source };
        if (discriminator != .string) return .{ .raw = source };
        if (std.mem.eql(u8, discriminator.string, "message")) {
            return .{ .message = try std.json.parseFromValueLeaky(TextInput, allocator, source, options) };
        }
        if (std.mem.eql(u8, discriminator.string, "image")) {
            return .{ .image = try std.json.parseFromValueLeaky(ImageInput, allocator, source, options) };
        }

        return .{ .raw = source };
    }

    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        switch (self) {            .message => |value| try jw.write(value),
            .image => |value| try jw.write(value),
            .raw => |value| try jw.write(value),
        }
    }
};

pub const EphemeralMcpIntegration = struct {
    server_url: []const u8,
    allowed_tools: ?[]const []const u8 = null,
    @"type": []const u8,
    headers: ?std.json.Value = null,
    server_label: []const u8,
};

pub const ToolCallOutput = struct {
    arguments: std.json.Value,
    tool: []const u8,
    output: []const u8,
    @"type": []const u8,
    provider_info: ProviderInfo,
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
    base_url: []const u8 = "http://localhost:1234",
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
    return requestRawWithContentType(client, method, url, payload, "application/json");
}

pub fn requestRawWithContentType(client: *Client, method: std.http.Method, url: []const u8, payload: ?[]const u8, content_type_value: []const u8) !RawResponse {
    const allocator = client.allocator;
    var headers = std.ArrayList(std.http.Header).empty;
    defer headers.deinit(allocator);
    const content_type: ?[]const u8 = if (payload != null) content_type_value else null;
    const auth_header = try appendClientHeaders(allocator, &headers, client, content_type, "application/json");
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

pub const CancellationToken = struct {
    cancelled: std.atomic.Value(bool),

    pub fn init() CancellationToken {
        return .{ .cancelled = std.atomic.Value(bool).init(false) };
    }

    pub fn cancel(self: *CancellationToken) void {
        self.cancelled.store(true, .seq_cst);
    }

    pub fn isCancelled(self: *CancellationToken) bool {
        return self.cancelled.load(.seq_cst);
    }
};

fn checkCancellation(token: ?*CancellationToken) !void {
    if (token) |t| {
        if (t.isCancelled()) return error.Cancelled;
    }
}

const max_sse_line_size = 256 * 1024;
const max_sse_event_size = 1024 * 1024;

pub fn parseSseBytes(allocator: std.mem.Allocator, bytes: []const u8, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    var reader: std.Io.Reader = .fixed(bytes);
    try parseSseReader(allocator, &reader, callback, cancellation_token);
}

pub fn parseSseReader(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    var line_buf: std.Io.Writer.Allocating = .init(allocator);
    defer line_buf.deinit();

    var event_data: std.Io.Writer.Allocating = .init(allocator);
    defer event_data.deinit();

    while (true) {
        try checkCancellation(cancellation_token);
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

pub fn parseSseBytesTyped(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    const Callback = @TypeOf(callback.*);
    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
    try parseSseBytes(allocator, bytes, &typed_callback, cancellation_token);
}

pub fn parseSseReaderTyped(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    const Callback = @TypeOf(callback.*);
    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = allocator, .callback = callback };
    try parseSseReader(allocator, reader, &typed_callback, cancellation_token);
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

fn streamJsonTyped(comptime T: type, client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    const Callback = @TypeOf(callback.*);
    var typed_callback: TypedSseCallback(T, Callback) = .{ .allocator = client.allocator, .callback = callback };
    try streamJson(client, path, requestBody, &typed_callback, cancellation_token);
}

fn streamJson(client: *Client, path: []const u8, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    const allocator = client.allocator;
    const payload = try stringifyStreamRequest(allocator, requestBody);
    defer allocator.free(payload);

    var headers = std.ArrayList(std.http.Header).empty;
    defer headers.deinit(allocator);
    const auth_header = try appendClientHeaders(allocator, &headers, client, "application/json", "text/event-stream");
    defer if (auth_header) |value| allocator.free(value);

    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ client.base_url, path });
    defer allocator.free(url);
    const uri = try std.Uri.parse(url);
    try checkCancellation(cancellation_token);

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
    try checkCancellation(cancellation_token);

    var response = try req.receiveHead(&.{});
    if (response.head.status.class() != .success) return error.ResponseError;

    var transfer_buffer: [8 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    parseSseReader(allocator, reader, callback, cancellation_token) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr() orelse err,
        else => return err,
    };
}

fn appendClientHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), client: *Client, content_type: ?[]const u8, accept: []const u8) !?[]u8 {
    if (content_type) |ct| {
        try headers.append(allocator, .{ .name = "Content-Type", .value = ct });
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
// List your models
//
// Description:
// Get a list of available models on your system, including both LLMs and embedding models.
//
pub fn listModels(client: *Client) !Owned(ListModelsResponse) {
    var result = try listModelsResult(client);
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

pub fn listModelsRaw(client: *Client) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/api/v1/models", .{client.base_url});
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn listModelsResult(client: *Client) !ApiResult(ListModelsResponse) {
    return parseRawResponse(ListModelsResponse, try listModelsRaw(client));
}

/////////////////
// Summary:
// Download a model
//
// Description:
// Download LLMs and embedding models.
//
pub fn downloadModel(client: *Client, requestBody: DownloadModelRequest) !Owned(DownloadModelResponse) {
    var result = try downloadModelResult(client, requestBody);
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

pub fn downloadModelRaw(client: *Client, requestBody: DownloadModelRequest) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/api/v1/models/download", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

pub fn downloadModelResult(client: *Client, requestBody: DownloadModelRequest) !ApiResult(DownloadModelResponse) {
    return parseRawResponse(DownloadModelResponse, try downloadModelRaw(client, requestBody));
}

/////////////////
// Summary:
// Get download status
//
// Description:
// Get the status of model downloads.
//
pub fn getDownloadStatus(client: *Client, job_id: []const u8) !Owned(DownloadStatusResponse) {
    var result = try getDownloadStatusResult(client, job_id);
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

pub fn getDownloadStatusRaw(client: *Client, job_id: []const u8) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/api/v1/models/download/status/{s}", .{client.base_url, job_id});
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn getDownloadStatusResult(client: *Client, job_id: []const u8) !ApiResult(DownloadStatusResponse) {
    return parseRawResponse(DownloadStatusResponse, try getDownloadStatusRaw(client, job_id));
}

/////////////////
// Summary:
// Unload a model
//
// Description:
// Unload a loaded model from memory.
//
pub fn unloadModel(client: *Client, requestBody: UnloadModelRequest) !Owned(UnloadModelResponse) {
    var result = try unloadModelResult(client, requestBody);
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

pub fn unloadModelRaw(client: *Client, requestBody: UnloadModelRequest) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/api/v1/models/unload", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

pub fn unloadModelResult(client: *Client, requestBody: UnloadModelRequest) !ApiResult(UnloadModelResponse) {
    return parseRawResponse(UnloadModelResponse, try unloadModelRaw(client, requestBody));
}

/////////////////
// Summary:
// Load a model
//
// Description:
// Load an LLM or Embedding model into memory with custom configuration for inference.
//
pub fn loadModel(client: *Client, requestBody: LoadModelRequest) !Owned(LoadModelResponse) {
    var result = try loadModelResult(client, requestBody);
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

pub fn loadModelRaw(client: *Client, requestBody: LoadModelRequest) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/api/v1/models/load", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

pub fn loadModelResult(client: *Client, requestBody: LoadModelRequest) !ApiResult(LoadModelResponse) {
    return parseRawResponse(LoadModelResponse, try loadModelRaw(client, requestBody));
}

/////////////////
// Summary:
// Chat with a model
//
// Description:
// Send a message to a model and receive a response. Supports MCP integration.
//
pub fn chat(client: *Client, requestBody: ChatRequest) !Owned(ChatResponse) {
    var result = try chatResult(client, requestBody);
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

pub fn chatRaw(client: *Client, requestBody: ChatRequest) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/api/v1/chat", .{client.base_url});

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();
    try std.json.Stringify.value(requestBody, .{ .emit_null_optional_fields = false }, &str.writer);
    const payload: ?[]const u8 = str.written();

    return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);
}

pub fn chatResult(client: *Client, requestBody: ChatRequest) !ApiResult(ChatResponse) {
    return parseRawResponse(ChatResponse, try chatRaw(client, requestBody));
}

pub fn chatStreaming(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    return streamJson(client, "/api/v1/chat", requestBody, callback, cancellation_token);
}

pub fn chatStreamingEvents(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
    return streamJsonTyped(Event, client, "/api/v1/chat", requestBody, callback, cancellation_token);
}

const _chat = chat;
const _chatResult = chatResult;

pub const resources = struct {
    pub const api = struct {
        pub const chat = struct {
            pub fn chat_(client: *Client, requestBody: ChatRequest) !Owned(ChatResponse) {
                return _chat(client, requestBody);
            }
            pub fn chat_Result(client: *Client, requestBody: ChatRequest) !ApiResult(ChatResponse) {
                return _chatResult(client, requestBody);
            }
            pub fn chatStream(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
                return chatStreaming(client, requestBody, callback, cancellation_token);
            }
            pub fn chatStreamEvents(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {
                return chatStreamingEvents(Event, client, requestBody, callback, cancellation_token);
            }
        };
        pub const models = struct {
            pub fn list(client: *Client) !Owned(ListModelsResponse) {
                return listModels(client);
            }
            pub fn listResult(client: *Client) !ApiResult(ListModelsResponse) {
                return listModelsResult(client);
            }
            pub const download = struct {
                pub fn downloadmodel(client: *Client, requestBody: DownloadModelRequest) !Owned(DownloadModelResponse) {
                    return downloadModel(client, requestBody);
                }
                pub fn downloadmodelResult(client: *Client, requestBody: DownloadModelRequest) !ApiResult(DownloadModelResponse) {
                    return downloadModelResult(client, requestBody);
                }
                pub const status = struct {
                    pub fn get(client: *Client, job_id: []const u8) !Owned(DownloadStatusResponse) {
                        return getDownloadStatus(client, job_id);
                    }
                    pub fn getResult(client: *Client, job_id: []const u8) !ApiResult(DownloadStatusResponse) {
                        return getDownloadStatusResult(client, job_id);
                    }
                };
            };
            pub const load = struct {
                pub fn loadmodel(client: *Client, requestBody: LoadModelRequest) !Owned(LoadModelResponse) {
                    return loadModel(client, requestBody);
                }
                pub fn loadmodelResult(client: *Client, requestBody: LoadModelRequest) !ApiResult(LoadModelResponse) {
                    return loadModelResult(client, requestBody);
                }
            };
            pub const unload = struct {
                pub fn unloadmodel(client: *Client, requestBody: UnloadModelRequest) !Owned(UnloadModelResponse) {
                    return unloadModel(client, requestBody);
                }
                pub fn unloadmodelResult(client: *Client, requestBody: UnloadModelRequest) !ApiResult(UnloadModelResponse) {
                    return unloadModelResult(client, requestBody);
                }
            };
        };
    };
};

pub const api = resources.api;

