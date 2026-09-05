const std = @import("std");
const openapi2zig = @import("../lib.zig");
const test_utils = @import("test_utils.zig");

// One assertion per Zig type the model generator can emit for a top-level
// schema or a struct field.

const spec_path = "openapi/v3.1/schema-shapes.json";

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

test "top level scalar schemas become plain aliases" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const Name = []const u8;");
    try expectContains(code, "pub const Count = i64;");
    try expectContains(code, "pub const Ratio = f64;");
    try expectContains(code, "pub const Enabled = bool;");
    try expectContains(code, "pub const Nothing = void;");
    try expectContains(code, "pub const AnythingAtAll = std.json.Value;");
}

test "top level array schemas become slice aliases" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const PetList = []const Pet;");
    try expectContains(code, "pub const Names = []const []const u8;");
    try expectContains(code, "pub const Matrix = []const []const i64;");
    try expectContains(code, "pub const NumberGrid = []const []const f64;");
    try expectContains(code, "pub const FlagGrid = []const []const bool;");
    try expectContains(code, "pub const RefGrid = []const []const Pet;");
    try expectContains(code, "pub const LooseList = []const std.json.Value;");
}

test "an array of inline objects gets a named item type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const PetPageItem = struct {");
    try expectContains(code, "pub const PetPage = []const PetPageItem;");
}

test "an object without declared properties is backed by std.json.Value" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const OpenObject = union(enum) {");
    try expectContains(code, "    number_string: []const u8,");
    try expectContains(code, "    object: std.json.ObjectMap,");
    try expectContains(code, "            .number_string => |value| try jw.print(\"{s}\", .{value}),");
}

test "optional struct fields keep their nullability and element types" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const OptionalFields = struct {");
    try expectContains(code, "    maybe_text: ?[]const u8 = null,");
    try expectContains(code, "    maybe_ratio: ?f64 = null,");
    try expectContains(code, "    nothing: ?void = null,");
    try expectContains(code, "    untyped: ?std.json.Value = null,");
    try expectContains(code, "    deep: ?[]const []const []const u8 = null,");
    try expectContains(code, "    loose_items: ?[]const std.json.Value = null,");
}

test "extensible request schemas gain extra_body and a custom stringifier" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const CreateChatCompletionRequest = struct {");
    try expectContains(code, "    model: []const u8,");
    try expectContains(code, "    extra_body: ?std.json.Value = null,");
    // Required fields are written unconditionally, optional ones only when set.
    try expectContains(code, "        try jw.objectField(\"model\");");
    try expectContains(code, "        try jw.write(self.model);");
    try expectContains(code, "        if (self.temperature) |value| {");
    try expectContains(code, "            try jw.objectField(\"temperature\");");
    try expectContains(code, "            try jw.write(value);");
}

test "enum values with quotes and control characters are escaped" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "source.string, \"say \\\"hi\\\"\")) return .say_hi;");
    try expectContains(code, "source.string, \"back\\\\slash\")) return .back_slash;");
    try expectContains(code, "source.string, \"line\\nbreak\")) return .line_break;");
    try expectContains(code, "source.string, \"tab\\there\")) return .tab_here;");
}
