const std = @import("std");
const openapi2zig = @import("../lib.zig");
const test_utils = @import("test_utils.zig");

// The model generator has to invent a Zig field name and type for every shape a
// oneOf/anyOf variant can take. These tests pin the naming rules down against a
// spec that carries one schema per shape.

const spec_path = "openapi/v3.1/union-variants.json";

fn generateModels(allocator: std.mem.Allocator) ![]const u8 {
    const file_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, spec_path, allocator, .unlimited);
    defer allocator.free(file_contents);
    var document = try openapi2zig.parseToUnified(allocator, file_contents);
    defer document.deinit(allocator);
    return try openapi2zig.generateModels(allocator, document);
}

fn expectContains(code: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, code, needle) != null);
}

test "a union of one type and null becomes an optional alias" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const NullableString = ?[]const u8;");
}

test "a union whose variants share one primitive type becomes a plain alias" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const IntegerAlias = i64;");
    try expectContains(code, "pub const NumberAlias = f64;");
    try expectContains(code, "pub const BooleanAlias = bool;");
}

test "a union of several primitive types becomes a tagged primitive union" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const MixedPrimitive = union(enum) {");
    try expectContains(code, "    string: []const u8,");
    try expectContains(code, "    integer: i64,");
    try expectContains(code, "    number: f64,");
    try expectContains(code, "    boolean: bool,");
    try expectContains(code, "            .string => |value| .{ .string = value },");
    try expectContains(code, "            .integer => |value| .{ .integer = value },");
    try expectContains(code, "            .float => |value| .{ .number = value },");
    try expectContains(code, "            .bool => |value| .{ .boolean = value },");
}

test "array variants are named after their item type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const ArrayVariants = union(enum) {");
    try expectContains(code, "    text_block: TextBlock,");
    try expectContains(code, "    text_block_items: []const TextBlock,");
    try expectContains(code, "    strings: ");
    try expectContains(code, "    integers: ");
    try expectContains(code, "    numbers: ");
    try expectContains(code, "    booleans: ");
    try expectContains(code, "    arrays: ");
    try expectContains(code, "    blobs: ");
    try expectContains(code, "    widget_items: ");
    try expectContains(code, "    items_9: ");
    try expectContains(code, "    raw: std.json.Value,");
}

test "scalar variants are named after their title or type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const ScalarVariants = union(enum) {");
    try expectContains(code, "    text: []const u8,");
    try expectContains(code, "    integer: i64,");
    try expectContains(code, "    number: f64,");
    try expectContains(code, "    boolean: bool,");
    try expectContains(code, "    object: ");
}

test "object variants are named after their title" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const TitledVariants = union(enum) {");
    try expectContains(code, "    alpha: TitledVariantsVariant0,");
    try expectContains(code, "    beta: TitledVariantsVariant1,");
    try expectContains(code, "pub const TitledVariantsVariant0 = struct {");
    try expectContains(code, "pub const TitledVariantsVariant1 = struct {");
}

test "object variants without a title fall back to a positional name" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const UntitledVariants = union(enum) {");
    try expectContains(code, "    variant_0: UntitledVariantsVariant0,");
    try expectContains(code, "    variant_1: UntitledVariantsVariant1,");
}

test "string enum variants become one field per enum value" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const EnumOrNumber = union(enum) {");
    try expectContains(code, "    red,");
    try expectContains(code, "    green,");
    try expectContains(code, "if (source == .string and std.mem.eql(u8, source.string, \"red\")) return .red;");
    try expectContains(code, "if (source == .string and std.mem.eql(u8, source.string, \"green\")) return .green;");
}

test "a discriminated union is keyed by the discriminator values" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const TaggedEvent = union(enum) {");
    try expectContains(code, "    started: StartedEvent,");
    try expectContains(code, "    stopped: StoppedEvent,");
}

test "structural unions round-trip through json parse and stringify helpers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {");
    try expectContains(code, "if (std.json.parseFromValueLeaky(");
    try expectContains(code, "        return .{ .raw = source };");
    try expectContains(code, "pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {");
}
