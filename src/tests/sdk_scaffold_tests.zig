const std = @import("std");
const cli = @import("../cli.zig");
const models = @import("../models.zig");
const generator = @import("../generator.zig");
const sdk_scaffold = @import("../generators/sdk/scaffold.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const spec =
    \\{
    \\  "openapi": "3.0.3",
    \\  "info": { "title": "Pets", "version": "1.0.0" },
    \\  "servers": [{ "url": "https://pets.example.com/v1" }],
    \\  "paths": {
    \\    "/pets": {
    \\      "get": {
    \\        "operationId": "listPets",
    \\        "responses": { "200": { "description": "ok", "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Pet" } } } } } }
    \\      },
    \\      "post": {
    \\        "operationId": "createPet",
    \\        "requestBody": { "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } } } },
    \\        "responses": { "201": { "description": "created" } }
    \\      }
    \\    }
    \\  },
    \\  "components": { "schemas": { "Pet": { "type": "object", "properties": { "name": { "type": "string" } } } } }
    \\}
;

const config_json =
    \\{ "name": "pets", "version": "0.3.0", "description": "Pets SDK for Zig", "repository": "https://github.com/example/pets-sdk-for-zig", "author": "Jane Doe", "spec": "openapi/openapi.json" }
;

fn exists(dir: std.Io.Dir, path: []const u8) bool {
    dir.access(testing.io, path, .{}) catch return false;
    return true;
}

fn read(allocator: std.mem.Allocator, dir: std.Io.Dir, path: []const u8) ![]u8 {
    return dir.readFileAlloc(testing.io, path, allocator, .unlimited);
}

fn runGenerate(allocator: std.mem.Allocator, dir: std.Io.Dir, force: bool) !void {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    try generator.generateCodeFromUnifiedDocument(allocator, testing.io, dir, unified, .{
        .input_path = "repo/openapi/openapi.json",
        .output_path = "repo",
        .sdk = true,
        .multiple_files = true,
        .sdk_config_path = "repo/openapi2zig.json",
        .force = force,
    });
}

test "sdk generation writes the full repository layout" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "repo");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/openapi2zig.json", .data = config_json });

    try runGenerate(allocator, tmp.dir, false);

    const expected = [_][]const u8{
        "repo/src/models.zig",
        "repo/src/runtime.zig",
        "repo/src/client.zig",
        "repo/src/root.zig",
        "repo/src/compile_check.zig",
        "repo/build.zig",
        "repo/build.zig.zon",
        "repo/README.md",
        "repo/LICENSE",
        "repo/CHANGELOG.md",
        "repo/.gitignore",
        "repo/.gitattributes",
        "repo/docs/USAGE.md",
        "repo/docs/REGENERATING.md",
        "repo/.github/workflows/ci.yml",
        "repo/.github/workflows/release.yml",
        "repo/examples/quickstart.zig",
    };
    for (expected) |path| {
        if (!exists(tmp.dir, path)) {
            std.debug.print("missing {s}\n", .{path});
            return error.MissingFile;
        }
    }

    const root = try read(allocator, tmp.dir, "repo/src/root.zig");
    defer allocator.free(root);
    try testing.expect(std.mem.indexOf(u8, root, "pub const api_base_url = \"https://pets.example.com/v1\";") != null);

    const readme = try read(allocator, tmp.dir, "repo/README.md");
    defer allocator.free(readme);
    try testing.expect(std.mem.indexOf(u8, readme, "# Pets SDK for Zig") != null);
    try testing.expect(std.mem.indexOf(u8, readme, "1 paths (2 operations)") != null);
    try testing.expect(std.mem.indexOf(u8, readme, "1 schemas") != null);

    const zon = try read(allocator, tmp.dir, "repo/build.zig.zon");
    defer allocator.free(zon);
    try testing.expect(std.mem.indexOf(u8, zon, ".name = .pets,") != null);
    try testing.expect(std.mem.indexOf(u8, zon, ".version = \"0.3.0\",") != null);
}

test "sdk regeneration keeps edited scaffold files and rewrites generated ones" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "repo");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/openapi2zig.json", .data = config_json });
    try runGenerate(allocator, tmp.dir, false);

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/README.md", .data = "my readme\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/build.zig", .data = "// hacked\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/examples/list_pets.zig", .data = "// example\n" });

    try runGenerate(allocator, tmp.dir, false);

    const readme = try read(allocator, tmp.dir, "repo/README.md");
    defer allocator.free(readme);
    try testing.expectEqualStrings("my readme\n", readme);

    const build_zig = try read(allocator, tmp.dir, "repo/build.zig");
    defer allocator.free(build_zig);
    try testing.expect(std.mem.indexOf(u8, build_zig, "hacked") == null);
    try testing.expect(std.mem.indexOf(u8, build_zig, "\"list_pets\"") != null);
    try testing.expect(std.mem.indexOf(u8, build_zig, "\"quickstart\"") != null);
}

test "sdk generation skips the license for non-MIT configs" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "repo");
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "repo/openapi2zig.json",
        .data = "{ \"name\": \"pets\", \"license\": \"Apache-2.0\" }",
    });
    try runGenerate(allocator, tmp.dir, false);

    try testing.expect(!exists(tmp.dir, "repo/LICENSE"));
    try testing.expect(exists(tmp.dir, "repo/build.zig"));
}

test "sdk prepare writes a default config when none exists" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var prepared = try sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{
        .input_path = "",
        .output_path = "repo",
        .sdk = true,
        .sdk_name = "pets",
    });
    defer prepared.deinit();

    const expected_config = try std.fs.path.join(allocator, &.{ "repo", "openapi2zig.json" });
    defer allocator.free(expected_config);
    try testing.expectEqualStrings(expected_config, prepared.config_path);
    try testing.expectEqualStrings("pets", prepared.parsed.value.name);
    try testing.expect(std.mem.endsWith(u8, prepared.args.input_path, "openapi.json"));
    try testing.expect(exists(tmp.dir, "repo/openapi2zig.json"));
}

test "sdk prepare needs a name when there is no config" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try testing.expectError(error.MissingSdkName, sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{
        .input_path = "spec.json",
        .sdk = true,
    }));
}

test "sdk prepare reads the spec path from an existing config" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "repo");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/openapi2zig.json", .data = config_json });

    var prepared = try sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{ .input_path = "", .output_path = "repo", .sdk = true });
    defer prepared.deinit();

    const expected = try std.fs.path.join(allocator, &.{ "repo", "openapi/openapi.json" });
    defer allocator.free(expected);
    try testing.expectEqualStrings(expected, prepared.args.input_path);
    try testing.expect(prepared.args.multiple_files);
}

test "sdk prepare copies a local spec into the repository" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(testing.io, .{ .sub_path = "pets.json", .data = spec });

    var prepared = try sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{
        .input_path = "pets.json",
        .output_path = "repo",
        .sdk = true,
        .sdk_name = "pets",
    });
    defer prepared.deinit();

    try testing.expectEqualStrings("openapi/pets.json", prepared.parsed.value.spec.?);
    try testing.expectEqualStrings("pets.json", prepared.args.input_path);

    const copied = try read(allocator, tmp.dir, "repo/openapi/pets.json");
    defer allocator.free(copied);
    try testing.expectEqualStrings(spec, copied);
}

test "sdk prepare keeps a remote spec url in the config" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var prepared = try sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{
        .input_path = "https://example.com/openapi.json",
        .output_path = "repo",
        .sdk = true,
        .sdk_name = "pets",
    });
    defer prepared.deinit();

    try testing.expectEqualStrings("https://example.com/openapi.json", prepared.parsed.value.spec.?);
}

test "sdk prepare writes nothing for an invalid name" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "pets.json", .data = spec });

    try testing.expectError(error.InvalidConfig, sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{
        .input_path = "pets.json",
        .output_path = "repo",
        .sdk = true,
        .sdk_name = "Pet-Store",
    }));
    try testing.expect(!exists(tmp.dir, "repo/openapi2zig.json"));
    try testing.expect(!exists(tmp.dir, "repo/openapi/pets.json"));
}

test "sdk prepare writes no config when the local spec is missing" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try testing.expectError(error.FileNotFound, sdk_scaffold.prepare(allocator, testing.io, tmp.dir, .{
        .input_path = "missing.json",
        .output_path = "repo",
        .sdk = true,
        .sdk_name = "pets",
    }));
    try testing.expect(!exists(tmp.dir, "repo/openapi2zig.json"));
}

test "sdk generation skips examples whose names cannot be a build step" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(testing.io, "repo/examples");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/openapi2zig.json", .data = config_json });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/examples/a b.zig", .data = "// bad\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "repo/examples/good_one.zig", .data = "// ok\n" });
    try runGenerate(allocator, tmp.dir, false);

    const build_zig = try read(allocator, tmp.dir, "repo/build.zig");
    defer allocator.free(build_zig);
    try testing.expect(std.mem.indexOf(u8, build_zig, "\"good_one\"") != null);
    try testing.expect(std.mem.indexOf(u8, build_zig, "a b") == null);
}
