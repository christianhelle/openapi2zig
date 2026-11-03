const std = @import("std");
const api = @import("../lib.zig");
const Info = @import("../models/v3.1/info.zig").Info;
const common = @import("../models/common/document.zig");
const detection = @import("../models/common/streaming.zig");

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

test "generated streaming requests do not follow redirects" {
    const allocator = std.testing.allocator;
    const source = try readFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    var generator = api.UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);
    for ([_][]const u8{"client.http.request(.POST, uri, .{"}) |call| {
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
    try detection.detectRequestStreaming(allocator, paths, schemas);
    try std.testing.expect(paths.get("/fixture").?.post.?.streaming);
    try std.testing.expect(!paths.get("/fixture").?.get.?.streaming);
    paths.getPtr("/fixture").?.post.?.streaming = false;
    try properties.put("stream", .{ .type = .string });
    try schemas.put("Body", .{ .type = .object, .properties = properties });
    try detection.detectRequestStreaming(allocator, paths, schemas);
    try std.testing.expect(!paths.get("/fixture").?.post.?.streaming);
    parameters[0].schema = .{ .ref = "#/components/schemas/Cycle" };
    try detection.detectRequestStreaming(allocator, paths, schemas);
    try std.testing.expect(!paths.get("/fixture").?.post.?.streaming);
}

fn detectForSchema(allocator: std.mem.Allocator, schema: common.Schema, schemas: ?std.StringHashMap(common.Schema)) !bool {
    var parameters = [_]common.Parameter{.{ .name = "body", .location = .body, .schema = schema }};
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    defer paths.deinit();
    try paths.put("/fixture", .{ .post = .{
        .parameters = &parameters,
        .responses = std.StringHashMap(common.Response).init(allocator),
    } });
    try detection.detectRequestStreaming(allocator, paths, schemas);
    return paths.get("/fixture").?.post.?.streaming;
}

// Property: for each root, detection is true exactly when a boolean permitting
// true (or a body containing such a stream field) is reachable through refs and
// either composition keyword. The oracle computes the least fixed point,
// independently of the production worklist and its visitation order.
test "stream traversal agrees with fixed point for all three-node directed graphs" {
    const allocator = std.testing.allocator;
    const names = [_][]const u8{ "A", "B", "C" };
    const refs = [_][]const u8{ "#/components/schemas/A", "#/components/schemas/B", "#/components/schemas/C" };
    var terminal_properties = std.StringHashMap(common.Schema).init(allocator);
    defer terminal_properties.deinit();
    try terminal_properties.put("stream", .{ .type = .boolean });
    var root_properties = std.StringHashMap(common.Schema).init(allocator);
    defer root_properties.deinit();
    try root_properties.put("stream", .{});
    var schemas = std.StringHashMap(common.Schema).init(allocator);
    defer schemas.deinit();
    for (names) |name| try schemas.put(name, .{});

    for (0..512) |edges| {
        var variants: [3][3]common.Schema = undefined;
        for (0..8) |terminals| {
            var expected: [3]bool = undefined;
            for (0..3) |i| expected[i] = terminals & (@as(usize, 1) << @intCast(i)) != 0;
            var changed = true;
            while (changed) {
                changed = false;
                for (0..3) |i| {
                    for (0..3) |j| {
                        if (edges & (@as(usize, 1) << @intCast(i * 3 + j)) != 0 and expected[j] and !expected[i]) {
                            expected[i] = true;
                            changed = true;
                        }
                    }
                }
            }
            for ([_]bool{ false, true }) |boolean_query| {
                for (names, 0..) |name, i| {
                    var count: usize = 0;
                    for (refs, 0..) |ref, j| {
                        if (edges & (@as(usize, 1) << @intCast(i * 3 + j)) == 0) continue;
                        variants[i][count] = .{ .ref = ref };
                        count += 1;
                    }
                    const terminal = terminals & (@as(usize, 1) << @intCast(i)) != 0;
                    schemas.getPtr(name).?.* = .{
                        .type = if (terminal and boolean_query) .boolean else null,
                        .properties = if (terminal and !boolean_query) terminal_properties else null,
                        .one_of = variants[i][0 .. count / 2],
                        .any_of = variants[i][count / 2 .. count],
                    };
                }
                for (refs, 0..) |ref, root| {
                    root_properties.getPtr("stream").?.* = .{ .ref = ref };
                    const schema: common.Schema = if (boolean_query) .{ .properties = root_properties } else .{ .ref = ref };
                    try std.testing.expectEqual(expected[root], try detectForSchema(allocator, schema, schemas));
                }
            }
        }
    }
}

fn exerciseStreamingWorklist(allocator: std.mem.Allocator) !void {
    var properties = std.StringHashMap(common.Schema).init(allocator);
    defer properties.deinit();
    var schemas = std.StringHashMap(common.Schema).init(allocator);
    defer schemas.deinit();
    const count = 192;
    var names: [count][]const u8 = undefined;
    var refs: [count][]const u8 = undefined;
    var allocated: usize = 0;
    defer for (0..allocated) |i| {
        allocator.free(names[i]);
        allocator.free(refs[i]);
    };
    for (0..count) |i| {
        names[i] = try allocator.print("N{d}", .{i});
        refs[i] = allocator.print("#/components/schemas/N{d}", .{i}) catch |err| {
            allocator.free(names[i]);
            return err;
        };
        allocated += 1;
    }
    // Two references to each successor make a shared DAG with exponentially
    // many paths, but only a linear number of vertices and edges.
    var variants: [count][2]common.Schema = undefined;
    for (0..count) |i| {
        variants[i] = .{ .{ .ref = refs[@min(i + 1, count - 1)] }, .{ .ref = refs[@min(i + 1, count - 1)] } };
        try schemas.put(names[i], .{ .one_of = &variants[i] });
    }
    try properties.put("stream", .{ .type = .boolean });
    schemas.getPtr(names[count - 1]).?.* = .{ .properties = properties };
    try std.testing.expect(try detectForSchema(allocator, .{ .ref = refs[0] }, schemas));
    // Exercise the boolean query on the same deep, shared graph as well.
    schemas.getPtr(names[count - 1]).?.* = .{ .type = .boolean };
    properties.getPtr("stream").?.* = .{ .ref = refs[0] };
    try std.testing.expect(try detectForSchema(allocator, .{ .properties = properties }, schemas));
    schemas.getPtr(names[count - 1]).?.* = .{};
    try std.testing.expect(!try detectForSchema(allocator, .{ .properties = properties }, schemas));
    try std.testing.expect(!try detectForSchema(allocator, .{ .ref = refs[0] }, schemas));
}

test "stream traversal handles deep shared DAGs for body and boolean queries" {
    try exerciseStreamingWorklist(std.testing.allocator);
}

test "stream traversal propagates allocation failures without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseStreamingWorklist, .{});
}

test "stream booleans must permit true including enums on references and unions" {
    const allocator = std.testing.allocator;
    var properties = std.StringHashMap(common.Schema).init(allocator);
    defer properties.deinit();
    var schemas = std.StringHashMap(common.Schema).init(allocator);
    defer schemas.deinit();
    const only_false = [_]std.json.Value{.{ .bool = false }};
    const only_true = [_]std.json.Value{.{ .bool = true }};
    try properties.put("stream", .{ .type = .boolean, .enum_values = &only_false });
    try std.testing.expect(!try detectForSchema(allocator, .{ .properties = properties }, null));
    properties.getPtr("stream").?.enum_values = &only_true;
    try std.testing.expect(try detectForSchema(allocator, .{ .properties = properties }, null));
    try schemas.put("Bool", .{ .type = .boolean, .enum_values = &only_false });
    properties.getPtr("stream").?.* = .{ .ref = "#/components/schemas/Bool" };
    try std.testing.expect(!try detectForSchema(allocator, .{ .properties = properties }, schemas));
    schemas.getPtr("Bool").?.enum_values = &only_true;
    try std.testing.expect(try detectForSchema(allocator, .{ .properties = properties }, schemas));
    var variants = [_]common.Schema{.{ .type = .boolean }};
    properties.getPtr("stream").?.* = .{ .one_of = &variants, .enum_values = &only_false };
    try std.testing.expect(!try detectForSchema(allocator, .{ .properties = properties }, schemas));
    // A ref to another component namespace must not accidentally resolve a
    // schema with the same basename.
    properties.getPtr("stream").?.* = .{ .ref = "#/components/requestBodies/Bool" };
    try std.testing.expect(!try detectForSchema(allocator, .{ .properties = properties }, schemas));
}

fn readStreamingFixture() ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, "openapi/v3.1/regression-streaming-composition.json", std.testing.allocator, .limited(1024 * 1024));
}

test "OpenAPI 3.1 resolves reusable bodies before paths including inline allOf schema aliases" {
    const allocator = std.testing.allocator;
    const source = try readStreamingFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    for ([_][]const u8{ "/referenced", "/inline-allof", "/mixed-one", "/mixed-any", "/boolean-allof", "/true", "/sse" }) |path| {
        try std.testing.expect(document.paths.get(path).?.post.?.streaming);
    }
    for ([_][]const u8{ "/false", "/false-allof", "/cyclic-body", "/external-body" }) |path| {
        try std.testing.expect(!document.paths.get(path).?.post.?.streaming);
    }
    const referenced = document.paths.get("/referenced").?.post.?.parameters.?[0];
    try std.testing.expectEqualStrings("#/components/requestBodies/Alias", referenced.name);
    try std.testing.expect(referenced.required);
    try std.testing.expectEqualStrings("application/vnd.fixture+json", referenced.content_type.?);
    try std.testing.expectEqualStrings("Reusable request", referenced.description.?);
    try std.testing.expect(referenced.schema.?.properties.?.contains("stream"));
    try std.testing.expect(referenced.schema.?.properties.?.contains("prompt"));
    const inline_body = document.paths.get("/inline-allof").?.post.?.parameters.?[0];
    try std.testing.expectEqualStrings("stream", inline_body.schema.?.required.?[0]);
    // Each use owns its converted containers, not a borrowed view of another
    // parameter's schema. Mutating one must not change another use.
    var owned = document.paths.getPtr("/referenced").?.post.?.parameters.?[0].schema.?.properties.?;
    owned.getPtr("stream").?.type = .string;
    try std.testing.expectEqual(common.SchemaType.boolean, inline_body.schema.?.properties.?.get("stream").?.type.?);
}

test "mixed properties and compositions retain both constraints and generate lossless round trips" {
    const allocator = std.testing.allocator;
    const source = try readStreamingFixture();
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    const one = document.schemas.?.get("MixedOne").?;
    const any = document.schemas.?.get("MixedAny").?;
    const both = document.schemas.?.get("MixedBoth").?;
    try std.testing.expect(one.properties.?.contains("base"));
    try std.testing.expect(one.one_of.?[0].properties.?.contains("variant"));
    try std.testing.expect(any.properties.?.contains("base"));
    try std.testing.expect(any.any_of.?[0].properties.?.contains("variant"));
    try std.testing.expect(both.one_of != null and both.any_of != null);
    var generator = api.UnifiedModelGenerator.init(allocator);
    defer generator.deinit();
    const code = try generator.generate(document);
    defer allocator.free(code);
    for ([_][]const u8{ "MixedOne", "MixedAny", "MixedBoth", "VariantWrapperVariant0" }) |name| {
        const declaration = try allocator.print("pub const {s} = std.json.Value;", .{name});
        defer allocator.free(declaration);
        try std.testing.expect(std.mem.indexOf(u8, code, declaration) != null);
    }
    for ([_][]const u8{ "one: std.json.Value", "any: std.json.Value", "list: []const std.json.Value" }) |field| {
        try std.testing.expect(std.mem.indexOf(u8, code, field) != null);
    }
    // The exact generated alias above selects this representation. Verify its
    // wire behavior, including fields from the base and both compositions.
    const Lossless = std.json.Value;
    for ([_][]const u8{
        "{\"base\":\"kept\",\"variant\":7,\"stream\":true}",
        "{\"one\":\"kept\",\"any\":7,\"extra\":{\"nested\":[false,null]}}",
    }) |payload| {
        const parsed = try std.json.parseFromSlice(Lossless, allocator, payload, .{});
        defer parsed.deinit();
        const encoded = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings(payload, encoded);
    }
}
