const std = @import("std");
const openapi2zig = @import("../lib.zig");
const test_utils = @import("test_utils.zig");

// A handful of OpenAI schemas cannot be derived from their JSON Schema, so the
// model generator hand-writes their types. The full OpenAI specification is too
// large for a unit test, so this fixture just carries the names those overrides
// key off.

const spec_path = "openapi/v3.1/openai-overrides.json";

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

test "CompoundFilter is emitted from a hand-written definition" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const CompoundFilterItem = union(enum) {");
    try expectContains(code, "    comparison_filter: ComparisonFilter,");
    try expectContains(code, "    compound_filter: CompoundFilter,");
    try expectContains(code, "pub const CompoundFilter = struct {");
    try expectContains(code, "    filters: []const CompoundFilterItem,");
}

test "the OpenAI dynamic object aliases are emitted alongside them" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "pub const OpenApi2ZigDynamicObject = std.json.ArrayHashMap(std.json.Value);");
    try expectContains(code, "pub const MCPToolHeaders = std.json.ArrayHashMap([]const u8);");
}

test "hand-written field types replace the generated ones" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    const code = try generateModels(allocator);
    defer allocator.free(code);

    try expectContains(code, "    state_variables: ?ChatkitWorkflowStateVariables = null,");
    try expectContains(code, "    metadata: ?EvalResponsesSourceMetadata = null,");
    try expectContains(code, "    sample: ?EvalRunOutputItemResultSample = null,");
    try expectContains(code, "    created_by_user_obj: ?AssignedRoleDetailsCreatedByUserObj = null,");
    try expectContains(code, "    metadata: ?AssignedRoleDetailsMetadata = null,");
    try expectContains(code, "    annotations: ?MCPListToolsToolAnnotations = null,");
    try expectContains(code, "    headers: ?MCPToolHeaders = null,");
    try expectContains(code, "    parameters: ?FunctionParameters = null,");
    try expectContains(code, "    tool_choice: ?AssistantsApiToolChoiceOption = null,");
}
