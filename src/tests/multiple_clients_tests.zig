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
    operation_id: ?[]const u8,
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

fn buildPerEndpointFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    // Duplicate operationId "getPetById" on two paths → GetPetById, GetPetById_ (ordered by path+method).
    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try opWithTags(allocator, "getPetById", false, false, true, null),
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try opWithTags(allocator, "getPetById", true, false, true, null),
    });
    try paths.put(try allocator.dupe(u8, "/store/order"), .{
        .post = try opWithTags(allocator, "placeOrder", false, true, true, null),
    });
    // No operationId → method+path derived fallback struct name.
    try paths.put(try allocator.dupe(u8, "/search"), .{
        .get = try opWithTags(allocator, null, false, false, true, null),
    });
    // Streaming operation → executeStreaming/executeStreamingEvents.
    var stream_op = try opWithTags(allocator, "streamPets", false, true, true, null);
    stream_op.streaming = true;
    try paths.put(try allocator.dupe(u8, "/stream"), .{
        .post = stream_op,
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
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
    // Streaming operation → {opId}Streaming / {opId}StreamEvents methods.
    var stream_op = try opWithTags(allocator, "streamPets", false, true, true, &.{"pet"});
    stream_op.streaming = true;
    try paths.put(try allocator.dupe(u8, "/stream"), .{
        .post = stream_op,
    });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

fn buildCollisionFixture(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    // Tag "store" would produce StoreClient, which collides with the StoreClient model below.
    try paths.put(try allocator.dupe(u8, "/store"), .{
        .get = try opWithTags(allocator, "listStore", false, false, true, &.{"store"}),
    });
    // Tag "pet": two operations whose sanitized methods collide ("getPet" from get-pet and getPet).
    try paths.put(try allocator.dupe(u8, "/pets"), .{
        .get = try opWithTags(allocator, "get-pet", false, false, true, &.{"pet"}),
    });
    try paths.put(try allocator.dupe(u8, "/pets/{petId}"), .{
        .get = try opWithTags(allocator, "getPet", true, false, true, &.{"pet"}),
    });
    // Reserved method name: operationId "init" sanitizes to "init".
    try paths.put(try allocator.dupe(u8, "/init"), .{
        .post = try opWithTags(allocator, "init", false, true, true, &.{"pet"}),
    });
    // Tag "Pet" (uppercase) sanitizes to the same PetClient as tag "pet" and merges.
    try paths.put(try allocator.dupe(u8, "/users"), .{
        .get = try opWithTags(allocator, "listUsers", false, false, true, &.{"Pet"}),
    });

    var schemas = std.StringHashMap(common.Schema).init(allocator);
    errdefer schemas.deinit();
    try schemas.put(try allocator.dupe(u8, "StoreClient"), .{ .type = .object });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
        .schemas = schemas,
    };
}

test "multiple-clients PerEndpoint generates one struct per operation with init + execute parity" {
    const allocator = std.testing.allocator;
    var document = try buildPerEndpointFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_endpoint,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // One flat top-level struct per operation, named PascalCase(operationId).
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const GetPetById = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const PlaceOrder = struct {") != null);

    // Duplicate operationId "getPetById" on /pets/{petId} → GetPetById_ (ordered by path+method).
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const GetPetById_ = struct {") != null);

    // init returns a struct holding the base Client.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init(client: *Client) GetPetById {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "    client: *Client,") != null);

    // execute delegates to the flat function.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn execute(self: *GetPetById) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPetById(self.client);") != null);

    // executeRaw and executeResult parity.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeRaw(self: *GetPetById) !RawResponse {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPetByIdRaw(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeResult(self: *GetPetById) !ApiResult(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPetByIdResult(self.client);") != null);

    // Path parameters flow through to the flat function.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn execute(self: *GetPetById_, petId: i64) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return getPetById(self.client, petId);") != null);

    // Body parameters use requestBody.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn execute(self: *PlaceOrder, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return placeOrder(self.client, requestBody);") != null);

    // No operationId → method+path derived fallback struct name, delegating to the flat fallback function.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const GetSearch = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return @\"operationsearch\"(self.client);") != null);
    // No Raw/Result flat functions exist for a fallback-named operation → no executeRaw/executeResult.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeRaw(self: *GetSearch") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeResult(self: *GetSearch") == null);

    // Streaming parity: executeStreaming and executeStreamingEvents delegate to flat functions.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const StreamPets = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeStreaming(self: *StreamPets, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return streamPetsStreaming(self.client, requestBody, callback, cancellation_token);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn executeStreamingEvents(comptime Event: type, self: *StreamPets, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return streamPetsStreamingEvents(Event, self.client, requestBody, callback, cancellation_token);") != null);
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

    // Method names that match flat function names (e.g. listPets) are resolved
    // through file-scope aliases so the delegation is not an ambiguous reference.
    try std.testing.expect(std.mem.indexOf(u8, code, "const _listPets = listPets;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const _listPetsRaw = listPetsRaw;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const _listPetsResult = listPetsResult;") != null);

    // Full triplet parity: main, Raw, Result.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPets(self: *PetClient) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _listPets(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsRaw(self: *PetClient) !RawResponse {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _listPetsRaw(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listPetsResult(self: *PetClient) !ApiResult(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _listPetsResult(self.client);") != null);

    // Path parameters and body parameters flow through the delegation.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPetById(self: *PetClient, petId: i64) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _getPetById(self.client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn placeOrder(self: *StoreClient, requestBody: std.json.Value) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _placeOrder(self.client, requestBody);") != null);

    // Untagged operations land in DefaultClient.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn searchUntagged(self: *DefaultClient) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _searchUntagged(self.client);") != null);

    // Streaming parity: {opId}Streaming and {opId}StreamEvents methods delegate to flat functions.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn streamPetsStreaming(self: *PetClient, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _streamPetsStreaming(self.client, requestBody, callback, cancellation_token);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const _streamPetsStreaming = streamPetsStreaming;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn streamPetsStreamEvents(comptime Event: type, self: *PetClient, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return streamPetsStreamingEvents(Event, self.client, requestBody, callback, cancellation_token);") != null);
}

test "multiple-clients PerTag dedupes struct names, reserved methods, and method collisions" {
    const allocator = std.testing.allocator;
    var document = try buildCollisionFixture(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_tag,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    // Tag "store" collides with the StoreClient model → StoreClient_.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const StoreClient_ = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const StoreClient = struct {") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listStore(self: *StoreClient_") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init(client: *Client) StoreClient_ {") != null);

    // Tags "pet" and "Pet" merge into a single PetClient (case/punctuation dedupe).
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const PetClient = struct {") != null);

    // Reserved method name "init" → init_. The flat fn `init` exists, so the
    // delegation resolves through the `_init` alias.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn init_(self: *PetClient") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _init(self.client, requestBody);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const _init = init;") != null);

    // Method collision: get-pet and getPet both sanitize to getPet → getPet, getPet_.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPet(self: *PetClient) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return @\"get-pet\"(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn getPet_(self: *PetClient, petId: i64) !Owned(std.json.Value) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _getPet(self.client, petId);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const _getPet = getPet;") != null);

    // The "Pet" tag operation landed in the merged PetClient too.
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn listUsers(self: *PetClient") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "return _listUsers(self.client);") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "const _listUsers = listUsers;") != null);
}
