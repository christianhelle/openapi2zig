const std = @import("std");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const common = @import("../models/common/document.zig");
const test_utils = @import("test_utils.zig");

// The raw request helper that gets emitted depends on the declared request body
// media type (JSON, form, binary/text or none) and on whether the operation
// needs extra headers (auth scheme or `in: header` parameters). These tests pin
// down each of those combinations.

const Fixture = struct {
    document: common.UnifiedDocument,
    code: []const u8,

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        self.document.deinit(allocator);
    }
};

const Options = struct {
    body_content_type: ?[]const u8 = null,
    /// When false the operation declares empty security, which disables the
    /// default bearer auth header.
    authenticated: bool = true,
    header_param: bool = false,
    form_param: bool = false,
    streaming: bool = false,
    api_key_header: ?[]const u8 = null,
};

fn responseMap(allocator: std.mem.Allocator) !std.StringHashMap(common.Response) {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, "200"), .{
        .description = "ok",
        .schema = common.Schema{ .type = .object },
    });
    return responses;
}

fn securitySchemes(allocator: std.mem.Allocator, api_key_header: ?[]const u8) !*std.StringHashMap(common.SecurityScheme) {
    const schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);
    if (api_key_header) |name| {
        try schemes.put(try allocator.dupe(u8, "apiKeyAuth"), .{ .api_key_header = .{ .name = try allocator.dupe(u8, name) } });
    } else {
        try schemes.put(try allocator.dupe(u8, "bearerAuth"), .bearer);
    }
    return schemes;
}

fn generate(allocator: std.mem.Allocator, options: Options) !Fixture {
    var parameters = std.ArrayList(common.Parameter).empty;
    errdefer parameters.deinit(allocator);
    if (options.body_content_type) |content_type| {
        try parameters.append(allocator, .{
            .name = "body",
            .location = .body,
            .required = true,
            .schema = .{ .type = .object },
            .content_type = try allocator.dupe(u8, content_type),
        });
    }
    if (options.header_param) {
        try parameters.append(allocator, .{
            .name = "x-trace-id",
            .location = .header,
            .required = true,
            .schema = .{ .type = .string },
        });
    }
    if (options.form_param) {
        try parameters.append(allocator, .{
            .name = "formField",
            .location = .form,
            .schema = .{ .type = .string },
        });
    }

    var security: ?[]common.SecurityRequirement = null;
    if (!options.authenticated) {
        // An empty security list means "no authentication for this operation".
        security = try allocator.alloc(common.SecurityRequirement, 0);
    }

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();
    try paths.put(try allocator.dupe(u8, "/items"), .{
        .post = .{
            .operationId = "createItem",
            .parameters = if (parameters.items.len > 0) try parameters.toOwnedSlice(allocator) else null,
            .responses = try responseMap(allocator),
            .security = security,
            .streaming = options.streaming,
        },
    });

    var document: common.UnifiedDocument = .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .security_schemes = try securitySchemes(allocator, options.api_key_header),
    };
    errdefer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    return .{ .document = document, .code = try generator.generate(document) };
}

fn expectContains(code: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, code, needle) != null);
}

test "json body without extra headers emits the plain raw request helper" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "application/json", .authenticated = false });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);");
}

test "json variant media type without extra headers keeps the declared content type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "application/merge-patch+json", .authenticated = false });
    defer fixture.deinit(allocator);

    try expectContains(
        fixture.code,
        "return requestRawWithContentType(client, std.http.Method.POST, uri_buf.written(), payload, \"application/merge-patch+json\");",
    );
}

test "json variant media type with auth keeps the declared content type and headers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "application/merge-patch+json" });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "return requestRawWithContentTypeAndExtraHeaders(client, std.http.Method.POST");
    try expectContains(fixture.code, "\"application/merge-patch+json\"");
}

test "form body falls back to JSON encoding and notes the limitation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "multipart/form-data" });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "multipart/form-data and x-www-form-urlencoded request bodies are not yet supported");
    try expectContains(fixture.code, "try std.json.Stringify.value(requestBody");
    try expectContains(fixture.code, "return requestRawWithExtraHeaders(client, std.http.Method.POST");
    // The emitted Content-Type must describe the JSON payload actually sent.
    try expectContains(fixture.code, "\"application/json\"");
}

test "form body without extra headers emits the plain raw request helper" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{
        .body_content_type = "application/x-www-form-urlencoded",
        .authenticated = false,
    });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "multipart/form-data and x-www-form-urlencoded request bodies are not yet supported");
    try expectContains(fixture.code, "return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);");
}

test "operation without a request body sends a null payload" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .authenticated = false });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "const payload: ?[]const u8 = null;");
    try expectContains(fixture.code, "return requestRaw(client, std.http.Method.POST, uri_buf.written(), payload);");
}

test "operation without a request body still sends auth headers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .header_param = true });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "const payload: ?[]const u8 = null;");
    try expectContains(fixture.code, "return requestRawWithExtraHeaders(client, std.http.Method.POST");
    try expectContains(fixture.code, "\"x-trace-id\"");
}

test "binary body is sent verbatim through a direct fetch" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{
        .body_content_type = "application/octet-stream",
        .header_param = true,
    });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "const payload: ?[]const u8 = requestBody;");
    try expectContains(fixture.code, "\"application/octet-stream\", \"application/json\");");
    try expectContains(fixture.code, "const result = client.http.fetch(.{");
    try expectContains(fixture.code, "if (obs.onRequest) |cb| cb(obs.ctx, std.http.Method.POST");
    try expectContains(fixture.code, "if (obs.onError) |cb| cb(obs.ctx, std.http.Method.POST");
    try expectContains(fixture.code, "if (obs.onResponse) |cb| cb(obs.ctx, std.http.Method.POST");
}

test "text body is sent verbatim through a direct fetch" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "text/plain" });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "const payload: ?[]const u8 = requestBody;");
    try expectContains(fixture.code, "\"text/plain\", \"application/json\");");
}

test "parameters in unsupported locations are discarded explicitly" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .form_param = true, .authenticated = false });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "_ = formField;");
}

test "streaming operation without auth uses the plain stream helpers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{
        .body_content_type = "application/json",
        .streaming = true,
        .authenticated = false,
    });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "return streamJson(client, \"/items\", requestBody, callback, cancellation_token);");
    try expectContains(fixture.code, "return streamJsonTyped(Event, client, \"/items\", requestBody, callback, cancellation_token);");
}

test "streaming operation with an api key header threads it through the stream helpers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{
        .body_content_type = "application/json",
        .streaming = true,
        .api_key_header = "X-API-Key",
    });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "try stream_headers.append(client.allocator, .{ .name = \"X-API-Key\", .value = client.api_key });");
    try expectContains(fixture.code, "return streamJsonWithExtraHeaders(client, \"/items\"");
    try expectContains(fixture.code, "return streamJsonTypedWithExtraHeaders(Event, client, \"/items\"");
}
