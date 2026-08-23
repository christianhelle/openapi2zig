const std = @import("std");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const common = @import("../models/common/document.zig");

fn responseMap(allocator: std.mem.Allocator, with_schema: bool) !std.StringHashMap(common.Response) {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, if (with_schema) "200" else "204"), .{
        .description = "ok",
        .schema = if (with_schema) common.Schema{ .type = .object } else null,
    });
    return responses;
}

fn op(allocator: std.mem.Allocator, operation_id: []const u8, params: []common.Parameter, has_response: bool) !common.Operation {
    return .{
        .operationId = operation_id,
        .parameters = if (params.len == 0) null else params,
        .responses = try responseMap(allocator, has_response),
    };
}

fn buildFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const list_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .schema = .{ .type = .integer } },
        .{ .name = "status", .location = .query, .schema = .{ .type = .string } },
    });
    const create_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "body", .location = .body, .required = true, .schema = .{ .type = .object } },
    });
    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try op(allocator, "listPets", list_params, true),
        .post = try op(allocator, "createPet", create_params, true),
    });

    const get_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "petId", .location = .path, .required = true, .schema = .{ .type = .integer } },
        .{ .name = "verbose", .location = .query, .schema = .{ .type = .boolean } },
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try op(allocator, "getPet", get_params, true),
    });

    const chat_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "stream", .location = .query, .schema = .{ .type = .boolean } },
        .{ .name = "body", .location = .body, .required = true, .schema = .{ .type = .object } },
    });
    try paths.put(try allocator.dupe(u8, "/chat/completions"), .{
        .post = try op(allocator, "createChatCompletion", chat_params, true),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "flat signature wraps non-body parameters in an options struct" {
    const allocator = std.testing.allocator;
    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(client: *Client, options: struct { limit: ?i64 = null, status: ?[]const u8 = null }) !Owned(std.json.Value) {") != null);
}

test "Raw and Result functions share the options struct signature" {
    const allocator = std.testing.allocator;
    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsRaw(client: *Client, options: struct { limit: ?i64 = null, status: ?[]const u8 = null }) !RawResponse {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsResult(client: *Client, options: struct { limit: ?i64 = null, status: ?[]const u8 = null }) !ApiResult(std.json.Value) {") != null);
}

test "path parameters are required fields in the options struct" {
    const allocator = std.testing.allocator;
    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(client: *Client, options: struct { petId: i64, verbose: ?bool = null }) !Owned(std.json.Value) {") != null);
}

test "body parameter stays an individual argument" {
    const allocator = std.testing.allocator;
    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn createPet(client: *Client, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
}

test "options struct composes with a body parameter" {
    const allocator = std.testing.allocator;
    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn createChatCompletion(client: *Client, options: struct { stream: ?bool = null }, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
}