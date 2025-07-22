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

    pub fn generate(self: *ApiCodeGenerator, document: models.SwaggerDocument) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        try parts.append("///////////////////////////////////////////\n");
        try parts.append("// Generated Zig API client from Swagger v2.0\n");
        try parts.append("///////////////////////////////////////////\n\n");
        try parts.append("const std = @import(\"std\");\n\n");

        var path_iterator = document.paths.path_items.iterator();
        while (path_iterator.next()) |entry| {
            const path_key = entry.key_ptr.*;
            const path_item = entry.value_ptr.*;

            // Build the full URL path
            var base_url: []const u8 = "";
            var allocated_base_url = false;
            if (self.args.base_url) |base| {
                base_url = base;
            } else if (document.host) |host| {
                // Construct base URL from Swagger host, basePath, and schemes
                const scheme = if (document.schemes != null and document.schemes.?.len > 0) document.schemes.?[0] else "https";
                const base_path = document.basePath orelse "";
                base_url = try std.fmt.allocPrint(self.allocator, "{s}://{s}{s}", .{ scheme, host, base_path });
                allocated_base_url = true;
            }
            defer if (allocated_base_url) self.allocator.free(base_url);

            const path = if (base_url.len > 0) try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base_url, path_key }) else path_key;
            defer if (base_url.len > 0) self.allocator.free(path);

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

            if (path_item.patch) |op| {
                try parts.append(try self.generateMethod(op, path, "PATCH"));
            }

            if (path_item.head) |op| {
                try parts.append(try self.generateMethod(op, path, "HEAD"));
            }

            if (path_item.options) |op| {
                try parts.append(try self.generateMethod(op, path, "OPTIONS"));
            }
        }

        return try std.mem.join(self.allocator, "", parts.items);
    }

    pub fn generateMethod(self: *ApiCodeGenerator, op: models.v2.Operation, path: []const u8, method: []const u8) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        try parts.append(try generateMethodDocs(self.allocator, op));
        try parts.append("pub fn ");
        try parts.append(op.operationId orelse path);
        try parts.append("(allocator: std.mem.Allocator");

        var parameters = std.ArrayList([]const u8).init(self.allocator);
        defer parameters.deinit();

        var has_body_param = false;

        if (op.parameters) |params| {
            if (params.len > 0) try parts.append(", ");
            var first = true;
            for (params) |param| {
                if (!first) try parts.append(", ");
                first = false;

                try parameters.append(param.name);
                try parts.append(param.name);
                try parts.append(": ");

                // Determine parameter type based on Swagger v2.0 parameter
                var data_type: []const u8 = "[]const u8"; // Default to string

                if (param.in == .body) {
                    has_body_param = true;
                    data_type = "[]const u8"; // For body parameters, assume JSON string
                } else if (param.type) |param_type| {
                    data_type = try converter.getDataType(@tagName(param_type));
                }

                try parts.append(data_type);
            }
        }

        try parts.append(") !void {\n");

        const method_body = try generateImplementation(self.allocator, path, method, parameters.items, has_body_param);
        try parts.append(method_body);

        try parts.append("}\n\n");

        return try std.mem.join(self.allocator, "", parts.items);
    }

    fn extractTypeFromReference(self: *ApiCodeGenerator, ref: []const u8) ?[]const u8 {
        _ = self;
        // Extract type name from $ref like "#/definitions/Pet" -> "Pet"
        const prefix = "#/definitions/";
        if (std.mem.startsWith(u8, ref, prefix)) {
            return ref[prefix.len..];
        }
        return null;
    }
};

fn generateMethodDocs(allocator: std.mem.Allocator, op: models.v2.Operation) ![]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    if (op.summary) |summary| {
        try parts.append("/// ");
        try parts.append(summary);
        try parts.append("\n");
    }

    if (op.description) |description| {
        try parts.append("/// ");
        try parts.append(description);
        try parts.append("\n");
    }

    return try std.mem.join(allocator, "", parts.items);
}

fn generateImplementation(allocator: std.mem.Allocator, path: []const u8, method: []const u8, parameters: [][]const u8, has_request_body: bool) ![]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    try parts.append("    var client = std.http.Client.init(allocator);\n");
    try parts.append("    defer client.deinit();\n\n");

    if (parameters.len > 0) {
        var new_path = path;
        for (parameters) |param| {
            // Replace path parameters (assuming they're in curly braces like {id})
            const param_placeholder = try std.fmt.allocPrint(allocator, "{{{s}}}", .{param});
            defer allocator.free(param_placeholder);

            const size = std.mem.replacementSize(u8, new_path, param_placeholder, "{s}");
            if (size != new_path.len) {
                const output = try allocator.alloc(u8, size);
                _ = std.mem.replace(u8, new_path, param_placeholder, "{s}", output);
                new_path = output;
            }
        }

        try parts.append("    const url = try std.fmt.allocPrint(allocator, \"");
        try parts.append(new_path);
        try parts.append("\"");

        // Add parameter formatting
        if (parameters.len > 0) {
            try parts.append(", .{");
            for (parameters, 0..) |param, i| {
                if (i > 0) try parts.append(", ");
                try parts.append(param);
            }
            try parts.append("}");
        }
        try parts.append(");\n");
        try parts.append("    defer allocator.free(url);\n\n");
    } else {
        try parts.append("    const url = \"");
        try parts.append(path);
        try parts.append("\";\n\n");
    }

    try parts.append("    var uri = try std.Uri.parse(url);\n");
    try parts.append("    var request = try client.request(std.http.Method.");
    try parts.append(method);
    try parts.append(", uri, .{}, .{});\n");
    try parts.append("    defer request.deinit();\n\n");

    if (has_request_body) {
        try parts.append("    request.headers.content_type = std.http.Header.ContentType{ .override = \"application/json\" };\n");
        try parts.append("    request.headers.content_length = requestBody.len;\n");
        try parts.append("    try request.send(.{});\n");
        try parts.append("    try request.writer().writeAll(requestBody);\n");
    } else {
        try parts.append("    try request.send(.{});\n");
    }

    try parts.append("    try request.finish();\n");
    try parts.append("    try request.wait();\n\n");
    try parts.append("    // Handle response\n");
    try parts.append("    // TODO: Process response based on status code and content\n");

    return try std.mem.join(allocator, "", parts.items);
}
