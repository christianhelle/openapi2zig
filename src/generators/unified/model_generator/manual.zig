const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const Schema = @import("../../../models/common/document.zig").Schema;
const ident = @import("../ident_utils.zig");
const model_generator = @import("../model_generator.zig");
const UnifiedModelGenerator = model_generator.UnifiedModelGenerator;
const isExtensibleRequest = model_generator.isExtensibleRequest;

pub fn generateManualSchema(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) !bool {
    _ = schema;
    if (std.mem.eql(u8, name, "CompoundFilter")) {
        try self.buffer.appendSlice(self.allocator,
            \\pub const CompoundFilterItem = union(enum) {
            \\    comparison_filter: ComparisonFilter,
            \\    compound_filter: CompoundFilter,
            \\    raw: std.json.Value,
            \\
            \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
            \\        return jsonParseFromValue(allocator, value, options);
            \\    }
            \\
            \\    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
            \\        if (source != .object) return .{ .raw = source };
            \\        const discriminator = source.object.get("type") orelse return .{ .raw = source };
            \\        if (discriminator != .string) return .{ .raw = source };
            \\        if (std.mem.eql(u8, discriminator.string, "and") or std.mem.eql(u8, discriminator.string, "or")) {
            \\            if (std.json.parseFromValueLeaky(CompoundFilter, allocator, source, options)) |value| return .{ .compound_filter = value } else |_| return .{ .raw = source };
            \\        }
            \\        if (std.mem.eql(u8, discriminator.string, "eq") or std.mem.eql(u8, discriminator.string, "ne") or std.mem.eql(u8, discriminator.string, "gt") or std.mem.eql(u8, discriminator.string, "gte") or std.mem.eql(u8, discriminator.string, "lt") or std.mem.eql(u8, discriminator.string, "lte") or std.mem.eql(u8, discriminator.string, "in") or std.mem.eql(u8, discriminator.string, "nin")) {
            \\            if (std.json.parseFromValueLeaky(ComparisonFilter, allocator, source, options)) |value| return .{ .comparison_filter = value } else |_| return .{ .raw = source };
            \\        }
            \\        return .{ .raw = source };
            \\    }
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        switch (self) {
            \\            .comparison_filter => |value| try jw.write(value),
            \\            .compound_filter => |value| try jw.write(value),
            \\            .raw => |value| try jw.write(value),
            \\        }
            \\    }
            \\};
            \\
            \\pub const CompoundFilter = struct {
            \\    type: []const u8,
            \\    filters: []const CompoundFilterItem,
            \\};
            \\
            \\
        );
        return true;
    }

    return false;
}

pub fn generateOpenAiDynamicFieldTypes(self: *UnifiedModelGenerator) !void {
    try self.buffer.appendSlice(self.allocator,
        \\pub const OpenApi2ZigDynamicObject = std.json.ArrayHashMap(std.json.Value);
        \\
        \\pub const EvalResponsesSourceMetadata = OpenApi2ZigDynamicObject;
        \\pub const EvalRunOutputItemResultSample = OpenApi2ZigDynamicObject;
        \\pub const AssignedRoleDetailsCreatedByUserObj = OpenApi2ZigDynamicObject;
        \\pub const AssignedRoleDetailsMetadata = OpenApi2ZigDynamicObject;
        \\pub const MCPListToolsToolAnnotations = OpenApi2ZigDynamicObject;
        \\
        \\pub const MCPToolHeaders = std.json.ArrayHashMap([]const u8);
        \\
        \\pub const ChatkitWorkflowStateVariable = union(enum) {
        \\    string: []const u8,
        \\    integer: i64,
        \\    boolean: bool,
        \\    number: f64,
        \\
        \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
        \\        return jsonParseFromValue(allocator, value, options);
        \\    }
        \\
        \\    pub fn jsonParseFromValue(_: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) !@This() {
        \\        return switch (source) {
        \\            .string => |value| .{ .string = value },
        \\            .integer => |value| .{ .integer = value },
        \\            .bool => |value| .{ .boolean = value },
        \\            .float => |value| .{ .number = value },
        \\            else => error.UnexpectedToken,
        \\        };
        \\    }
        \\
        \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        \\        switch (self) {
        \\            .string => |value| try jw.write(value),
        \\            .integer => |value| try jw.write(value),
        \\            .boolean => |value| try jw.write(value),
        \\            .number => |value| try jw.write(value),
        \\        }
        \\    }
        \\};
        \\
        \\pub const ChatkitWorkflowStateVariables = std.json.ArrayHashMap(ChatkitWorkflowStateVariable);
        \\
        \\
    );
}

pub fn generateManualAliases(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
    if (schemas.contains("ChatkitWorkflow") or schemas.contains("MCPTool") or schemas.contains("ChatCompletionResponseMessage")) {
        try self.generateOpenAiDynamicFieldTypes();
    }
}

pub fn appendManualFieldType(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8) !bool {
    if (std.mem.eql(u8, owner_name, "ChatkitWorkflow") and std.mem.eql(u8, field_name, "state_variables")) {
        try self.buffer.appendSlice(self.allocator, "?ChatkitWorkflowStateVariables");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "EvalResponsesSource") and std.mem.eql(u8, field_name, "metadata")) {
        try self.buffer.appendSlice(self.allocator, "?EvalResponsesSourceMetadata");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "EvalRunOutputItemResult") and std.mem.eql(u8, field_name, "sample")) {
        try self.buffer.appendSlice(self.allocator, "?EvalRunOutputItemResultSample");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "AssignedRoleDetails") and std.mem.eql(u8, field_name, "created_by_user_obj")) {
        try self.buffer.appendSlice(self.allocator, "?AssignedRoleDetailsCreatedByUserObj");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "AssignedRoleDetails") and std.mem.eql(u8, field_name, "metadata")) {
        try self.buffer.appendSlice(self.allocator, "?AssignedRoleDetailsMetadata");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "MCPListToolsTool") and std.mem.eql(u8, field_name, "annotations")) {
        try self.buffer.appendSlice(self.allocator, "?MCPListToolsToolAnnotations");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "MCPTool") and std.mem.eql(u8, field_name, "headers")) {
        try self.buffer.appendSlice(self.allocator, "?MCPToolHeaders");
        return true;
    }
    if (std.mem.eql(u8, owner_name, "FunctionTool") and std.mem.eql(u8, field_name, "parameters")) {
        try self.buffer.appendSlice(self.allocator, "?FunctionParameters");
        return true;
    }
    if ((std.mem.eql(u8, owner_name, "RunObject") or
        std.mem.eql(u8, owner_name, "CreateRunRequest") or
        std.mem.eql(u8, owner_name, "CreateThreadAndRunRequest")) and
        std.mem.eql(u8, field_name, "tool_choice"))
    {
        try self.buffer.appendSlice(self.allocator, "?AssistantsApiToolChoiceOption");
        return true;
    }
    return false;
}
