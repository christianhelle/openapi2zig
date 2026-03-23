const std = @import("std");
const cli = @import("../../cli.zig");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../models/common/document.zig").Operation;
const Parameter = @import("../../models/common/document.zig").Parameter;
const ParameterLocation = @import("../../models/common/document.zig").ParameterLocation;
const Response = @import("../../models/common/document.zig").Response;
const Schema = @import("../../models/common/document.zig").Schema;
const SchemaType = @import("../../models/common/document.zig").SchemaType;
const zig_identifier = @import("../zig_identifier.zig");

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
            try self.appendCommentLines(summary);
            try self.buffer.appendSlice(self.allocator, "//\n");
        }

        if (operation.description) |description| {
            try self.buffer.appendSlice(self.allocator, "// Description:\n");
            try self.appendCommentLines(description);
            try self.buffer.appendSlice(self.allocator, "//\n");
        }
    }

    fn appendCommentLines(self: *UnifiedApiGenerator, text: []const u8) !void {
        var line_start: usize = 0;
        var index: usize = 0;

        while (index < text.len) : (index += 1) {
            switch (text[index]) {
                '\n' => {
                    try self.appendCommentLine(text[line_start..index]);
                    line_start = index + 1;
                },
                '\r' => {
                    try self.appendCommentLine(text[line_start..index]);
                    if (index + 1 < text.len and text[index + 1] == '\n') {
                        index += 1;
                    }
                    line_start = index + 1;
                },
                else => {},
            }
        }

        if (text.len == 0 or line_start < text.len or text[text.len - 1] == '\n' or text[text.len - 1] == '\r') {
            try self.appendCommentLine(text[line_start..]);
        }
    }

    fn appendCommentLine(self: *UnifiedApiGenerator, line: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "// ");
        for (line) |byte| {
            switch (byte) {
                '\t' => try self.buffer.appendSlice(self.allocator, "    "),
                0...8, 11...12, 14...31, 127 => try self.appendHexEscape(byte),
                else => try self.buffer.append(self.allocator, byte),
            }
        }
        try self.buffer.appendSlice(self.allocator, "\n");
    }

    fn appendHexEscape(self: *UnifiedApiGenerator, byte: u8) !void {
        const hex_digits = "0123456789abcdef";
        const hi: usize = byte >> 4;
        const lo: usize = byte & 0x0f;
        const escaped = [_]u8{ '\\', 'x', hex_digits[hi], hex_digits[lo] };

        try self.buffer.appendSlice(self.allocator, &escaped);
    }

    fn generateFunctionSignature(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        try self.buffer.appendSlice(self.allocator, "pub fn ");

        if (operation.operationId) |op_id| {
            try zig_identifier.append(&self.buffer, self.allocator, op_id);
        } else {
            const fallback_name = try std.fmt.allocPrint(self.allocator, "operation{s}", .{if (path.len > 0) path[1..] else path});
            defer self.allocator.free(fallback_name);

            try zig_identifier.append(&self.buffer, self.allocator, fallback_name);
        }
        try self.buffer.appendSlice(self.allocator, "(allocator: std.mem.Allocator");
        if (operation.parameters) |params| {
            if (params.len > 0) try self.buffer.appendSlice(self.allocator, ", ");
            var first = true;
            for (params) |param| {
                if (!first) try self.buffer.appendSlice(self.allocator, ", ");
                first = false;

                try self.appendParameterIdentifier(param);

                try self.buffer.appendSlice(self.allocator, ": ");

                if (param.location == .body) {
                    if (param.schema) |schema| {
                        try self.appendZigTypeFromSchema(schema);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "[]const u8");
                    }
                } else if (param.type) |param_type| {
                    try self.appendZigTypeFromSchemaType(param_type);
                } else if (param.schema) |schema| {
                    try self.appendZigTypeFromSchema(schema);
                } else {
                    try self.buffer.appendSlice(self.allocator, "[]const u8");
                }
            }
        }

        try self.buffer.appendSlice(self.allocator, ") !");
        try self.appendReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, " {\n");
    }

    fn appendReturnType(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) !void {
        if (self.getReturnSchema(method, operation)) |schema| {
            try self.appendZigTypeFromSchema(schema);
            return;
        }

        try self.buffer.appendSlice(self.allocator, "void");
    }

    fn generateFunctionBody(self: *UnifiedApiGenerator, method: []const u8, path: []const u8, operation: Operation) !void {
        if (operation.parameters) |parameters| {
            var emitted_unused_discard = false;
            if (parameters.len > 0) {
                for (parameters) |parameter| {
                    if (parameter.location == .path) continue;
                    if (parameter.location == .body) continue;
                    try self.buffer.appendSlice(self.allocator, "    _ = ");
                    try self.appendParameterIdentifier(parameter);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                    emitted_unused_discard = true;
                }
            }

            if (emitted_unused_discard) {
                try self.buffer.appendSlice(self.allocator, "\n");
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
                try self.appendParameterIdentifier(parameter);
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

        var has_body_param = false;
        if (operation.parameters) |params| {
            for (params) |param| {
                if (param.location == .body) {
                    has_body_param = true;
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

        if (!has_body_param) {
            try self.buffer.appendSlice(self.allocator, "    try req.sendBodiless();\n");
        }

        if (self.getReturnSchema(method, operation) != null) {
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
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ", allocator, body, .{});\n");
            try self.buffer.appendSlice(self.allocator, "    defer parsed.deinit();\n\n");
            try self.buffer.appendSlice(self.allocator, "    return parsed.value;\n");
        }

        try self.buffer.appendSlice(self.allocator, "}\n\n");
    }

    fn getReturnSchema(self: *UnifiedApiGenerator, method: []const u8, operation: Operation) ?Schema {
        _ = self;
        if (std.mem.eql(u8, method, "GET")) {
            if (operation.responses.get("200")) |response| {
                if (response.schema) |schema| {
                    return schema;
                }
            }
        }

        return null;
    }

    fn appendParameterIdentifier(self: *UnifiedApiGenerator, parameter: Parameter) !void {
        if (parameter.location == .body) {
            try self.buffer.appendSlice(self.allocator, "requestBody");
            return;
        }

        const prefix = switch (parameter.location) {
            .path => "path_",
            .query => "query_",
            .header => "header_",
            .form => "form_",
            .body => unreachable,
        };
        const identifier = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, parameter.name });
        defer self.allocator.free(identifier);

        try zig_identifier.append(&self.buffer, self.allocator, identifier);
    }

    fn appendZigTypeFromSchema(self: *UnifiedApiGenerator, schema: Schema) !void {
        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                try zig_identifier.append(&self.buffer, self.allocator, ref[last_slash + 1 ..]);
                return;
            }
        }
        if (schema.type) |schema_type| {
            try self.appendZigTypeFromSchemaType(schema_type);
            return;
        }
        try self.buffer.appendSlice(self.allocator, "[]const u8");
    }

    fn appendZigTypeFromSchemaType(self: *UnifiedApiGenerator, schema_type: SchemaType) !void {
        switch (schema_type) {
            .string => try self.buffer.appendSlice(self.allocator, "[]const u8"),
            .integer => try self.buffer.appendSlice(self.allocator, "i64"),
            .number => try self.buffer.appendSlice(self.allocator, "f64"),
            .boolean => try self.buffer.appendSlice(self.allocator, "bool"),
            .array => try self.buffer.appendSlice(self.allocator, "[]const u8"), // Simplified for now
            .object => try self.buffer.appendSlice(self.allocator, "std.json.Value"),
            .reference => try self.buffer.appendSlice(self.allocator, "[]const u8"),
        }
    }
};
