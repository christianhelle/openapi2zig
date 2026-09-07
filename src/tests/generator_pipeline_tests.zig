const std = @import("std");
const generator = @import("../generator.zig");
const test_utils = @import("test_utils.zig");

// End-to-end coverage of the `generate` pipeline: extension detection, spec
// loading, version dispatch and file writing, for each supported specification
// version and for both single- and multiple-file output.

const Workspace = struct {
    tmp: std.testing.TmpDir,
    path: []const u8,

    fn init(allocator: std.mem.Allocator) !Workspace {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        // The generator resolves paths against the process working directory,
        // so address the temporary directory the same way.
        const path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
        return .{ .tmp = tmp, .path = path };
    }

    fn deinit(self: *Workspace, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.tmp.cleanup();
    }

    fn write(self: *Workspace, name: []const u8, data: []const u8) !void {
        try self.tmp.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = data });
    }

    fn join(self: *Workspace, allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
        return std.fs.path.join(allocator, &.{ self.path, name });
    }

    fn read(self: *Workspace, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        return self.tmp.dir.readFileAlloc(std.testing.io, name, allocator, .unlimited);
    }
};

const swagger_v2 =
    \\{
    \\  "swagger": "2.0",
    \\  "info": { "title": "fixture", "version": "1.0.0" },
    \\  "paths": {
    \\    "/pets": {
    \\      "get": {
    \\        "operationId": "listPets",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  },
    \\  "definitions": {
    \\    "Pet": { "type": "object", "properties": { "name": { "type": "string" } } }
    \\  }
    \\}
;

const openapi_v31 =
    \\{
    \\  "openapi": "3.1.0",
    \\  "info": { "title": "fixture", "version": "1.0.0" },
    \\  "paths": {
    \\    "/pets": {
    \\      "get": {
    \\        "operationId": "listPets",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  },
    \\  "components": {
    \\    "schemas": {
    \\      "Pet": { "type": "object", "properties": { "name": { "type": "string" } } }
    \\    }
    \\  }
    \\}
;

const openapi_v32 =
    \\{
    \\  "openapi": "3.2.0",
    \\  "info": { "title": "fixture", "version": "1.0.0" },
    \\  "paths": {
    \\    "/pets": {
    \\      "get": {
    \\        "operationId": "listPets",
    \\        "responses": { "200": { "description": "ok" } }
    \\      }
    \\    }
    \\  },
    \\  "components": {
    \\    "schemas": {
    \\      "Pet": { "type": "object", "properties": { "name": { "type": "string" } } }
    \\    }
    \\  }
    \\}
;

const openapi_v30_yaml =
    \\openapi: 3.0.3
    \\info:
    \\  title: fixture
    \\  version: 1.0.0
    \\paths:
    \\  /pets:
    \\    get:
    \\      operationId: listPets
    \\      responses:
    \\        '200':
    \\          description: ok
    \\components:
    \\  schemas:
    \\    Pet:
    \\      type: object
    \\      properties:
    \\        name:
    \\          type: string
;

fn generateInto(allocator: std.mem.Allocator, workspace: *Workspace, spec_name: []const u8, spec: []const u8) ![]u8 {
    try workspace.write(spec_name, spec);

    const input_path = try workspace.join(allocator, spec_name);
    defer allocator.free(input_path);
    const output_path = try workspace.join(allocator, "generated.zig");
    defer allocator.free(output_path);

    try generator.generateCode(allocator, std.testing.io, .{
        .input_path = input_path,
        .output_path = output_path,
    });

    return workspace.read(allocator, "generated.zig");
}

test "validateExtension accepts json and yaml and rejects anything else" {
    try std.testing.expectEqual(try generator.validateExtension("api.json"), .JSON);
    try std.testing.expectEqual(try generator.validateExtension("API.JSON"), .JSON);
    try std.testing.expectEqual(try generator.validateExtension("api.yaml"), .YAML);
    try std.testing.expectEqual(try generator.validateExtension("api.yml"), .YAML);
    try std.testing.expectError(
        generator.GeneratorErrors.UnsupportedExtension,
        generator.validateExtension("api.txt"),
    );
}

test "generateCode handles a Swagger 2.0 spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var workspace = try Workspace.init(allocator);
    defer workspace.deinit(allocator);

    const generated = try generateInto(allocator, &workspace, "api.json", swagger_v2);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn listPets") != null);
}

test "generateCode handles an OpenAPI 3.1 spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var workspace = try Workspace.init(allocator);
    defer workspace.deinit(allocator);

    const generated = try generateInto(allocator, &workspace, "api.json", openapi_v31);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn listPets") != null);
}

test "generateCode handles an OpenAPI 3.2 spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var workspace = try Workspace.init(allocator);
    defer workspace.deinit(allocator);

    const generated = try generateInto(allocator, &workspace, "api.json", openapi_v32);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn listPets") != null);
}

test "generateCode converts a YAML spec before generating" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var workspace = try Workspace.init(allocator);
    defer workspace.deinit(allocator);

    const generated = try generateInto(allocator, &workspace, "api.yaml", openapi_v30_yaml);
    defer allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "pub fn listPets") != null);
}

test "generateCode rejects an unsupported specification version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{"openapi": "4.0.0", "info": {"title": "Future", "version": "1.0.0"}, "paths": {}}
    ;
    try std.testing.expectError(
        generator.GeneratorErrors.UnsupportedOpenAPIVersion,
        generator.generateCodeFromJsonContents(allocator, std.testing.io, spec, .{ .input_path = "api.json" }),
    );
}

test "generateCode writes separate files in multiple-files mode" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var workspace = try Workspace.init(allocator);
    defer workspace.deinit(allocator);

    try workspace.write("api.json", openapi_v31);
    const input_path = try workspace.join(allocator, "api.json");
    defer allocator.free(input_path);
    const output_path = try workspace.join(allocator, "out");
    defer allocator.free(output_path);

    try generator.generateCode(allocator, std.testing.io, .{
        .input_path = input_path,
        .output_path = output_path,
        .multiple_files = true,
    });

    const models_code = try workspace.read(allocator, "out/models.zig");
    defer allocator.free(models_code);
    const client_code = try workspace.read(allocator, "out/client.zig");
    defer allocator.free(client_code);
    const runtime_code = try workspace.read(allocator, "out/runtime.zig");
    defer allocator.free(runtime_code);

    try std.testing.expect(std.mem.indexOf(u8, models_code, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, client_code, "pub fn listPets") != null);
    try std.testing.expect(runtime_code.len > 0);
}

test "validateExtension handles paths longer than max_path_bytes" {
    // The input path comes straight from the command line. Copying it into a
    // fixed [max_path_bytes]u8 stack buffer to lowercase it overflows that
    // buffer for a longer path, and release builds are ReleaseSmall, where
    // the bounds assert is compiled out. Only the extension matters here.
    const allocator = std.testing.allocator;
    const len = std.fs.max_path_bytes + 1;

    const json_path = try allocator.alloc(u8, len + ".json".len);
    defer allocator.free(json_path);
    @memset(json_path[0..len], 'a');
    @memcpy(json_path[len..], ".json");
    try std.testing.expectEqual(try generator.validateExtension(json_path), .JSON);

    const yaml_path = try allocator.alloc(u8, len + ".YAML".len);
    defer allocator.free(yaml_path);
    @memset(yaml_path[0..len], 'a');
    @memcpy(yaml_path[len..], ".YAML");
    try std.testing.expectEqual(try generator.validateExtension(yaml_path), .YAML);

    const bad_path = try allocator.alloc(u8, len + ".txt".len);
    defer allocator.free(bad_path);
    @memset(bad_path[0..len], 'a');
    @memcpy(bad_path[len..], ".txt");
    try std.testing.expectError(
        generator.GeneratorErrors.UnsupportedExtension,
        generator.validateExtension(bad_path),
    );
}
