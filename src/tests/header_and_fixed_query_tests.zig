const std = @import("std");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const common = @import("../models/common/document.zig");
const test_utils = @import("test_utils.zig");

// Regression coverage for https://github.com/christianhelle/openapi2zig/issues/101:
// declared `in: header` parameters must be sent as request headers instead of
// being silently discarded, and a path with a fixed query component (e.g.
// "?beta=true") must not produce a second "?" when dynamic query parameters
// are appended.

fn responseMap(allocator: std.mem.Allocator) !std.StringHashMap(common.Response) {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, "200"), .{
        .description = "ok",
        .schema = common.Schema{ .type = .object },
    });
    return responses;
}

fn buildHeaderFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "anthropic-version", .location = .header, .required = true, .schema = .{ .type = .string } },
        .{ .name = "anthropic-beta", .location = .header, .required = false, .schema = .{ .type = .string } },
        .{ .name = "message", .location = .body, .required = true, .schema = .{ .type = .object } },
    });
    try paths.put(try allocator.dupe(u8, "/v1/messages"), .{
        .post = .{
            .operationId = "createMessage",
            .parameters = params,
            .responses = try responseMap(allocator),
        },
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "required header parameters are sent as request headers, not discarded" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // The required header parameter must never be silently discarded.
    try std.testing.expect(std.mem.indexOf(u8, code, "_ = @\"anthropic-version\";") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const header_value = try formatHeaderValue(allocator, @\"anthropic-version\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "try appendOrReplaceHeader(allocator, &operation_headers, \"anthropic-version\", header_value);") != null);
}

test "optional header parameters are only sent when non-null" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "_ = @\"anthropic-beta\";") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "if (@\"anthropic-beta\") |value| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "try appendOrReplaceHeader(allocator, &operation_headers, \"anthropic-beta\", header_value);") != null);
}

test "header API key security emits its declared auth header" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);
    const schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);
    document.security_schemes = schemes;
    try schemes.put(try allocator.dupe(u8, "anthropicApiKey"), .{
        .api_key_header = .{ .name = try allocator.dupe(u8, "x-api-key") },
    });

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "try headers.append(allocator, .{ .name = \"x-api-key\", .value = client.api_key });") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "auth_header = try std.fmt.allocPrint(allocator, \"Bearer {s}\", .{client.api_key});") == null);
}

test "SecurityScheme deinit correctly frees ApiKeyHeader allocation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);

    const key = try allocator.dupe(u8, "apiKey");
    const val = try allocator.dupe(u8, "X-API-Key");
    try schemes.put(key, .{ .api_key_header = .{ .name = val } });

    var document = common.UnifiedDocument{
        .version = "3.0.0",
        .info = .{ .title = "test", .version = "1.0.0" },
        .paths = std.StringHashMap(common.PathItem).init(allocator),
        .security_schemes = schemes,
    };
    defer document.deinit(allocator);
}

test "auth scheme selection prefers document security requirements when operation security is missing" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);

    const schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);
    document.security_schemes = schemes;

    try schemes.put(try allocator.dupe(u8, "bearerAuth"), .bearer);
    try schemes.put(try allocator.dupe(u8, "apiKeyAuth"), .{
        .api_key_header = .{ .name = try allocator.dupe(u8, "x-api-key") },
    });

    var sec_req_schemes = std.StringHashMap([][]const u8).init(allocator);
    try sec_req_schemes.put(try allocator.dupe(u8, "apiKeyAuth"), &.{});
    const sec_reqs = try allocator.dupe(common.SecurityRequirement, &.{
        .{ .schemes = sec_req_schemes },
    });
    document.security = sec_reqs;

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "try headers.append(allocator, .{ .name = \"x-api-key\", .value = client.api_key });") != null);
}

test "auth scheme selection prefers operation security requirements" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);

    const schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);
    document.security_schemes = schemes;

    try schemes.put(try allocator.dupe(u8, "bearerAuth"), .bearer);
    try schemes.put(try allocator.dupe(u8, "apiKeyAuth"), .{
        .api_key_header = .{ .name = try allocator.dupe(u8, "x-api-key") },
    });

    var path_entry = document.paths.getPtr("/v1/messages").?;
    var op_sec_schemes = std.StringHashMap([][]const u8).init(allocator);
    try op_sec_schemes.put(try allocator.dupe(u8, "apiKeyAuth"), &.{});
    const op_sec_reqs = try allocator.dupe(common.SecurityRequirement, &.{
        .{ .schemes = op_sec_schemes },
    });
    path_entry.post.?.security = op_sec_reqs;

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "try headers.append(allocator, .{ .name = \"x-api-key\", .value = client.api_key });") != null);
}

test "generated Raw function passes headers to the shared request helper" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "return requestRawWithExtraHeaders(client, std.http.Method.POST, uri_buf.written(), payload, operation_headers.items);") != null);
}

test "operation headers replace every default with their declared wire name" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildHeaderFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "headers.orderedRemove(i);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "try headers.append(allocator, .{ .name = name, .value = value });") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "@compileError(\"OpenAPI header values must be strings, numbers, booleans, or enums\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "errdefer allocator.free(header_value);") != null);
    const append_header = std.mem.indexOf(u8, code, "try appendOrReplaceHeader(allocator, &operation_headers, \"anthropic-version\", header_value);").?;
    const own_header_value = std.mem.indexOf(u8, code, "try operation_header_values.append(allocator, header_value);").?;
    try std.testing.expect(append_header < own_header_value);
}

test "header parameters do not shadow generated header locals" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "headers", .location = .header, .required = true, .schema = .{ .type = .string } },
        .{ .name = "header_values", .location = .header, .required = true, .schema = .{ .type = .string } },
        .{ .name = "operation_headers", .location = .header, .required = true, .schema = .{ .type = .string } },
        .{ .name = "operation_header_values", .location = .header, .required = true, .schema = .{ .type = .string } },
    });
    try paths.put(try allocator.dupe(u8, "/headers"), .{
        .get = .{
            .operationId = "getHeaders",
            .parameters = params,
            .responses = try responseMap(allocator),
        },
    });
    var document: common.UnifiedDocument = .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "getHeadersRaw(client: *Client, headers: []const u8, header_values: []const u8, operation_headers: []const u8, operation_header_values: []const u8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var operation_headers_ = std.ArrayList(std.http.Header).empty;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var operation_header_values_ = std.ArrayList([]u8).empty;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "&operation_headers_, \"headers\", header_value") != null);
}

fn buildFixedQueryFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "before_id", .location = .query, .required = false, .schema = .{ .type = .string } },
        .{ .name = "limit", .location = .query, .required = false, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/v1/deployments/run?beta=true"), .{
        .get = .{
            .operationId = "listDeploymentRuns",
            .parameters = params,
            .responses = try responseMap(allocator),
        },
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "a fixed query string in the path is followed by '&' instead of a second '?'" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixedQueryFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "\"{s}/v1/deployments/run?beta=true\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var first_query = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "\"{s}/v1/deployments/run?beta=true?") == null);
}

fn buildTrailingSeparatorFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .required = false, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/v1/items?"), .{
        .get = .{
            .operationId = "listItems",
            .parameters = params,
            .responses = try responseMap(allocator),
        },
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "a trailing '?' with no fixed key/value pairs still starts with a single '?'" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildTrailingSeparatorFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "\"{s}/v1/items\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var first_query = true;") != null);
}

test "fixed query text is escaped before being emitted in a Zig string literal" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .required = false, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/v1/items?filter=\"active\"\\draft"), .{
        .get = .{
            .operationId = "listEscapedItems",
            .parameters = params,
            .responses = try responseMap(allocator),
        },
    });
    var document: common.UnifiedDocument = .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "try uri_buf.writer.print(\"{s}/v1/items?filter=\\\"active\\\"\\\\draft\", .{client.base_url});") != null);
}

test "per-operation auth selects correct scheme for each operation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    // Operation 1: requires apiKey
    var op1_sec_schemes = std.StringHashMap([][]const u8).init(allocator);
    try op1_sec_schemes.put(try allocator.dupe(u8, "apiKeyAuth"), &.{});
    const op1_sec = try allocator.dupe(common.SecurityRequirement, &.{
        .{ .schemes = op1_sec_schemes },
    });
    try paths.put(try allocator.dupe(u8, "/v1/apiKeyOp"), .{
        .get = .{
            .operationId = "apiKeyOp",
            .security = op1_sec,
            .responses = try responseMap(allocator),
        },
    });

    // Operation 2: requires bearer
    var op2_sec_schemes = std.StringHashMap([][]const u8).init(allocator);
    try op2_sec_schemes.put(try allocator.dupe(u8, "bearerAuth"), &.{});
    const op2_sec = try allocator.dupe(common.SecurityRequirement, &.{
        .{ .schemes = op2_sec_schemes },
    });
    // Need to get the PathItem for second path; we already have first, now add second path item
    // We add a second entry with different path
    try paths.put(try allocator.dupe(u8, "/v1/bearerOp"), .{
        .get = .{
            .operationId = "bearerOp",
            .security = op2_sec,
            .responses = try responseMap(allocator),
        },
    });

    var document: common.UnifiedDocument = .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
    defer document.deinit(allocator);

    const schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);
    document.security_schemes = schemes;
    try schemes.put(try allocator.dupe(u8, "bearerAuth"), .bearer);
    try schemes.put(try allocator.dupe(u8, "apiKeyAuth"), .{
        .api_key_header = .{ .name = try allocator.dupe(u8, "x-api-key") },
    });

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // Both auth header strings must appear in generated code for respective operations
    try std.testing.expect(std.mem.indexOf(u8, code, "x-api-key") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "Bearer") != null);
    // Verify per-operation functions contain correct auth
    const api_key_fn = std.mem.indexOf(u8, code, "pub fn apiKeyOpRaw") orelse unreachable;
    const bearer_fn = std.mem.indexOf(u8, code, "pub fn bearerOpRaw") orelse unreachable;
    const api_key_header_pos = std.mem.indexOf(u8, code, "\"x-api-key\"") orelse unreachable;
    const bearer_header_pos = std.mem.indexOf(u8, code, "\"Bearer") orelse unreachable;
    // apiKey header should appear near apiKeyOp (before bearerOp) and bearer header near bearerOp
    // This checks that each operation's generated function has its own auth, not just global
    try std.testing.expect(api_key_header_pos > api_key_fn);
    try std.testing.expect(bearer_header_pos > bearer_fn);
    // Global appendClientHeaders should not contain both (it should be neutral or per-op)
    // At minimum, per-op code must have both; global duplication is okay but per-op is required
}

test "operation with empty security emits no auth header" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    // Operation with explicit no-auth (security: [])
    const empty_sec = try allocator.alloc(common.SecurityRequirement, 0);
    try paths.put(try allocator.dupe(u8, "/v1/noAuthOp"), .{
        .get = .{
            .operationId = "noAuthOp",
            .security = empty_sec,
            .responses = try responseMap(allocator),
        },
    });

    var document: common.UnifiedDocument = .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
    defer document.deinit(allocator);

    const schemes = try allocator.create(std.StringHashMap(common.SecurityScheme));
    schemes.* = std.StringHashMap(common.SecurityScheme).init(allocator);
    document.security_schemes = schemes;
    try schemes.put(try allocator.dupe(u8, "bearerAuth"), .bearer);
    try schemes.put(try allocator.dupe(u8, "apiKeyAuth"), .{
        .api_key_header = .{ .name = try allocator.dupe(u8, "x-api-key") },
    });
    // Document-level security would normally pick apiKey, but operation explicitly disables auth
    var doc_sec_schemes = std.StringHashMap([][]const u8).init(allocator);
    try doc_sec_schemes.put(try allocator.dupe(u8, "apiKeyAuth"), &.{});
    const doc_sec = try allocator.dupe(common.SecurityRequirement, &.{
        .{ .schemes = doc_sec_schemes },
    });
    document.security = doc_sec;

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // With explicit no-auth, no auth header code should be emitted anywhere
    try std.testing.expect(std.mem.indexOf(u8, code, "Bearer") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "x-api-key") == null);
    // The operation's raw function should exist and not trigger auth
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn noAuthOpRaw") != null);
}
