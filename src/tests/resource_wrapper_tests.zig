const std = @import("std");
const cli = @import("../cli.zig");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const common = @import("../models/common/document.zig");
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;

fn responseMap(allocator: std.mem.Allocator, with_schema: bool) !std.StringHashMap(common.Response) {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, if (with_schema) "200" else "204"), .{
        .description = "ok",
        .schema = if (with_schema) common.Schema{ .type = .object } else null,
    });
    return responses;
}

fn dupTags(allocator: std.mem.Allocator, tags: []const []const u8) ![][]const u8 {
    const out = try allocator.alloc([]const u8, tags.len);
    for (tags, 0..) |tag, i| out[i] = tag;
    return out;
}

fn op(allocator: std.mem.Allocator, operation_id: []const u8, method: []const u8, has_body: bool, has_path_param: bool, has_response: bool) !common.Operation {
    return opWithTags(allocator, operation_id, method, has_body, has_path_param, has_response, null);
}

fn opWithTags(
    allocator: std.mem.Allocator,
    operation_id: []const u8,
    method: []const u8,
    has_body: bool,
    has_path_param: bool,
    has_response: bool,
    tags: ?[]const []const u8,
) !common.Operation {
    var params = std.ArrayList(common.Parameter).empty;
    errdefer params.deinit(allocator);
    const owned_tags = if (tags) |provided_tags| try dupTags(allocator, provided_tags) else null;
    errdefer if (owned_tags) |value| allocator.free(value);

    if (has_path_param) {
        try params.append(allocator, .{
            .name = "petId",
            .location = .path,
            .required = true,
            .type = .integer,
        });
    }
    if (has_body) {
        try params.append(allocator, .{
            .name = "body",
            .location = .body,
            .required = true,
            .schema = .{ .type = .object },
        });
    }

    _ = method;
    return .{
        .tags = owned_tags,
        .operationId = operation_id,
        .parameters = if (params.items.len == 0) null else try params.toOwnedSlice(allocator),
        .responses = try responseMap(allocator, has_response),
    };
}

fn buildFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try op(allocator, "listPets", "GET", false, false, true),
        .post = try op(allocator, "createPet", "POST", true, false, true),
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try op(allocator, "getPet", "GET", false, true, true),
        .delete = try op(allocator, "deletePet", "DELETE", false, true, false),
    });
    try paths.put(try allocator.dupe(u8, "/chat/completions"), .{
        .post = try op(allocator, "createChatCompletion", "POST", true, false, true),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

fn buildOperationNameCollisionFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    try paths.put(try allocator.dupe(u8, "/api/v1/chat"), .{
        .post = try opWithTags(allocator, "chat", "POST", true, false, true, &.{"chat"}),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "resource wrappers derive from paths" {
    const allocator = std.testing.allocator;
    var document = try buildFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .paths,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const resources = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const pets = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn list(client: *Client)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsResult(client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsRaw(client: *Client) !RawResponse") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listResult(client: *Client) !ApiResult(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsResult(client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn create(client: *Client, requestBody: std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return createPet(client, requestBody);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn createPetRaw(client: *Client, requestBody: std.json.Value) !RawResponse") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn createResult(client: *Client, requestBody: std.json.Value) !ApiResult(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return createPetResult(client, requestBody);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn get(client: *Client, petId: i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPet(client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPetRaw(client: *Client, petId: i64) !RawResponse") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPetResult(client: *Client, petId: i64) !ApiResult(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getResult(client: *Client, petId: i64) !ApiResult(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn delete(client: *Client, petId: i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return deletePet(client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const chat = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const completions = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return createChatCompletion(client, requestBody);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return createChatCompletionResult(client, requestBody);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const chat = resources.chat;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const pets = resources.pets;") != null);
}

test "resource wrapper aliases skip top-level operation name collisions" {
    const allocator = std.testing.allocator;
    const modes = [_]cli.ResourceWrapperMode{ .tags, .hybrid };

    for (modes) |mode| {
        var document = try buildOperationNameCollisionFixture(allocator);
        defer document.deinit(allocator);

        var generator = UnifiedApiGenerator.init(allocator, .{
            .input_path = "fixture.json",
            .resource_wrappers = mode,
        });
        defer generator.deinit();

        const code = try generator.generate(document);
        defer allocator.free(code);

        try std.testing.expect(std.mem.indexOf(u8, code, "const _chat = chat;") != null);
        try std.testing.expect(std.mem.indexOf(u8, code, "pub const resources = struct") != null);
        try std.testing.expect(std.mem.indexOf(u8, code, "pub const chat = struct") != null);
        try std.testing.expect(std.mem.indexOf(u8, code, "pub fn chat_(client: *Client, requestBody: std.json.Value)") != null);
        try std.testing.expect(std.mem.indexOf(u8, code, "pub const chat = resources.chat;") == null);
    }
}

fn buildModelNameCollisionFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    try paths.put(try allocator.dupe(u8, "/installation/repositories"), .{
        .get = try opWithTags(allocator, "listInstallationRepos", "GET", false, false, true, null),
    });

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    errdefer schemas.deinit();
    try schemas.put(try allocator.dupe(u8, "installation"), .{ .type = .object });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };
}

test "resource wrapper aliases skip model type name collisions" {
    const allocator = std.testing.allocator;
    var document = try buildModelNameCollisionFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .paths,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // A schema named "installation" declares a top-level `installation` type in
    // single-file output, so the resource alias must not redeclare the name.
    try std.testing.expect(std.mem.indexOf(u8, code, "    pub const installation = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const installation = resources.installation;") == null);
}

fn buildParameterShadowsModelFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    var params = std.ArrayList(common.Parameter).empty;
    errdefer params.deinit(allocator);
    try params.append(allocator, .{
        .name = "page",
        .location = .query,
        .required = false,
        .type = .integer,
    });

    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, "200"), .{ .description = "ok" });

    try paths.put(try allocator.dupe(u8, "/issues"), .{
        .get = .{
            .operationId = "listIssues",
            .parameters = try params.toOwnedSlice(allocator),
            .responses = responses,
        },
    });

    var page_properties = std.StringHashMap(common.Schema).init(allocator);
    errdefer page_properties.deinit();
    try page_properties.put(try allocator.dupe(u8, "url"), .{ .type = .string });

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    errdefer schemas.deinit();
    try schemas.put(try allocator.dupe(u8, "page"), .{ .type = .object, .properties = page_properties });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };
}

test "flat parameters do not shadow inlined model type names" {
    const allocator = std.testing.allocator;
    var document = try buildParameterShadowsModelFixture(allocator);
    defer document.deinit(allocator);

    // Single-file output joins the models and the client, so both share one
    // top-level namespace, exactly as generateCodeFromUnifiedDocument builds it.
    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const models_code = try model_generator.generate(document);
    defer allocator.free(models_code);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    const api_code = try generator.generate(document);
    defer allocator.free(api_code);

    const code = try std.mem.join(allocator, "\n", &.{ models_code, api_code });
    defer allocator.free(code);

    // Zig rejects a function parameter that shadows a top-level declaration, and
    // a schema named "page" declares exactly such a top-level type.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const page = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "page: ?i64") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "page_param: ?i64") != null);
}

fn buildWrapperShadowsModelFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, "200"), .{
        .description = "ok",
        .schema = .{ .type = .reference, .ref = "#/components/schemas/installation" },
    });

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();
    try paths.put(try allocator.dupe(u8, "/apps/installation"), .{
        .get = .{ .operationId = "getInstallation", .responses = responses },
    });

    var properties = std.StringHashMap(common.Schema).init(allocator);
    errdefer properties.deinit();
    try properties.put(try allocator.dupe(u8, "app_id"), .{ .type = .integer });

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    errdefer schemas.deinit();
    try schemas.put(try allocator.dupe(u8, "installation"), .{ .type = .object, .properties = properties });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };
}

test "wrapper bodies reference models unambiguously when a wrapper shares a model name" {
    const allocator = std.testing.allocator;
    var document = try buildWrapperShadowsModelFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .paths,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // The wrapper struct `resources.apps.installation` makes a bare `installation`
    // inside `resources.apps` ambiguous with the top-level model of that name, so
    // wrapper bodies must reach the model through the file-scope alias.
    try std.testing.expect(std.mem.indexOf(u8, code, "const _root = @This();") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_root.installation") != null);
}
