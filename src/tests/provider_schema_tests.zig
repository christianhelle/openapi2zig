const std = @import("std");
const api = @import("../lib.zig");
const Info = @import("../models/v3.1/info.zig").Info;

fn readFixture() ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, "openapi/v3.1/regression-provider-schemas.json", std.testing.allocator, .limited(1024 * 1024));
}

test "OpenAPI 3.1 tolerates missing version without fabricating one" {
    const allocator = std.testing.allocator;
    const source = try readFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    try std.testing.expectEqualStrings("unknown", document.info.version);
    try std.testing.expect(document.schemas.?.contains("BetaDreamUsage"));
    try std.testing.expect(document.paths.get("/v1/messages").?.post.?.streaming);
}

test "OpenAPI 3.1 rejects non-string info version with a clear error" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, "{\"title\":\"fixture\",\"version\":42}", .{});
    defer parsed.deinit();
    try std.testing.expectError(error.InvalidInfoVersion, Info.parseFromJson(allocator, parsed.value));
}

test "provider helper declarations are unique and repeatable with component refs unchanged" {
    const allocator = std.testing.allocator;
    const source = try readFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    var generator = api.UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const first = try generator.generate(document);
    defer allocator.free(first);
    const second = try generator.generate(document);
    defer allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.indexOf(u8, first, "traces: BetaTelemetryDestinationTraces_2") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "usage: BetaDreamUsage_2") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "component: OwnerFooBar") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "pub const OwnerFooBar = i64;") != null);
    const sentinel = try allocator.dupeSentinel(u8, first, 0);
    defer allocator.free(sentinel);
    var ast = try std.zig.Ast.parse(allocator, sentinel, .{ .mode = .zig });
    defer ast.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), ast.errors.len);
    var declarations = std.StringHashMap(void).init(allocator);
    defer declarations.deinit();
    for (ast.rootDecls()) |node| {
        const token = ast.nodeMainToken(node);
        if (ast.tokenTag(token) != .keyword_const) continue;
        const name = ast.tokenSlice(token + 1);
        try std.testing.expect(!declarations.contains(name));
        try declarations.put(name, {});
    }
}

test "OpenAPI 3.1 preserves explicit open objects through allOf and cloning" {
    const allocator = std.testing.allocator;
    const source = try readFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    for ([_][]const u8{ "InputSchema", "TypedOpen", "OpenBase", "OpenDerived" }) |name| {
        try std.testing.expectEqual(@as(?bool, true), document.schemas.?.get(name).?.additional_properties);
    }
    var generator = api.UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const InputSchema = std.json.Value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "schema: std.json.Value") != null);
}

fn exerciseHelperNames(allocator: std.mem.Allocator) !void {
    var generator = api.UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    try generator.declaration_names.put("OwnerField", {});
    const first = try generator.fieldTypeNameAlloc("Owner", "field");
    defer allocator.free(first);
    const repeated = try generator.fieldTypeNameAlloc("Owner", "field");
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings("OwnerField_2", first);
    try std.testing.expectEqualStrings(first, repeated);
    const different = try generator.fieldTypeNameAlloc("Owner", "Field");
    defer allocator.free(different);
    try std.testing.expectEqualStrings("OwnerField_3", different);
}

test "helper name registry cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseHelperNames, .{});
}

test "generated HTTP call sites explicitly disable redirects" {
    const allocator = std.testing.allocator;
    const source = try readFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    var generator = api.UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);
    for ([_][]const u8{ "client.http.fetch(.{", "client.http.request(.POST, uri, .{" }) |call| {
        var offset: usize = 0;
        var count: usize = 0;
        while (std.mem.indexOfPos(u8, code, offset, call)) |start| {
            const end = std.mem.indexOfPos(u8, code, start, "}) catch") orelse return error.MissingHttpOptions;
            try std.testing.expect(std.mem.indexOf(u8, code[start..end], ".redirect_behavior = .unhandled") != null);
            offset = end;
            count += 1;
        }
        try std.testing.expect(count > 0);
    }
}

test "stream switch detection resolves refs and ignores GET non-booleans and cycles" {
    const allocator = std.testing.allocator;
    const common = @import("../models/common/document.zig");
    const detection = @import("../models/common/streaming.zig");
    var properties = std.StringHashMap(common.Schema).init(allocator);
    defer properties.deinit();
    try properties.put("stream", .{ .type = .boolean });
    var schemas = std.StringHashMap(common.Schema).init(allocator);
    defer schemas.deinit();
    try schemas.put("Body", .{ .type = .object, .properties = properties });
    try schemas.put("Cycle", .{ .ref = "#/components/schemas/Cycle" });
    var parameters = [_]common.Parameter{.{ .name = "body", .location = .body, .schema = .{ .ref = "#/components/schemas/Body" } }};
    const operation: common.Operation = .{ .parameters = &parameters, .responses = std.StringHashMap(common.Response).init(allocator) };
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    defer paths.deinit();
    try paths.put("/fixture", .{ .get = operation, .post = operation });
    detection.detectRequestStreaming(paths, schemas);
    try std.testing.expect(paths.get("/fixture").?.post.?.streaming);
    try std.testing.expect(!paths.get("/fixture").?.get.?.streaming);
    paths.getPtr("/fixture").?.post.?.streaming = false;
    try properties.put("stream", .{ .type = .string });
    try schemas.put("Body", .{ .type = .object, .properties = properties });
    detection.detectRequestStreaming(paths, schemas);
    try std.testing.expect(!paths.get("/fixture").?.post.?.streaming);
    parameters[0].schema = .{ .ref = "#/components/schemas/Cycle" };
    detection.detectRequestStreaming(paths, schemas);
    try std.testing.expect(!paths.get("/fixture").?.post.?.streaming);
}
