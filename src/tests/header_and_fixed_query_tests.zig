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
}

test "header parameters do not shadow generated header locals" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "headers", .location = .header, .required = true, .schema = .{ .type = .string } },
        .{ .name = "header_values", .location = .header, .required = true, .schema = .{ .type = .string } },
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

    try std.testing.expect(std.mem.indexOf(u8, code, "getHeadersRaw(client: *Client, headers: []const u8, header_values: []const u8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var operation_headers = std.ArrayList(std.http.Header).empty;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "var operation_header_values = std.ArrayList([]u8).empty;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "&operation_headers, \"headers\", header_value") != null);
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
