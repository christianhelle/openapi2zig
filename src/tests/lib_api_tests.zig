const std = @import("std");
const openapi2zig = @import("../lib.zig");
const test_utils = @import("test_utils.zig");

// Exercises the public library surface: the per-version parse helpers, the YAML
// entry points and the standalone converters that callers use instead of the
// CLI.

fn readSpec(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .unlimited);
}

fn expectParsesToUnified(allocator: std.mem.Allocator, path: []const u8, expected_title: []const u8) !void {
    const contents = try readSpec(allocator, path);
    defer allocator.free(contents);
    var document = try openapi2zig.parseToUnified(allocator, contents);
    defer document.deinit(allocator);
    try std.testing.expectEqualStrings(expected_title, document.info.title);
}

test "parseToUnified handles every supported specification version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    try expectParsesToUnified(allocator, "openapi/v2.0/petstore.json", "Swagger Petstore");
    try expectParsesToUnified(allocator, "openapi/v3.0/petstore.json", "Swagger Petstore");
    try expectParsesToUnified(allocator, "openapi/v3.1/kitchen-sink.json", "Kitchen Sink");
    try expectParsesToUnified(allocator, "openapi/v3.2/kitchen-sink.json", "Kitchen Sink");
}

test "parseToUnified rejects an unrecognised specification version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const spec =
        \\{"openapi": "4.0.0", "info": {"title": "Future", "version": "1.0.0"}, "paths": {}}
    ;
    try std.testing.expectError(error.UnsupportedApiVersion, openapi2zig.parseToUnified(allocator, spec));
}

test "detectVersion recognises each specification version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v2_0,
        try openapi2zig.detectVersion(allocator, "{\"swagger\": \"2.0\"}"),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v3_0,
        try openapi2zig.detectVersion(allocator, "{\"openapi\": \"3.0.3\"}"),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v3_1,
        try openapi2zig.detectVersion(allocator, "{\"openapi\": \"3.1.0\"}"),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v3_2,
        try openapi2zig.detectVersion(allocator, "{\"openapi\": \"3.2.0\"}"),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.Unsupported,
        try openapi2zig.detectVersion(allocator, "{\"openapi\": \"4.0.0\"}"),
    );
}

const yaml_paths =
    \\paths:
    \\  /ping:
    \\    get:
    \\      responses:
    \\        "200":
    \\          description: pong
;

const yaml_v30 =
    \\openapi: 3.0.3
    \\info:
    \\  title: Yaml Petstore
    \\  version: 1.0.0
    \\
++ yaml_paths;

const yaml_v31 =
    \\openapi: 3.1.0
    \\info:
    \\  title: Yaml Petstore
    \\  version: 1.0.0
    \\
++ yaml_paths;

const yaml_v32 =
    \\openapi: 3.2.0
    \\info:
    \\  title: Yaml Petstore
    \\  version: 1.0.0
    \\
++ yaml_paths;

const yaml_v20 =
    \\swagger: "2.0"
    \\info:
    \\  title: Yaml Petstore
    \\  version: 1.0.0
    \\
++ yaml_paths;

test "detectVersionFromYaml recognises each specification version" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v3_0,
        try openapi2zig.detectVersionFromYaml(allocator, yaml_v30),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v3_1,
        try openapi2zig.detectVersionFromYaml(allocator, yaml_v31),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v3_2,
        try openapi2zig.detectVersionFromYaml(allocator, yaml_v32),
    );
    try std.testing.expectEqual(
        openapi2zig.ApiVersion.v2_0,
        try openapi2zig.detectVersionFromYaml(allocator, yaml_v20),
    );
}

test "each YAML parse helper returns its version specific document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var v30 = try openapi2zig.parseOpenApiYaml(allocator, yaml_v30);
    defer v30.deinit(allocator);
    try std.testing.expectEqualStrings("3.0.3", v30.openapi);

    var v31 = try openapi2zig.parseOpenApi31Yaml(allocator, yaml_v31);
    defer v31.deinit(allocator);
    try std.testing.expectEqualStrings("3.1.0", v31.openapi);

    var v32 = try openapi2zig.parseOpenApi32Yaml(allocator, yaml_v32);
    defer v32.deinit(allocator);
    try std.testing.expectEqualStrings("3.2.0", v32.openapi);

    var v20 = try openapi2zig.parseSwaggerYaml(allocator, yaml_v20);
    defer v20.deinit(allocator);
    try std.testing.expectEqualStrings("2.0", v20.swagger);
}

test "parseOpenApi and convertOpenApiToUnified round-trip a v3.0 document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try readSpec(allocator, "openapi/v3.0/petstore.json");
    defer allocator.free(contents);
    var parsed = try openapi2zig.parseOpenApi(allocator, contents);
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);

    var unified = try openapi2zig.convertOpenApiToUnified(allocator, parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("Swagger Petstore", unified.info.title);
}

test "parseSwagger and convertSwaggerToUnified round-trip a v2.0 document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try readSpec(allocator, "openapi/v2.0/petstore.json");
    defer allocator.free(contents);
    var parsed = try openapi2zig.parseSwagger(allocator, contents);
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);

    var unified = try openapi2zig.convertSwaggerToUnified(allocator, parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("Swagger Petstore", unified.info.title);
}

test "convertOpenApi31ToUnified converts a parsed v3.1 document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try readSpec(allocator, "openapi/v3.1/kitchen-sink.json");
    defer allocator.free(contents);
    var parsed = try openapi2zig.OpenApi31Document.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);

    var unified = try openapi2zig.convertOpenApi31ToUnified(allocator, parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("Kitchen Sink", unified.info.title);
}

test "convertOpenApi32ToUnified converts a parsed v3.2 document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try readSpec(allocator, "openapi/v3.2/kitchen-sink.json");
    defer allocator.free(contents);
    var parsed = try openapi2zig.OpenApi32Document.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);

    var unified = try openapi2zig.convertOpenApi32ToUnified(allocator, parsed);
    defer unified.deinit(allocator);
    try std.testing.expectEqualStrings("Kitchen Sink", unified.info.title);
}

test "generateCode emits models and the API client in one file" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try readSpec(allocator, "openapi/v3.0/petstore.json");
    defer allocator.free(contents);
    var document = try openapi2zig.parseToUnified(allocator, contents);
    defer document.deinit(allocator);

    const code = try openapi2zig.generateCode(allocator, std.testing.io, document, .{
        .input_path = "openapi/v3.0/petstore.json",
    });
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "This code was generated by openapi2zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const Pet = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const Client = struct") != null);
}

test "generateApi emits an API client for a unified document" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try readSpec(allocator, "openapi/v3.0/petstore.json");
    defer allocator.free(contents);
    var document = try openapi2zig.parseToUnified(allocator, contents);
    defer document.deinit(allocator);

    const code = try openapi2zig.generateApi(allocator, document, .{
        .input_path = "openapi/v3.0/petstore.json",
    });
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const Client = struct") != null);
}
