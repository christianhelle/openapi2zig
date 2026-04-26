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

fn op(allocator: std.mem.Allocator, operation_id: []const u8, method: []const u8, has_body: bool, has_path_param: bool, has_response: bool) !common.Operation {
    var params = std.ArrayList(common.Parameter).empty;
    errdefer params.deinit(allocator);

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
