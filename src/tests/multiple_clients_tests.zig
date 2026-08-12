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

fn opWithTags(
    allocator: std.mem.Allocator,
    operation_id: []const u8,
    has_path_param: bool,
    has_body: bool,
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

    return .{
        .tags = owned_tags,
        .operationId = operation_id,
        .parameters = if (params.items.len == 0) null else try params.toOwnedSlice(allocator),
        .responses = try responseMap(allocator, has_response),
    };
}

fn buildPerTagFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try opWithTags(allocator, "listPets", false, false, true, &.{"pet"}),
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try opWithTags(allocator, "getPetById", true, false, true, &.{"pet"}),
    });
    try paths.put(try allocator.dupe(u8, "/store/order"), .{
        .post = try opWithTags(allocator, "placeOrder", false, true, true, &.{"store"}),
    });
    try paths.put(try allocator.dupe(u8, "/users"), .{
        .get = try opWithTags(allocator, "listUsers", false, false, true, &.{"user"}),
    });
    try paths.put(try allocator.dupe(u8, "/search"), .{
        .get = try opWithTags(allocator, "searchUntagged", false, false, true, null),
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "multiple-clients PerTag groups operations into client structs" {
    const allocator = std.testing.allocator;
    var document = try buildPerTagFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // Client structs per tag, plus DefaultClient for untagged operations.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const PetClient = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const StoreClient = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const UserClient = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const DefaultClient = struct {") != null);

    // Each client holds a Client pointer and exposes init.
    try std.testing.expect(std.mem.indexOf(u8, code, "    client: *Client,") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init(client: *Client) PetClient {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init(client: *Client) StoreClient {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init(client: *Client) DefaultClient {") != null);

    // Full triplet parity: main, Raw, Result.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(self: *PetClient) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPets(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsRaw(self: *PetClient) !RawResponse {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsRaw(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsResult(self: *PetClient) !ApiResult(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return listPetsResult(self.client);") != null);

    // Path parameters and body parameters flow through the delegation.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPetById(self: *PetClient, petId: i64) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPetById(self.client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn placeOrder(self: *StoreClient, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return placeOrder(self.client, requestBody);") != null);

    // Untagged operations land in DefaultClient.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn searchUntagged(self: *DefaultClient) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return searchUntagged(self.client);") != null);
}
