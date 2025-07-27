const std = @import("std");
const models = @import("../../models.zig");
const cli = @import("../../cli.zig");
const detector = @import("../../detector.zig");
const converter = @import("../converter.zig");
const default_output_file: []const u8 = "generated.zig";

pub const ApiCodeGenerator = struct {
    allocator: std.mem.Allocator,
    args: cli.CliArgs,

    pub fn init(allocator: std.mem.Allocator, args: cli.CliArgs) ApiCodeGenerator {
        return ApiCodeGenerator{
            .allocator = allocator,
            .args = args,
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
        var methods = std.ArrayList([]const u8).init(self.allocator);
        defer methods.deinit();
        var path_iterator = document.paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path_key = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;
            const path = if (self.args.base_url) |base_url| try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_url, path_key }) else path_key;
            defer if (self.args.base_url != null) self.allocator.free(path);
            if (path_item.get) |op| {
                try methods.append(try self.generateMethod(op, path, "GET"));
            }
            if (path_item.post) |op| {
                try methods.append(try self.generateMethod(op, path, "POST"));
            }
            if (path_item.put) |op| {
                try methods.append(try self.generateMethod(op, path, "PUT"));
            }
            if (path_item.delete) |op| {
                try methods.append(try self.generateMethod(op, path, "DELETE"));
            }
            if (path_item.patch) |op| {
                try methods.append(try self.generateMethod(op, path, "PATCH"));
            }
            if (path_item.head) |op| {
                try methods.append(try self.generateMethod(op, path, "HEAD"));
            }
            if (path_item.options) |op| {
                try methods.append(try self.generateMethod(op, path, "OPTIONS"));
            }
        }
        for (methods.items) |method| {
            try parts.append(method);
        }
        const code = try std.mem.join(self.allocator, "", parts.items);
        for (methods.items) |item| {
            defer self.allocator.free(item);
        }
        return code;
    }

    pub fn generateMethod(self: *ApiCodeGenerator, op: models.v3.Operation, path: []const u8, method: []const u8) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();
        const docs = try generateMethodDocs(self.allocator, op);
        defer self.allocator.free(docs);
        try parts.append(docs);
        try parts.append("pub fn ");
        try parts.append(op.operationId orelse path);
        try parts.append("(allocator: std.mem.Allocator");
        var parameters = std.ArrayList([]const u8).init(self.allocator);
        defer parameters.deinit();
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
                        const data_type = try converter.getDataType(field_name);
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
            if (request_body.request_body.content.count() > 0) {
                var content_iterator = request_body.request_body.content.iterator();
                if (content_iterator.next()) |first_entry| {
                    const media_type = first_entry.value_ptr.*;
                    if (media_type.schema) |schema_or_ref| {
                        switch (schema_or_ref) {
                            .schema => |schema_ptr| {
                                if (schema_ptr.type) |schemaName| {
                                    data_type = try converter.getDataType(schemaName);
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
        }
        try parts.append(") !void {\n");
        const method_body = try generateImplementation(self.allocator, path, method, op);
        defer self.allocator.free(method_body);
        try parts.append(method_body);
        try parts.append("}\n\n");
        return try std.mem.join(self.allocator, "", parts.items);
    }

    fn generateImplementation(allocator: std.mem.Allocator, path: []const u8, method: []const u8, op: models.v3.Operation) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();
        const has_request_body = op.requestBody != null;
        if (op.parameters) |params| {
            if (params.len > 0) {
                for (params) |paramOrReference| {
                    const parameter = paramOrReference.parameter;
                    if (!std.mem.eql(u8, parameter.in_field, "path") and !std.mem.eql(u8, parameter.in_field, "body")) {
                        try parts.append("    _ = ");
                        try parts.append(parameter.name);
                        try parts.append(";\n");
                    }
                }
                if (has_request_body) {
                    try parts.append("\n");
                }
            }
        }
        try parts.append("    var client = std.http.Client { .allocator = allocator };\n");
        try parts.append("    defer client.deinit();\n\n");
        var allocations = std.ArrayList([]const u8).init(allocator);
        defer allocations.deinit();
        if (op.parameters) |params| {
            var new_path = path;
            for (params) |paramOrReference| {
                const parameter = paramOrReference.parameter;
                if (!std.mem.eql(u8, parameter.in_field, "path")) continue;
                const name = parameter.name;
                const size = std.mem.replacementSize(u8, new_path, name, "any");
                const output = try allocator.alloc(u8, size);
                _ = std.mem.replace(u8, new_path, name, "any", output);
                new_path = output;
                try allocations.append(output);
            }
            try parts.append("    const uri_str = try std.fmt.allocPrint(allocator, \"");
            try parts.append(new_path);
            try parts.append("\", .{");
            var pos: i32 = 0;
            for (params) |paramOrReference| {
                const parameter = paramOrReference.parameter;
                if (!std.mem.eql(u8, parameter.in_field, "path")) continue;
                const name = parameter.name;
                try parts.append(name);
                pos += 1;
                if (pos < params.len)
                    try parts.append(", ");
            }
            try parts.append("});\n");
            try parts.append("    defer allocator.free(uri_str);\n\n");
            try parts.append("    const uri = try std.Uri.parse(uri_str);\n");
        } else {
            try parts.append("    const uri = try std.Uri.parse(\"");
            try parts.append(path);
            try parts.append("\");\n");
        }
        try parts.append(
            \\    const buf = try allocator.alloc(u8, 1024 * 8);
            \\    defer allocator.free(buf);
        );
        try parts.append("\n\n");
        try parts.append("    var req = try client.open(.");
        try parts.append(method);
        try parts.append(", uri, .{\n");
        try parts.append(
            \\        .server_header_buffer = buf,
            \\    });
            \\    defer req.deinit();
            \\
            \\    try req.send();
        );
        if (has_request_body) {
            try parts.append("\n\n");
            try parts.append("    var str = std.ArrayList(u8).init(allocator);\n");
            try parts.append("    defer str.deinit();\n\n");
            try parts.append("    try std.json.stringify(requestBody, .{}, str.writer());\n");
            try parts.append("    const body = try std.mem.join(allocator, \"\", str.items);\n");
            try parts.append("    defer allocator.free(body);\n\n");
            try parts.append("    req.transfer_encoding = .{ .content_length = body.len };\n");
            try parts.append("    try req.writeAll(body);\n\n");
        } else {
            try parts.append("\n");
        }
        try parts.append(
            \\    try req.finish();
            \\    try req.wait();
            \\
        );
        const code = try std.mem.join(allocator, "", parts.items);
        for (allocations.items) |alloc| {
            allocator.free(alloc);
        }
        return code;
    }

    fn extractTypeFromReference(self: *ApiCodeGenerator, ref: []const u8) ?[]const u8 {
        _ = self;
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash_index| {
            if (last_slash_index + 1 < ref.len) {
                return ref[last_slash_index + 1 ..];
            }
        }
        return null;
    }

    fn generateMethodDocs(allocator: std.mem.Allocator, op: models.v3.Operation) ![]const u8 {
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
