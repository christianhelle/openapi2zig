const std = @import("std");
const cli = @import("../../cli.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../models/common/document.zig").Operation;
const Parameter = @import("../../models/common/document.zig").Parameter;
const ParameterLocation = @import("../../models/common/document.zig").ParameterLocation;
const Response = @import("../../models/common/document.zig").Response;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;

pub const UnifiedApiGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    args: cli.CliArgs,

    pub fn init(allocator: std.mem.Allocator, args: cli.CliArgs) UnifiedApiGenerator {
        return UnifiedApiGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .args = args,
        };
    }

    pub fn deinit(self: *UnifiedApiGenerator) void {
        self.buffer.deinit();
    }

    pub fn generate(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.generateHeader();
        try self.generateApiClient(document);
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn generateHeader(self: *UnifiedApiGenerator) !void {
        try self.buffer.appendSlice("///////////////////////////////////////////\n");
        try self.buffer.appendSlice("// Generated Zig API client from OpenAPI\n");
        try self.buffer.appendSlice("///////////////////////////////////////////\n\n");
        try self.buffer.appendSlice("const std = @import(\"std\");\n\n");
    }

    fn generateApiClient(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
        var path_iterator = document.paths.iterator();
        while (path_iterator.next()) |entry| {
            const path = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;
            try self.generateOperations(path, path_item);
        }
    }

    fn generateOperations(self: *UnifiedApiGenerator, path: []const u8, path_item: @import("../../models/common/document.zig").PathItem) !void {
        if (path_item.get) |op| try self.generateOperation("GET", path, op);
        if (path_item.post) |op| try self.generateOperation("POST", path, op);
        if (path_item.put) |op| try self.generateOperation("PUT", path, op);
        if (path_item.delete) |op| try self.generateOperation("DELETE", path, op);
        if (path_item.patch) |op| try self.generateOperation("PATCH", path, op);
        if (path_item.head) |op| try self.generateOperation("HEAD", path, op);
        if (path_item.options) |op| try self.generateOperation("OPTIONS", path, op);
    }

    fn generateOperation(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.generateComments(operation);
        try self.generateFunctionSignature(method, path, operation);
        try self.generateFunctionBody(method, path, operation);
    }

    fn generateComments(self: *UnifiedApiGenerator, operation: Operation) !void {
        if (operation.summary) |summary| {
            try self.buffer.appendSlice("/////////////////\n");
            try self.buffer.appendSlice("// Summary:\n");
            try self.buffer.appendSlice("// ");
            try self.buffer.appendSlice(summary);
            try self.buffer.appendSlice("\n");
            try self.buffer.appendSlice("//\n");
        }

        if (operation.description) |description| {
            try self.buffer.appendSlice("// Description:\n");
            try self.buffer.appendSlice("// ");
            try self.buffer.appendSlice(description);
            try self.buffer.appendSlice("\n");
            try self.buffer.appendSlice("//\n");
        }
    }

    fn generateFunctionSignature(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.buffer.appendSlice("pub fn ");

        if (operation.operationId) |op_id| {
            try self.buffer.appendSlice(op_id);
        } else {
            try self.buffer.appendSlice("operation");
            try self.buffer.appendSlice(path[1..]); // Remove leading slash
        }
        try self.buffer.appendSlice("(allocator: std.mem.Allocator");
        var has_body_param = false;
        var path_parameters = std.ArrayList([]const u8).init(self.allocator);
        defer path_parameters.deinit();
        if (operation.parameters) |params| {
            if (params.len > 0) try self.buffer.appendSlice(", ");
            var first = true;
            for (params) |param| {
                if (!first) try self.buffer.appendSlice(", ");
                first = false;
                var data_type: []const u8 = "[]const u8"; // Default to string
                var name: []const u8 = param.name;
                if (param.location == .body) {
                    has_body_param = true;
                    name = "requestBody";
                    if (param.schema) |schema| {
                        if (schema.ref) |ref| {
                            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                                data_type = ref[last_slash + 1 ..];
                            }
                        } else {
                            data_type = try self.getZigTypeFromSchema(schema);
                        }
                    }
                } else if (param.location == .path) {
                    try path_parameters.append(param.name);
                    if (param.type) |param_type| {
                        data_type = self.getZigTypeFromSchemaType(param_type);
                    }
                } else {
                    if (param.type) |param_type| {
                        data_type = self.getZigTypeFromSchemaType(param_type);
                    }
                }
                try self.buffer.appendSlice(name);
                try self.buffer.appendSlice(": ");
                try self.buffer.appendSlice(data_type);
            }
        }

        const return_type = self.getReturnType(method, operation);
        try self.buffer.appendSlice(") !");
        try self.buffer.appendSlice(return_type);
        try self.buffer.appendSlice(" {\n");
    }

    fn getReturnType(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) []const u8 {
        if (std.mem.eql(u8, method, "GET")) {
            if (operation.responses.get("200")) |path_item| {
                if (path_item.schema) |schema| {
                    return try self.getZigTypeFromSchema(schema);
                }
            }
        }

        return "void";
    }

    fn generateFunctionBody(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        if (operation.parameters) |parameters| {
            if (parameters.len > 0) {
                for (parameters) |parameter| {
                    if (parameter.location != .path and parameter.location != .body) {
                        try self.buffer.appendSlice("    _ = ");
                        try self.buffer.appendSlice(parameter.name);
                        try self.buffer.appendSlice(";\n");
                    }
                }
            }
        }

        try self.buffer.appendSlice("    var client = std.http.Client { .allocator = allocator };\n");
        try self.buffer.appendSlice("    defer client.deinit();\n\n");

        try self.buffer.appendSlice("    var header_buffer: [8192]u8 = undefined;\n");
        try self.buffer.appendSlice("    const headers = &[_]std.http.Header{\n");
        try self.buffer.appendSlice("        .{ .name = \"Content-Type\", .value = \"application/json\" },\n");
        try self.buffer.appendSlice("        .{ .name = \"Accept\", .value = \"application/json\" },\n");
        try self.buffer.appendSlice("    };\n");
        try self.buffer.appendSlice("\n");

        if (operation.parameters) |parameters| {
            var new_path = path;
            var allocated_paths = std.ArrayList([]u8).init(self.allocator);
            defer {
                for (allocated_paths.items) |allocated_path| {
                    self.allocator.free(allocated_path);
                }
                allocated_paths.deinit();
            }

            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                const param = parameter.name;
                const size = std.mem.replacementSize(u8, new_path, param, "s");
                const output = try self.allocator.alloc(u8, size);
                try allocated_paths.append(output);
                _ = std.mem.replace(u8, new_path, param, "s", output);
                new_path = output;
            }

            try self.buffer.appendSlice("    const uri_str = try std.fmt.allocPrint(allocator, \"");
            if (self.args.base_url) |base_url| {
                try self.buffer.appendSlice(base_url);
            }
            try self.buffer.appendSlice(new_path);
            try self.buffer.appendSlice("\", .{");

            var pos: i32 = 0;
            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                const param = parameter.name;
                try self.buffer.appendSlice(param);
                pos += 1;
                if (pos < parameters.len)
                    try self.buffer.appendSlice(", ");
            }
            try self.buffer.appendSlice("});\n");

            try self.buffer.appendSlice("    defer allocator.free(uri_str);\n");
            try self.buffer.appendSlice("    const uri = try std.Uri.parse(uri_str);\n");
        } else {
            try self.buffer.appendSlice("    const uri = try std.Uri.parse(\"");
            if (self.args.base_url) |base_url| {
                try self.buffer.appendSlice(base_url);
            }
            try self.buffer.appendSlice(path);
            try self.buffer.appendSlice("\");\n");
        }

        try self.buffer.appendSlice("    var req = try client.open(std.http.Method.");
        try self.buffer.appendSlice(method);
        try self.buffer.appendSlice(", uri, .{ .server_header_buffer = &header_buffer, .extra_headers = headers });\n");
        try self.buffer.appendSlice("    defer req.deinit();\n\n");

        if (std.mem.eql(u8, method, "POST") or std.mem.eql(u8, method, "PUT") or std.mem.eql(u8, method, "PATCH")) {
            if (operation.parameters) |params| {
                for (params) |param| {
                    if (param.location == .body) {
                        try self.buffer.appendSlice("    var str = std.ArrayList(u8).init(allocator);\n");
                        try self.buffer.appendSlice("    defer str.deinit();\n\n");
                        try self.buffer.appendSlice("    try std.json.stringify(requestBody, .{}, str.writer());\n");
                        try self.buffer.appendSlice("    const payload = str.items;\n\n");
                        try self.buffer.appendSlice("    req.transfer_encoding = .{ .content_length = payload.len };\n");
                        try self.buffer.appendSlice("    try req.writeAll(payload);\n\n");
                        break;
                    }
                }
            }
        }

        try self.buffer.appendSlice("    try req.send();\n");
        try self.buffer.appendSlice("    try req.finish();\n");
        try self.buffer.appendSlice("    try req.wait();\n");

        const return_type = self.getReturnType(method, operation);
        if (!std.mem.eql(u8, return_type, "!void")) {
            try self.buffer.appendSlice("\n");
            try self.buffer.appendSlice("    const response = req.response;\n");
            try self.buffer.appendSlice("    if (response.status != .ok) {\n");
            try self.buffer.appendSlice("        return error.ResponseError;\n");
            try self.buffer.appendSlice("    }\n\n");
            try self.buffer.appendSlice("    const body = try response.body.readAll(allocator);\n");
            try self.buffer.appendSlice("    defer allocator.free(body);\n\n");
            try self.buffer.appendSlice("    const json_value = try std.json.parseFromSlice(");
            try self.buffer.appendSlice(return_type);
            try self.buffer.appendSlice(", allocator, body, .{});\n");
            try self.buffer.appendSlice("    return json_value;\n");
        }

        try self.buffer.appendSlice("}\n\n");
    }

    fn getZigTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) ![]const u8 {
        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                return ref[last_slash + 1 ..];
            }
        }
        if (schema.type) |schema_type| {
            return self.getZigTypeFromSchemaType(schema_type);
        }
        return "[]const u8"; // default fallback
    }

    fn getZigTypeFromSchemaType(self: *UnifiedApiGenerator, schema_type: SchemaType) []const u8 {
        _ = self;
        return switch (schema_type) {
            .string => "[]const u8",
            .integer => "i64",
            .number => "f64",
            .boolean => "bool",
            .array => "[]const u8", // Simplified for now
            .object => "std.json.Value",
            .reference => "[]const u8",
        };
    }
};
