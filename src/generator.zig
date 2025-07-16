const std = @import("std");
const models = @import("models.zig");

const default_output_file: []const u8 = "generated_models.zig";

pub fn generateCode(allocator: std.mem.Allocator, input_file_path: []const u8, output_file_path: ?[]const u8) !void {
    const openapi_file = try std.fs.cwd().openFile(input_file_path, .{});
    defer openapi_file.close();

    try openapi_file.seekBy(0);
    const file_contents = try openapi_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var openapi = try models.OpenApiDocument.parseFromJson(allocator, file_contents);
    defer openapi.deinit(allocator);

    var model_generator = ModelCodeGenerator.init(allocator);
    defer model_generator.deinit();

    const generated_models = try model_generator.generate(openapi);
    defer allocator.free(generated_models);

    var api_generator = ApiCodeGenerator.init(allocator);
    defer api_generator.deinit();

    const generated_api = try api_generator.generate(openapi);
    defer allocator.free(generated_api);

    const generated_code = try std.mem.join(allocator, "\n", &.{ generated_models, generated_api });

    if (output_file_path) |output_path| {
        if (std.fs.path.dirname(output_path)) |dir_path| {
            try std.fs.cwd().makePath(dir_path);
        }
        const output_file = try std.fs.cwd().createFile(output_path, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Models generated successfully and written to '{s}'.\n", .{output_path});
    } else {
        const output_file = try std.fs.cwd().createFile(default_output_file, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Models generated successfully and written to 'generated_models.zig'.\n", .{});
    }
}

pub const ApiCodeGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ApiCodeGenerator {
        return ApiCodeGenerator{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ApiCodeGenerator) void {
        _ = self;
    }

    pub fn generate(self: *ApiCodeGenerator, document: models.OpenApiDocument) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        try parts.append("///////////////////////////////////////////\n");
        try parts.append("// Generated Zig API client from OpenAPI\n");
        try parts.append("///////////////////////////////////////////\n\n");

        var path_iterator = document.paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;

            if (path_item.get) |op| {
                const name = op.operationId orelse try std.fmt.allocPrint(self.allocator, "get_{s}", .{path});
                const line = try std.fmt.allocPrint(self.allocator, "pub fn {s}(self: *const Self) !void", .{name});
                try parts.append(line);
                try parts.append("  {\n");
                try parts.append("    // Implement GET ");
                try parts.append(path);
                try parts.append("\n");
                try parts.append("}\n\n");
            }

            if (path_item.post) |op| {
                const name = op.operationId orelse try std.fmt.allocPrint(self.allocator, "post_{s}", .{path});
                const line = try std.fmt.allocPrint(self.allocator, "pub fn {s}(self: *const Self) !void", .{name});
                try parts.append(line);
                try parts.append("  {\n");
                try parts.append("    // Implement POST ");
                try parts.append(path);
                try parts.append("\n");
                try parts.append("}\n\n");
            }
        }

        return try std.mem.join(self.allocator, "", parts.items);
    }
};

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
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        try parts.append("///////////////////////////////////////////\n");
        try parts.append("// Generated Zig structures from OpenAPI\n");
        try parts.append("///////////////////////////////////////////\n\n");

        if (document.components) |components| {
            if (components.schemas) |schemas| {
                try self.generateSchemas(&parts, schemas);
            }
        }

        return try std.mem.join(self.allocator, "", parts.items);
    }

    fn generateSchemas(self: *ModelCodeGenerator, parts: *std.ArrayList([]const u8), schemas: std.HashMap([]const u8, models.SchemaOrReference, std.hash_map.StringContext, 80)) !void {
        var iterator = schemas.iterator();
        while (iterator.next()) |entry| {
            const schema_name = entry.key_ptr.*;
            const schema_or_ref = entry.value_ptr.*;

            switch (schema_or_ref) {
                .schema => |schema_ptr| {
                    try self.generateSchema(parts, schema_name, schema_ptr.*);
                },
                .reference => |_| {
                    // Skip references for now
                },
            }
        }
    }

    fn generateSchema(self: *ModelCodeGenerator, parts: *std.ArrayList([]const u8), name: []const u8, schema: models.Schema) !void {
        try parts.append(try std.fmt.allocPrint(self.allocator, "pub const {s} = struct {{\n", .{name}));

        if (schema.properties) |properties| {
            var property_iterator = properties.iterator();
            while (property_iterator.next()) |property| {
                const field_name = property.key_ptr.*;
                const field_schema_or_ref = property.value_ptr;
                try self.generateField(parts, field_name, field_schema_or_ref, schema.required);
            }
        }

        try parts.append("};\n\n");
    }

    fn generateField(self: *ModelCodeGenerator, parts: *std.ArrayList([]const u8), field_name: []const u8, field_schema_or_ref: *models.SchemaOrReference, required_fields: ?[]const []const u8) !void {
        const name = try self.allocator.dupe(u8, field_name);
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

                var data_type: []const u8 = "[]const u8";
                if (std.mem.eql(u8, field_schema, "string")) {
                    data_type = "[]const u8";
                } else if (std.mem.eql(u8, field_schema, "integer")) {
                    data_type = "i64";
                } else if (std.mem.eql(u8, field_schema, "number")) {
                    data_type = "f64";
                } else if (std.mem.eql(u8, field_schema, "boolean")) {
                    data_type = "bool";
                } else if (std.mem.eql(u8, field_schema, "array")) {
                    data_type = "[]const u8"; // TODO: handle array items type
                } else if (std.mem.eql(u8, field_schema, "object")) {
                    data_type = "std.json.Value"; // or a generated struct if possible
                }

                if (is_required) {
                    try parts.append(try std.fmt.allocPrint(self.allocator, "    {s}: {s},\n", .{ name, data_type }));
                } else {
                    try parts.append(try std.fmt.allocPrint(self.allocator, "    {s}: ?{s} = null,\n", .{ name, data_type }));
                }
            },
            .reference => |_| {
                // For references, assume string type
                try parts.append(try std.fmt.allocPrint(self.allocator, "    {s}: ?[]const u8 = null,\n", .{field_name}));
            },
        }
    }
};
