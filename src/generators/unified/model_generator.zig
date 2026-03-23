const std = @import("std");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;
const zig_identifier = @import("../zig_identifier.zig");

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
        try self.buffer.appendSlice(self.allocator, "const std = @import(\"std\");\n\n");
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
        try zig_identifier.append(&self.buffer, self.allocator, name);
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
        try zig_identifier.append(&self.buffer, self.allocator, field_name);
        try self.buffer.appendSlice(self.allocator, ": ");

        if (!is_required) {
            try self.buffer.appendSlice(self.allocator, "?");
        }

        try self.appendZigType(field_schema);

        if (!is_required) {
            try self.buffer.appendSlice(self.allocator, " = null");
        }

        try self.buffer.appendSlice(self.allocator, ",\n");
    }

    fn appendZigType(self: *UnifiedModelGenerator, schema: Schema) !void {
        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                try zig_identifier.append(&self.buffer, self.allocator, ref[last_slash + 1 ..]);
                return;
            }

            try self.buffer.appendSlice(self.allocator, "[]const u8");
            return;
        }

        if (schema.type) |schema_type| {
            switch (schema_type) {
                .string => try self.buffer.appendSlice(self.allocator, "[]const u8"),
                .integer => try self.buffer.appendSlice(self.allocator, "i64"),
                .number => try self.buffer.appendSlice(self.allocator, "f64"),
                .boolean => try self.buffer.appendSlice(self.allocator, "bool"),
                .array => {
                    if (schema.items) |items| {
                        if (items.ref != null) {
                            try self.buffer.appendSlice(self.allocator, "[]const std.json.Value");
                        } else if (items.type) |item_type| {
                            switch (item_type) {
                                .string => try self.buffer.appendSlice(self.allocator, "[]const []const u8"),
                                .integer => try self.buffer.appendSlice(self.allocator, "[]const i64"),
                                .number => try self.buffer.appendSlice(self.allocator, "[]const f64"),
                                .boolean => try self.buffer.appendSlice(self.allocator, "[]const bool"),
                                else => try self.buffer.appendSlice(self.allocator, "[]const std.json.Value"),
                            }
                        } else {
                            try self.buffer.appendSlice(self.allocator, "[]const u8");
                        }
                    } else {
                        try self.buffer.appendSlice(self.allocator, "[]const u8");
                    }
                },
                .object => try self.buffer.appendSlice(self.allocator, "std.json.Value"),
                .reference => try self.buffer.appendSlice(self.allocator, "[]const u8"),
            }

            return;
        }

        try self.buffer.appendSlice(self.allocator, "[]const u8");
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
