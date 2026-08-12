const std = @import("std");
const cli = @import("../cli.zig");
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

/// Fixture with operations spread across pet/store/user tags plus one
/// untagged operation that must land in DefaultClient.
fn buildTaggedFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try opWithTags(allocator, "listPets", "GET", false, false, true, &.{"pet"}),
        .post = try opWithTags(allocator, "createPet", "POST", true, false, true, &.{"pet"}),
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try opWithTags(allocator, "getPet", "GET", false, true, true, &.{"pet"}),
        .delete = try opWithTags(allocator, "deletePet", "DELETE", false, true, false, &.{"pet"}),
    });
    try paths.put(try allocator.dupe(u8, "/store/order"), .{
        .post = try opWithTags(allocator, "placeOrder", "POST", true, false, true, &.{"store"}),
    });
    try paths.put(try allocator.dupe(u8, "/users"), .{
        .get = try opWithTags(allocator, "listUsers", "GET", false, false, true, &.{"user"}),
    });
    try paths.put(try allocator.dupe(u8, "/health"), .{
        .get = try op(allocator, "healthCheck", "GET", false, false, true),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "per-tag clients group operations by first tag" {
    const allocator = std.testing.allocator;
    var document = try buildTaggedFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const PetClient = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const StoreClient = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const UserClient = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const DefaultClient = struct") != null);
}

test "per-tag clients wrap the base client with an init constructor" {
    const allocator = std.testing.allocator;
    var document = try buildTaggedFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "    client: *Client,") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init(client: *Client) PetClient {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "        return .{ .client = client };") != null);
}

test "per-tag clients delegate to flat functions with full operation names" {
    const allocator = std.testing.allocator;
    var document = try buildTaggedFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // Main operation methods delegate to the flat functions.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(self: *PetClient) !Owned(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPets(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(self: *PetClient, petId: i64) !Owned(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPet(self.client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn deletePet(self: *PetClient, petId: i64) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return deletePet(self.client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn placeOrder(self: *StoreClient, requestBody: std.json.Value) !Owned(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return placeOrder(self.client, requestBody);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listUsers(self: *UserClient) !Owned(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn healthCheck(self: *DefaultClient) !Owned(std.json.Value)") != null);
}

test "per-tag clients expose Raw and Result parity" {
    const allocator = std.testing.allocator;
    var document = try buildTaggedFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsRaw(self: *PetClient) !RawResponse") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsRaw(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsResult(self: *PetClient) !ApiResult(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsResult(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn deletePetRaw(self: *PetClient, petId: i64) !RawResponse") != null);
    // Operations without a response schema get Raw but no Result.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn deletePetResult(self: *PetClient") == null);
}

test "per-tag clients keep the flat functions and base client" {
    const allocator = std.testing.allocator;
    var document = try buildTaggedFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const Client = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(client: *Client) !Owned(std.json.Value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(client: *Client, petId: i64) !Owned(std.json.Value)") != null);
}

test "per-tag clients are not emitted without the flag" {
    const allocator = std.testing.allocator;
    var document = try buildTaggedFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const PetClient = struct") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const DefaultClient = struct") == null);
}
