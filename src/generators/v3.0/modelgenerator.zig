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

    pub fn generate(self: *ModelCodeGenerator, document: models.OpenApiDocument) ![]const u8 {
        var parts = std.ArrayList([]const u8){};
        defer parts.deinit(self.allocator);
        try parts.append(self.allocator, "///////////////////////////////////////////\n");
        try parts.append(self.allocator, "// Generated Zig structures from OpenAPI\n");
        try parts.append(self.allocator, "///////////////////////////////////////////\n\n");
        if (document.components) |components| {
            if (components.schemas) |schemas| {
                try generateSchemas(self.allocator, &parts, schemas);
            }
        }
        return try std.mem.join(self.allocator, "", parts.items);
    }
};

fn generateSchemas(allocator: std.mem.Allocator, parts: *std.ArrayList([]const u8), schemas: std.HashMap([]const u8, models.v3.SchemaOrReference, std.hash_map.StringContext, 80)) !void {
    var iterator = schemas.iterator();
    while (iterator.next()) |entry| {
        const schema_name = entry.key_ptr.*;
        const schema_or_ref = entry.value_ptr.*;
        switch (schema_or_ref) {
            .schema => |schema_ptr| {
                try generateSchema(allocator, parts, schema_name, schema_ptr.*);
            },
            .reference => |_| {},
        }
    }
}

fn generateSchema(allocator: std.mem.Allocator, parts: *std.ArrayList([]const u8), name: []const u8, schema: models.v3.Schema) !void {
    try parts.append(allocator, "pub const ");
    try parts.append(allocator, name);
    try parts.append(allocator, " = struct {\n");
    if (schema.properties) |properties| {
        var property_iterator = properties.iterator();
        while (property_iterator.next()) |property| {
            const field_name = property.key_ptr.*;
            const field_schema_or_ref = property.value_ptr;
            try generateField(allocator, parts, field_name, field_schema_or_ref, schema.required);
        }
    }
    try parts.append(allocator, "};\n\n");
}

fn generateField(allocator: std.mem.Allocator, parts: *std.ArrayList([]const u8), field_name: []const u8, field_schema_or_ref: *models.v3.SchemaOrReference, required_fields: ?[]const []const u8) !void {
    const name = field_name;
    switch (field_schema_or_ref.*) {
        .schema => |field_schema_ptr| {
            const field_schema = field_schema_ptr.type.?; // Unwrap the optional, as it can never be null
            const is_required = if (required_fields) |req_fields| blk: {
                for (req_fields) |req_field| {
                    if (std.mem.eql(u8, req_field, field_name)) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;
            try parts.append(allocator, "    ");
            try parts.append(allocator, name);
            try parts.append(allocator, ": ");
            const data_type = converter.getDataType(field_schema);
            if (is_required) {
                try parts.append(allocator, data_type);
                try parts.append(allocator, ",\n");
            } else {
                try parts.append(allocator, "?");
                try parts.append(allocator, data_type);
                try parts.append(allocator, " = null,\n");
            }
        },
        .reference => |_| {
            try parts.append(allocator, "    ");
            try parts.append(allocator, name);
            try parts.append(allocator, ": ?[]const u8 = null,\n");
        },
    }
}
