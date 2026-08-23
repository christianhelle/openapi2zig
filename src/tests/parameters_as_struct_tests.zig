const std = @import("std");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const common = @import("../models/common/document.zig");
const test_utils = @import("test_utils.zig");

fn responseMap(allocator: std.mem.Allocator, with_schema: bool) !std.StringHashMap(common.Response) {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, if (with_schema) "200" else "204"), .{
        .description = "ok",
        .schema = if (with_schema) common.Schema{ .type = .object } else null,
    });
    return responses;
}

fn op(allocator: std.mem.Allocator, operation_id: ?[]const u8, params: []common.Parameter, has_response: bool) !common.Operation {
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

    const pets2_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/pets2"), .{
        .get = try op(allocator, null, pets2_params, true),
    });

    const search_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "X-Request-Id", .location = .header, .schema = .{ .type = .string } },
    });
    try paths.put(try allocator.dupe(u8, "/search"), .{
        .get = try op(allocator, "search", search_params, true),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "flat signature wraps non-body parameters in an options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const listPetsOptions = struct {\n    limit: ?i64 = null,\n    status: ?[]const u8 = null,\n};") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(client: *Client, options: listPetsOptions) !Owned(std.json.Value) {") != null);
}

test "Raw and Result functions share the options struct signature" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsRaw(client: *Client, options: listPetsOptions) !RawResponse {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsResult(client: *Client, options: listPetsOptions) !ApiResult(std.json.Value) {") != null);
}

test "path parameters are required fields in the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const getPetOptions = struct {\n    petId: i64,\n    verbose: ?bool = null,\n};") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(client: *Client, options: getPetOptions) !Owned(std.json.Value) {") != null);
}

test "body parameter stays an individual argument" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn createPet(client: *Client, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
}

test "options struct composes with a body parameter" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn createChatCompletion(client: *Client, options: createChatCompletionOptions, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
}

test "optional query parameters are read from the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "if (options.limit) |value| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "try appendQueryParam(&uri_buf.writer, &first_query, \"limit\", value);") != null);
}

test "path parameters are read from the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "try uri_buf.writer.print(\"{s}/pets/{d}\", .{ client.base_url, options.petId });") != null);
}

test "optional header parameters are nullable fields in the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const searchOptions = struct {\n    @\"X-Request-Id\": ?[]const u8 = null,\n};") != null);
}

test "header parameters are read from the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "_ = options.@\"X-Request-Id\";") != null);
}

test "operations without an operation id read query parameters from the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const @\"operationpets2Options\" = struct {\n    limit: ?i64 = null,\n};") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn @\"operationpets2\"(client: *Client, options: @\"operationpets2Options\") !Owned(std.json.Value) {") != null);
    // listPetsRaw and the direct fallback function both encode the limit query parameter
    try std.testing.expect(countOccurrences(code, "try appendQueryParam(&uri_buf.writer, &first_query, \"limit\", value);") == 2);
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var rest = haystack;
    while (std.mem.indexOf(u8, rest, needle)) |idx| {
        count += 1;
        rest = rest[idx + needle.len ..];
    }
    return count;
}

test "tag client methods wrap parameters in the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .multiple_clients = .per_tag,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(self: *DefaultClient, options: listPetsOptions) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _listPets(self.client, options);") != null);
}

test "endpoint client execute wraps parameters in the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .multiple_clients = .per_endpoint,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn execute(self: *ListPets, options: listPetsOptions) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPets(self.client, options);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeRaw(self: *ListPets, options: listPetsOptions) !RawResponse {") != null);
}

test "resource wrapper methods wrap parameters in the options struct" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .paths,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn list(client: *Client, options: listPetsOptions) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPets(client, options);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listResult(client: *Client, options: listPetsOptions) !ApiResult(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsResult(client, options);") != null);
}

fn buildOperationCollisionFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const list_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/foo"), .{
        .get = try op(allocator, "foo", list_params, true),
    });

    const body_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "body", .location = .body, .required = true, .schema = .{ .type = .object } },
    });
    try paths.put(try allocator.dupe(u8, "/fooOptions"), .{
        .get = try op(allocator, "fooOptions", body_params, true),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "options type name is disambiguated when an operation shares it" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildOperationCollisionFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const fooOptions_ = struct {\n    limit: ?i64 = null,\n};") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn foo(client: *Client, options: fooOptions_) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn fooOptions(client: *Client, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
}

test "disambiguated options type name is shared by tag client methods" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildOperationCollisionFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .multiple_clients = .per_tag,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn foo(self: *DefaultClient, options: fooOptions_) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _foo(self.client, options);") != null);
}

fn buildSchemaCollisionFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/pets2"), .{
        .get = try op(allocator, null, params, true),
    });

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    errdefer schemas.deinit();
    try schemas.put(try allocator.dupe(u8, "operationpets2Options"), .{ .type = .object });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };
}

test "fallback options type name avoids schema declarations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildSchemaCollisionFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const @\"operationpets2Options_\" = struct {\n    limit: ?i64 = null,\n};") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn @\"operationpets2\"(client: *Client, options: @\"operationpets2Options_\") !Owned(std.json.Value) {") != null);
}

fn buildEndpointCollisionFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    const list_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "limit", .location = .query, .schema = .{ .type = .integer } },
    });
    try paths.put(try allocator.dupe(u8, "/Foo"), .{
        .get = try op(allocator, "Foo", list_params, true),
    });

    const body_params = try allocator.dupe(common.Parameter, &.{
        .{ .name = "body", .location = .body, .required = true, .schema = .{ .type = .object } },
    });
    try paths.put(try allocator.dupe(u8, "/fooOptions"), .{
        .get = try op(allocator, "fooOptions", body_params, true),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "endpoint client struct names avoid reserved options types" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var document = try buildEndpointCollisionFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .parameters_as_struct = true,
        .multiple_clients = .per_endpoint,
        .resource_wrappers = .none,
    });
    defer generator.deinit(allocator);

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const FooOptions = struct {\n    limit: ?i64 = null,\n};") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const FooOptions_ = struct {") != null);
}
