const std = @import("std");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;

pub const UnifiedModelGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) UnifiedModelGenerator {
        return UnifiedModelGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *UnifiedModelGenerator) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn generate(self: *UnifiedModelGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.generateHeader();

        if (document.schemas) |schemas| {
            try self.generateSchemas(schemas);
        }

        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn generateHeader(self: *UnifiedModelGenerator) !void {
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n");
        try self.buffer.appendSlice(self.allocator, "// Generated Zig structures from OpenAPI\n");
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n\n");
    }

    fn generateSchemas(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
        var schema_iterator = schemas.iterator();
        while (schema_iterator.next()) |entry| {
            const schema_name = entry.key_ptr.*;
            const schema = entry.value_ptr.*;
            try self.generateSchema(schema_name, schema);
        }
    }

    fn generateSchema(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) !void {
        if (schema.type == .reference) return;

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.buffer.appendSlice(self.allocator, name);
        try self.buffer.appendSlice(self.allocator, " = struct {\n");

        if (schema.properties) |properties| {
            try self.generateStructFields(properties, schema.required);
        }

        try self.buffer.appendSlice(self.allocator, "};\n\n");
    }

    fn generateStructFields(self: *UnifiedModelGenerator, properties: std.StringHashMap(Schema), required: ?[][]const u8) !void {
        var prop_iterator = properties.iterator();
        while (prop_iterator.next()) |entry| {
            const field_name = entry.key_ptr.*;
            const field_schema = entry.value_ptr.*;
            const is_required = self.isFieldRequired(field_name, required);
            try self.generateStructField(field_name, field_schema, is_required);
        }
    }

    fn generateStructField(self: *UnifiedModelGenerator, field_name: []const u8, field_schema: Schema, is_required: bool) !void {
        try self.buffer.appendSlice(self.allocator, "    ");
        try self.buffer.appendSlice(self.allocator, field_name);
        try self.buffer.appendSlice(self.allocator, ": ");

        if (!is_required) {
            try self.buffer.appendSlice(self.allocator, "?");
        }

        try self.buffer.appendSlice(self.allocator, try self.getZigType(field_schema));

        if (!is_required) {
            try self.buffer.appendSlice(self.allocator, " = null");
        }

        try self.buffer.appendSlice(self.allocator, ",\n");
    }

    fn getZigType(self: *UnifiedModelGenerator, schema: Schema) ![]const u8 {
        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                const schema_name = ref[last_slash + 1 ..];
                return schema_name;
            }
            return "[]const u8";
        }

        if (schema.type) |schema_type| {
            return switch (schema_type) {
                .string => "[]const u8",
                .integer => "i64",
                .number => "f64",
                .boolean => "bool",
                .array => blk: {
                    if (schema.items) |items| {
                        const item_type = try self.getZigType(items.*);
                        if (std.mem.eql(u8, item_type, "[]const u8")) {
                            break :blk "[]const []const u8";
                        } else if (std.mem.eql(u8, item_type, "i64")) {
                            break :blk "[]const i64";
                        } else if (std.mem.eql(u8, item_type, "f64")) {
                            break :blk "[]const f64";
                        } else if (std.mem.eql(u8, item_type, "bool")) {
                            break :blk "[]const bool";
                        } else {
                            break :blk "[]const std.json.Value";
                        }
                    } else {
                        break :blk "[]const u8";
                    }
                },
                .object => "std.json.Value",
                .reference => "[]const u8",
            };
        }

        return "[]const u8";
    }

    fn isFieldRequired(self: *UnifiedModelGenerator, field_name: []const u8, required: ?[][]const u8) bool {
        _ = self;
        if (required == null) return false;

        for (required.?) |req_field| {
            if (std.mem.eql(u8, field_name, req_field)) {
                return true;
            }
        }

        return false;
    }
};
