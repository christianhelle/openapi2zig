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
            .buffer = std.ArrayList(u8){},
            .args = args,
        };
    }

    pub fn deinit(self: *UnifiedApiGenerator) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn generate(self: *UnifiedApiGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.generateHeader();
        try self.generateApiClient(document);
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn generateHeader(self: *UnifiedApiGenerator) !void {
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n");
        try self.buffer.appendSlice(self.allocator, "// Generated Zig API client from OpenAPI\n");
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n\n");
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
            try self.buffer.appendSlice(self.allocator, "/////////////////\n");
            try self.buffer.appendSlice(self.allocator, "// Summary:\n");
            try self.buffer.appendSlice(self.allocator, "// ");
            try self.buffer.appendSlice(self.allocator, summary);
            try self.buffer.appendSlice(self.allocator, "\n");
            try self.buffer.appendSlice(self.allocator, "//\n");
        }

        if (operation.description) |description| {
            try self.buffer.appendSlice(self.allocator, "// Description:\n");
            try self.buffer.appendSlice(self.allocator, "// ");
            try self.buffer.appendSlice(self.allocator, description);
            try self.buffer.appendSlice(self.allocator, "\n");
            try self.buffer.appendSlice(self.allocator, "//\n");
        }
    }

    fn generateFunctionSignature(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "pub fn ");

        if (operation.operationId) |op_id| {
            try self.buffer.appendSlice(self.allocator, op_id);
        } else {
            try self.buffer.appendSlice(self.allocator, "operation");
            try self.buffer.appendSlice(self.allocator, path[1..]); // Remove leading slash
        }
        try self.buffer.appendSlice(self.allocator, "(allocator: std.mem.Allocator");
        var has_body_param = false;
        var path_parameters = std.ArrayList([]const u8){};
        defer path_parameters.deinit(self.allocator);
        if (operation.parameters) |params| {
            if (params.len > 0) try self.buffer.appendSlice(self.allocator, ", ");
            var first = true;
            for (params) |param| {
                if (!first) try self.buffer.appendSlice(self.allocator, ", ");
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
                            data_type = self.getZigTypeFromSchema(schema);
                        }
                    }
                } else if (param.location == .path) {
                    try path_parameters.append(self.allocator, param.name);
                    if (param.type) |param_type| {
                        data_type = self.getZigTypeFromSchemaType(param_type);
                    }
                } else {
                    if (param.type) |param_type| {
                        data_type = self.getZigTypeFromSchemaType(param_type);
                    }
                }
                try self.buffer.appendSlice(self.allocator, name);
                try self.buffer.appendSlice(self.allocator, ": ");
                try self.buffer.appendSlice(self.allocator, data_type);
            }
        }

        const return_type = self.getReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, ") !");
        try self.buffer.appendSlice(self.allocator, return_type);
        try self.buffer.appendSlice(self.allocator, " {\n");
    }

    fn getReturnType(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) []const u8 {
        if (std.mem.eql(u8, method, "GET")) {
            if (operation.responses.get("200")) |path_item| {
                if (path_item.schema) |schema| {
                    return self.getZigTypeFromSchema(schema);
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
                        try self.buffer.appendSlice(self.allocator, "    _ = ");
                        try self.buffer.appendSlice(self.allocator, parameter.name);
                        try self.buffer.appendSlice(self.allocator, ";\n");
                    }
                }
            }
        }

        try self.buffer.appendSlice(self.allocator, "    var client = std.http.Client { .allocator = allocator };\n");
        try self.buffer.appendSlice(self.allocator, "    defer client.deinit();\n\n");

        try self.buffer.appendSlice(self.allocator, "    const headers = &[_]std.http.Header{\n");
        try self.buffer.appendSlice(self.allocator, "        .{ .name = \"Content-Type\", .value = \"application/json\" },\n");
        try self.buffer.appendSlice(self.allocator, "        .{ .name = \"Accept\", .value = \"application/json\" },\n");
        try self.buffer.appendSlice(self.allocator, "    };\n");
        try self.buffer.appendSlice(self.allocator, "\n");

        if (operation.parameters) |parameters| {
            var new_path = path;
            var allocated_paths = std.ArrayList([]u8){};
            defer {
                for (allocated_paths.items) |allocated_path| {
                    self.allocator.free(allocated_path);
                }
                allocated_paths.deinit(self.allocator);
            }

            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                const param = parameter.name;
                const param_type = switch (parameter.type orelse .string) {
                    .string => "s",
                    .integer => "d",
                    .number => "d",
                    else => "any",
                };
                const size = std.mem.replacementSize(u8, new_path, param, param_type);
                const output = try self.allocator.alloc(u8, size);
                try allocated_paths.append(self.allocator, output);
                _ = std.mem.replace(u8, new_path, param, param_type, output);
                new_path = output;
            }

            try self.buffer.appendSlice(self.allocator, "    const uri_str = try std.fmt.allocPrint(allocator, \"");
            if (self.args.base_url) |base_url| {
                try self.buffer.appendSlice(self.allocator, base_url);
            }
            try self.buffer.appendSlice(self.allocator, new_path);
            try self.buffer.appendSlice(self.allocator, "\", .{");

            var pos: i32 = 0;
            for (parameters) |parameter| {
                if (parameter.location != .path) continue;
                const param = parameter.name;
                try self.buffer.appendSlice(self.allocator, param);
                pos += 1;
                if (pos < parameters.len)
                    try self.buffer.appendSlice(self.allocator, ", ");
            }
            try self.buffer.appendSlice(self.allocator, "});\n");

            try self.buffer.appendSlice(self.allocator, "    defer allocator.free(uri_str);\n");
            try self.buffer.appendSlice(self.allocator, "    const uri = try std.Uri.parse(uri_str);\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "    const uri = try std.Uri.parse(\"");
            if (self.args.base_url) |base_url| {
                try self.buffer.appendSlice(self.allocator, base_url);
            }
            try self.buffer.appendSlice(self.allocator, path);
            try self.buffer.appendSlice(self.allocator, "\");\n");
        }

        try self.buffer.appendSlice(self.allocator, "    var req = try client.request(std.http.Method.");
        try self.buffer.appendSlice(self.allocator, method);
        try self.buffer.appendSlice(self.allocator, ", uri, .{ .extra_headers = headers });\n");
        try self.buffer.appendSlice(self.allocator, "    defer req.deinit();\n\n");

        if (std.mem.eql(u8, method, "POST") or std.mem.eql(u8, method, "PUT") or std.mem.eql(u8, method, "PATCH")) {
            if (operation.parameters) |params| {
                for (params) |param| {
                    if (param.location == .body) {
                        try self.buffer.appendSlice(self.allocator, "    var str = std.ArrayList(u8){};\n");
                        try self.buffer.appendSlice(self.allocator, "    defer str.deinit(allocator);\n\n");
                        try self.buffer.appendSlice(self.allocator, "    try std.json.stringify(requestBody, .{}, str.writer());\n");
                        try self.buffer.appendSlice(self.allocator, "    const payload = str.items;\n\n");
                        try self.buffer.appendSlice(self.allocator, "    req.transfer_encoding = .{ .content_length = payload.len };\n");
                        try self.buffer.appendSlice(self.allocator, "    try req.sendBodyComplete(payload);\n\n");
                        break;
                    }
                }
            }
        } else {
            try self.buffer.appendSlice(self.allocator, "    try req.sendBodiless();\n");
        }

        const return_type = self.getReturnType(method, operation);
        if (!std.mem.eql(u8, return_type, "void")) {
            try self.buffer.appendSlice(self.allocator, "\n");
            try self.buffer.appendSlice(self.allocator, "    var response = try req.receiveHead(&.{});\n");
            try self.buffer.appendSlice(self.allocator, "    if (response.head.status != .ok) {\n");
            try self.buffer.appendSlice(self.allocator, "        return error.ResponseError;\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");
            try self.buffer.appendSlice(self.allocator, "    var reader_buffer: [100]u8 = undefined;\n");
            try self.buffer.appendSlice(self.allocator, "    const body_reader = response.reader(&reader_buffer);\n");
            try self.buffer.appendSlice(self.allocator, "    const body = try body_reader.readAlloc(allocator, response.head.content_length orelse 1024 * 1024 * 4);\n");
            try self.buffer.appendSlice(self.allocator, "    defer allocator.free(body);\n\n");
            try self.buffer.appendSlice(self.allocator, "    const parsed = try std.json.parseFromSlice(");
            try self.buffer.appendSlice(self.allocator, return_type);
            try self.buffer.appendSlice(self.allocator, ", allocator, body, .{});\n");
            try self.buffer.appendSlice(self.allocator, "    defer parsed.deinit();\n\n");
            try self.buffer.appendSlice(self.allocator, "    return parsed.value;\n");
        }

        try self.buffer.appendSlice(self.allocator, "}\n\n");
    }

    fn getZigTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) []const u8 {
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
