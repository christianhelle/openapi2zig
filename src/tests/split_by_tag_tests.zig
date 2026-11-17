const std = @import("std");
const models = @import("../models.zig");
const generator = @import("../generator.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{" ++
    "\"/pets/{id}\":{\"get\":{\"tags\":[\"pets.pet\"],\"operationId\":\"pets.GetPet\",\"parameters\":[{\"name\":\"id\",\"in\":\"path\",\"required\":true,\"schema\":{\"type\":\"string\"}},{\"name\":\"$select\",\"in\":\"query\",\"schema\":{\"type\":\"string\"}}],\"responses\":{\"200\":{\"description\":\"ok\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/Pet\"}}}}}}}," ++
    "\"/pets\":{\"post\":{\"tags\":[\"pets.pet\"],\"operationId\":\"pets.CreatePet\",\"requestBody\":{\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/Pet\"}}}},\"responses\":{\"201\":{\"description\":\"ok\"}}}}," ++
    "\"/stores\":{\"get\":{\"tags\":[\"stores\"],\"operationId\":\"stores.ListStores\",\"responses\":{\"200\":{\"description\":\"ok\"}}}}," ++
    "\"/ping\":{\"get\":{\"operationId\":\"ping\",\"responses\":{\"200\":{\"description\":\"ok\"}}}}}," ++
    "\"components\":{\"schemas\":{\"Pet\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}}}}";

const Fixture = struct {
    parsed: models.OpenApiDocument,
    unified: @import("../models/common/document.zig").UnifiedDocument,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
        errdefer parsed.deinit(allocator);
        var converter = OpenApiConverter.init(allocator);
        const unified = try converter.convert(parsed);
        return .{ .parsed = parsed, .unified = unified };
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.unified.deinit(allocator);
        self.parsed.deinit(allocator);
    }
};

fn findFile(api: *const UnifiedApiGenerator, name: []const u8) ?[]const u8 {
    for (api.split_files.items) |file| {
        if (std.mem.eql(u8, file.name, name)) return file.content;
    }
    return null;
}

test "split mode puts each tag's operations in its own file" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var fixture = try Fixture.init(allocator);
    defer fixture.deinit(allocator);

    var api = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .multiple_files = true, .split_by_tag = true, .resource_wrappers = .none });
    api.emit_imports = true;
    defer api.deinit();
    const client = try api.generateClientOnly(fixture.unified);
    defer allocator.free(client);

    try testing.expectEqual(@as(usize, 3), api.split_files.items.len);
    const pets = findFile(&api, "client/pets_pet.zig") orelse return error.MissingFile;
    try testing.expect(findFile(&api, "client/stores.zig") != null);
    try testing.expect(findFile(&api, "client/default.zig") != null);

    try testing.expect(std.mem.indexOf(u8, pets, "pub fn petsGetPet(client: *Client, id: []const u8, @\"$select\": ?[]const u8) !Owned(Pet) {") != null);
    try testing.expect(std.mem.indexOf(u8, pets, "pub fn petsCreatePet(") != null);
    try testing.expect(std.mem.indexOf(u8, pets, "const _client_zig = @import(\"../client.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, pets, "const Client = _client_zig.Client;") != null);
    try testing.expect(std.mem.indexOf(u8, pets, "const appendQueryParam = _client_zig.appendQueryParam;") != null);

    // The client keeps its shared helpers (now public) and re-exports every operation.
    try testing.expect(std.mem.indexOf(u8, client, "pub fn appendQueryParam(") != null);
    try testing.expect(std.mem.indexOf(u8, client, "pub fn petsGetPet(") == null);
    try testing.expect(std.mem.indexOf(u8, client, "pub const petsGetPet = @import(\"client/pets_pet.zig\").petsGetPet;") != null);
    try testing.expect(std.mem.indexOf(u8, client, "pub const petsGetPetRaw = @import(\"client/pets_pet.zig\").petsGetPetRaw;") != null);
    try testing.expect(std.mem.indexOf(u8, client, "pub const ping = @import(\"client/default.zig\").ping;") != null);
}

test "split mode writes the tag files next to client.zig" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var fixture = try Fixture.init(allocator);
    defer fixture.deinit(allocator);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try generator.generateMultipleFiles(allocator, testing.io, tmp.dir, fixture.unified, .{
        .input_path = "fixture.json",
        .output_path = "out",
        .multiple_files = true,
        .split_by_tag = true,
        .resource_wrappers = .none,
    });

    const pets = try tmp.dir.readFileAlloc(testing.io, "out/client/pets_pet.zig", allocator, .unlimited);
    defer allocator.free(pets);
    try testing.expect(std.mem.indexOf(u8, pets, "pub fn petsGetPet(") != null);
    const client = try tmp.dir.readFileAlloc(testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try testing.expect(std.mem.indexOf(u8, client, "pub const petsGetPet = @import(\"client/pets_pet.zig\").petsGetPet;") != null);
}

test "split mode is off by default" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var fixture = try Fixture.init(allocator);
    defer fixture.deinit(allocator);

    var api = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .multiple_files = true, .resource_wrappers = .none });
    defer api.deinit();
    const client = try api.generateClientOnly(fixture.unified);
    defer allocator.free(client);

    try testing.expectEqual(@as(usize, 0), api.split_files.items.len);
    try testing.expect(std.mem.indexOf(u8, client, "pub fn petsGetPet(") != null);
}
