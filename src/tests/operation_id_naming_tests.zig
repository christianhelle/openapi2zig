const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const models = @import("../models.zig");
const cli = @import("../cli.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;

// Real specifications such as the GitHub REST API use operation ids that are
// not valid Zig identifiers, e.g. "repos/list-pull-requests-associated-with-commit".
const spec_with_slashed_operation_id =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Naming", "version": "1.0.0" },
    \\  "paths": {
    \\    "/repos/{owner}/{repo}/commits/{commit_sha}/pulls": {
    \\      "get": {
    \\        "operationId": "repos/list-pull-requests-associated-with-commit",
    \\        "parameters": [
    \\          { "name": "owner", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "repo", "in": "path", "required": true, "schema": { "type": "string" } },
    \\          { "name": "commit_sha", "in": "path", "required": true, "schema": { "type": "string" } }
    \\        ],
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

// Camel casing collapses "get-pet" and "getPet" onto the same name, so one of
// the two flat functions has to be disambiguated.
const spec_with_colliding_operation_ids =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Naming", "version": "1.0.0" },
    \\  "paths": {
    \\    "/a/pet": {
    \\      "get": {
    \\        "operationId": "get-pet",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    },
    \\    "/b/pet": {
    \\      "get": {
    \\        "operationId": "getPet",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

// GitHub declares both "markdown/render" and "markdown/render-raw". The first
// one already owns the markdownRenderRaw declaration through its Raw variant.
const spec_with_variant_collision =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Naming", "version": "1.0.0" },
    \\  "paths": {
    \\    "/markdown": {
    \\      "get": {
    \\        "operationId": "markdown/render",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    },
    \\    "/markdown/raw": {
    \\      "get": {
    \\        "operationId": "markdown/render-raw",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

// A streaming POST declares {op}Streaming and {op}StreamingEvents on top of the
// usual functions, so those names are taken for any other operation too.
const spec_with_streaming_collision =
    \\{
    \\  "openapi": "3.0.0",
    \\  "info": { "title": "Naming", "version": "1.0.0" },
    \\  "paths": {
    \\    "/chat": {
    \\      "post": {
    \\        "operationId": "foo",
    \\        "requestBody": {
    \\          "content": { "application/json": { "schema": { "type": "object" } } }
    \\        },
    \\        "responses": {
    \\          "200": {
    \\            "description": "ok",
    \\            "content": { "text/event-stream": { "schema": { "type": "string" } } }
    \\          }
    \\        }
    \\      }
    \\    },
    \\    "/other": {
    \\      "get": {
    \\        "operationId": "foo-streaming-events",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  }
    \\}
;

fn generateClient(allocator: std.mem.Allocator, spec: []const u8, args: cli.CliArgs) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, args);
    defer generator.deinit();
    return generator.generate(unified);
}

test "operation ids that are not valid identifiers generate camel case functions" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_slashed_operation_id, .{ .input_path = "fixture.json" });
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub fn reposListPullRequestsAssociatedWithCommit(") != null);
    try testing.expect(std.mem.indexOf(u8, code, "@\"repos/list-pull-requests-associated-with-commit\"") == null);
}

test "operation ids that camel case to the same name stay distinct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_colliding_operation_ids, .{ .input_path = "fixture.json" });
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(client: *Client) ") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pub fn getPet_(client: *Client) ") != null);
}

test "operation names avoid the Raw and Result variants of other operations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_variant_collision, .{ .input_path = "fixture.json" });
    defer allocator.free(code);

    // "markdown/render" already declares markdownRenderRaw, so the operation
    // named after it has to move aside.
    try testing.expect(std.mem.indexOf(u8, code, "pub fn markdownRender(client: *Client) ") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pub fn markdownRenderRaw(client: *Client) !RawResponse {") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pub fn markdownRenderRaw_(client: *Client) ") != null);
}

test "operation names avoid the streaming helpers of other operations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator, spec_with_streaming_collision, .{ .input_path = "fixture.json" });
    defer allocator.free(code);

    // The streaming POST declares fooStreaming and fooStreamingEvents, so the
    // operation whose id camel cases onto the latter has to move aside.
    try testing.expect(std.mem.indexOf(u8, code, "pub fn fooStreamingEvents(comptime Event: type, client: *Client") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pub fn fooStreamingEvents_(client: *Client) ") != null);
}
