const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const fixture_path = "openapi/v3.0/regression-odata-shapes.json";

const Generated = struct {
    models: []const u8,
    client: []const u8,

    fn deinit(self: Generated, allocator: std.mem.Allocator) void {
        allocator.free(self.models);
        allocator.free(self.client);
    }
};

fn generateFixture(allocator: std.mem.Allocator) !Generated {
    const contents = try std.Io.Dir.cwd().readFileAlloc(testing.io, fixture_path, allocator, .unlimited);
    defer allocator.free(contents);
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const model_code = try model_generator.generate(unified);
    errdefer allocator.free(model_code);

    var api_generator = UnifiedApiGenerator.init(allocator, .{ .input_path = fixture_path, .resource_wrappers = .none });
    defer api_generator.deinit();
    const client_code = try api_generator.generate(unified);
    return .{ .models = model_code, .client = client_code };
}

test "required properties with a string default can be omitted from responses" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const generated = try generateFixture(allocator);
    defer generated.deinit(allocator);

    // `@odata.type` is required in every OData schema but servers usually omit
    // it, so the declared default has to apply when the key is missing.
    try testing.expect(std.mem.indexOf(u8, generated.models, "@\"@odata.type\": []const u8 = \"#microsoft.graph.user\",") != null);
}

fn generateNamespaced(allocator: std.mem.Allocator) !Generated {
    const contents = try std.Io.Dir.cwd().readFileAlloc(testing.io, fixture_path, allocator, .unlimited);
    defer allocator.free(contents);
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var model_generator = UnifiedModelGenerator.init(allocator);
    model_generator.model_naming = .namespaced;
    defer model_generator.deinit();
    const model_code = try model_generator.generate(unified);
    errdefer allocator.free(model_code);

    var api_generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = fixture_path,
        .resource_wrappers = .none,
        .model_naming = .namespaced,
    });
    defer api_generator.deinit();
    const client_code = try api_generator.generate(unified);
    return .{ .models = model_code, .client = client_code };
}

test "namespaced model naming declares PascalCase types and nested aliases" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const generated = try generateNamespaced(allocator);
    defer generated.deinit(allocator);

    try testing.expect(std.mem.indexOf(u8, generated.models, "pub const User = struct {") != null);
    try testing.expect(std.mem.indexOf(u8, generated.models, "pub const Message = struct {") != null);
    try testing.expect(std.mem.indexOf(u8, generated.models, "pub const ODataErrorsODataError = struct {") != null);
    try testing.expect(std.mem.indexOf(u8, generated.models, "@\"microsoft.graph.user\"") == null);
    try testing.expect(std.mem.indexOf(u8, generated.models, "pub const o_data_errors = struct {") != null);
    try testing.expect(std.mem.indexOf(u8, generated.models, "pub const ODataError = root.ODataErrorsODataError;") != null);
    // References between models use the same names.
    try testing.expect(std.mem.indexOf(u8, generated.models, "messages: ?[]const Message = null,") != null);
}

test "namespaced model naming is used by client signatures" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const generated = try generateNamespaced(allocator);
    defer generated.deinit(allocator);

    try testing.expect(std.mem.indexOf(u8, generated.client, "requestBody: User) !Owned(User)") != null);
    try testing.expect(std.mem.indexOf(u8, generated.client, "@\"microsoft.graph.user\"") == null);
}
