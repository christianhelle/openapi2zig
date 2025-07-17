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

fn getDataType(field_schema: []const u8) ![]const u8 {
    if (std.mem.eql(u8, field_schema, "string")) {
        return "[]const u8";
    } else if (std.mem.eql(u8, field_schema, "integer")) {
        return "i64";
    } else if (std.mem.eql(u8, field_schema, "number")) {
        return "f64";
    } else if (std.mem.eql(u8, field_schema, "boolean")) {
        return "bool";
    } else if (std.mem.eql(u8, field_schema, "array")) {
        return "[]const u8"; // TODO: handle array items type
    } else if (std.mem.eql(u8, field_schema, "object")) {
        return "std.json.Value"; // or a generated struct if possible
    } else {
        return "[]const u8";
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
        try parts.append("const std = @import(\"std\");\n\n");

        var path_iterator = document.paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;

            if (path_item.get) |op| {
                try parts.append(try self.generateMethod(op, path, "GET"));
            }

            if (path_item.post) |op| {
                try parts.append(try self.generateMethod(op, path, "POST"));
            }

            if (path_item.put) |op| {
                try parts.append(try self.generateMethod(op, path, "PUT"));
            }

            if (path_item.delete) |op| {
                try parts.append(try self.generateMethod(op, path, "DELETE"));
            }
        }

        return try std.mem.join(self.allocator, "", parts.items);
    }

    pub fn generateMethod(self: *ApiCodeGenerator, op: models.Operation, path: []const u8, method: []const u8) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        try parts.append(try generateMethodDocs(self.allocator, op));
        try parts.append("pub fn ");
        try parts.append(op.operationId orelse path);
        try parts.append("(allocator: std.mem.Allocator");

        var parameters = std.ArrayList([]const u8).init(self.allocator);
        if (op.parameters) |params| {
            if (params.len > 0) try parts.append(", ");
            var first = true;
            for (params) |param| {
                if (!first) try parts.append(", ");
                first = false;

                switch (param) {
                    .parameter => |p| {
                        try parameters.append(p.name);
                        try parts.append(p.name);
                        try parts.append(": ");

                        const field_name = p.schema.?.schema.type orelse "[]const u8";
                        const data_type = try getDataType(field_name);
                        try parts.append(data_type); // Unwrap the optional, as it can never be null
                    },
                    .reference => |_| {
                        try parts.append("[]const u8"); // Assume string type for references
                    },
                }
            }
        }

        if (op.requestBody) |request_body| {
            try parts.append(", requestBody: ");
            var data_type: []const u8 = "[]const u8"; // Default to string type

            // Try to get application/json content directly using get method
            // This avoids iterating over the hashmap which causes memory issues
            if (request_body.request_body.content.count() > 0) {
                // For now, just check if we can find any content type that might have a schema
                // We'll improve this later when the memory issues are resolved
                var content_iterator = request_body.request_body.content.iterator();
                if (content_iterator.next()) |first_entry| {
                    const media_type = first_entry.value_ptr.*;
                    if (media_type.schema) |schema_or_ref| {
                        switch (schema_or_ref) {
                            .schema => |schema_ptr| {
                                if (schema_ptr.type) |schemaName| {
                                    data_type = try getDataType(schemaName);
                                }
                            },
                            .reference => |ref| {
                                if (self.extractTypeFromReference(ref.ref)) |type_name| {
                                    data_type = type_name;
                                }
                            },
                        }
                    }
                }
            }

            try parts.append(data_type);
            try parameters.append("requestBody");
        }

        try parts.append(") !void {\n");

        try parts.append("    // Avoid warnings about unused parameters\n");
        for (parameters.items) |param| {
            try parts.append("    _ = ");
            try parts.append(param);
            try parts.append(";\n");
        }
        try parts.append("\n");

        try parts.append("    var client = std.http.Client.init(allocator);\n");
        try parts.append("    defer client.deinit();\n\n");
        try parts.append("    const uri = try std.Uri.parse(\"");
        try parts.append(path);
        try parts.append("\");\n");
        try parts.append(
            \\    const buf = try allocator.alloc(u8, 1024 * 8);
            \\    defer allocator.free(buf);
        );
        try parts.append("   var req = try client.open(.");
        try parts.append(method);
        try parts.append(", uri, .{\n");
        try parts.append(
            \\        .server_header_buffer = buf,
            \\    });
            \\    defer req.deinit();
            \\
            \\    try req.send();
            \\    try req.finish();
            \\    try req.wait();
        );
        try parts.append("\n");
        try parts.append("}\n\n");

        return try std.mem.join(self.allocator, "", parts.items);
    }

    fn extractTypeFromReference(self: *ApiCodeGenerator, ref: []const u8) ?[]const u8 {
        _ = self;
        // Extract type name from reference like "#/components/schemas/Pet" -> "Pet"
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash_index| {
            if (last_slash_index + 1 < ref.len) {
                return ref[last_slash_index + 1 ..];
            }
        }
        return null;
    }

    fn generateMethodDocs(allocator: std.mem.Allocator, op: models.Operation) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        if (op.summary != null or op.description != null) {
            try parts.append("/////////////////");
            try parts.append("\n");
        }
        if (op.summary) |summary| {
            if (summary.len > 0) {
                try parts.append("// Summary:\n");
                try parts.append("// ");
                try parts.append(summary);
                try parts.append("\n//\n");
            }
        }
        if (op.description) |description| {
            if (description.len > 0) {
                try parts.append("// Description:\n");
                try parts.append("// ");
                try parts.append(description);
                try parts.append("\n//\n");
            }
        }

        return try std.mem.join(allocator, "", parts.items);
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

                const data_type = try getDataType(field_schema);
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
