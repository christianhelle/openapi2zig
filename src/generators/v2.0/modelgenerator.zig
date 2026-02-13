const std = @import("std");
const models = @import("../../models.zig");
const cli = @import("../../cli.zig");
const detector = @import("../../detector.zig");
const converter = @import("../converter.zig");
const default_output_file: []const u8 = "generated.zig";

pub const ModelCodeGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModelCodeGenerator {
        return ModelCodeGenerator{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModelCodeGenerator) void {
        _ = self;
    }

    pub fn generate(self: *ModelCodeGenerator, document: models.SwaggerDocument) ![]const u8 {
        var parts = std.ArrayList([]const u8){};
        defer parts.deinit(self.allocator);
        try parts.append(self.allocator, "///////////////////////////////////////////\n");
        try parts.append(self.allocator, "// Generated Zig structures from Swagger v2.0\n");
        try parts.append(self.allocator, "///////////////////////////////////////////\n\n");
        if (document.definitions) |definitions| {
            try generateSchemas(self.allocator, &parts, definitions);
        }
        const code = try std.mem.join(self.allocator, "", parts.items);
        return code;
    }

    fn generateSchemas(allocator: std.mem.Allocator, parts: *std.ArrayList([]const u8), schemas: std.StringHashMap(models.v2.Schema)) !void {
        var iterator = schemas.iterator();
        while (iterator.next()) |entry| {
            const schema_name = entry.key_ptr.*;
            const schema = entry.value_ptr.*;
            try generateSchema(allocator, parts, schema_name, schema);
        }
    }

    fn generateSchema(allocator: std.mem.Allocator, parts: *std.ArrayList([]const u8), name: []const u8, schema: models.v2.Schema) !void {
        try parts.append(allocator, "pub const ");
        try parts.append(allocator, name);
        try parts.append(allocator, " = struct {\n");
        if (schema.properties) |properties| {
            var property_iterator = properties.iterator();
            while (property_iterator.next()) |property| {
                const field_name = property.key_ptr.*;
                const field_schema = property.value_ptr.*;
                try generateField(allocator, parts, field_name, field_schema, schema.required);
            }
        }
        try parts.append(allocator, "};\n\n");
    }

    fn generateField(allocator: std.mem.Allocator, parts: *std.ArrayList([]const u8), field_name: []const u8, field_schema: models.v2.Schema, required_fields: ?[]const []const u8) !void {
        const is_required = if (required_fields) |req_fields| blk: {
            for (req_fields) |req_field| {
                if (std.mem.eql(u8, req_field, field_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        } else false;
        var data_type: []const u8 = "[]const u8"; // Default to string
        if (field_schema.type) |schema_type| {
            data_type = converter.getDataType(schema_type);
        } else if (field_schema.ref) |_| {
            data_type = "[]const u8";
        }
        try parts.append(allocator, "    ");
        try parts.append(allocator, field_name);
        try parts.append(allocator, ": ");
        if (is_required) {
            try parts.append(allocator, data_type);
            try parts.append(allocator, ",\n");
        } else {
            try parts.append(allocator, "?");
            try parts.append(allocator, data_type);
            try parts.append(allocator, " = null,\n");
        }
    }
};
