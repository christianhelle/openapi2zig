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

        var methods = std.ArrayList([]const u8).init(self.allocator);
        defer methods.deinit();

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
        for (methods.items) |method| {
            self.allocator.free(method);
        }
        return code;
    }

    pub fn generateMethod(self: *ApiCodeGenerator, op: models.v2.Operation, path: []const u8, method: []const u8) ![]const u8 {
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        const comments = try generateMethodDocs(self.allocator, op);
        defer self.allocator.free(comments);
        try parts.append(comments);

        try parts.append("pub fn ");
        try parts.append(op.operationId orelse path);
        try parts.append("(allocator: std.mem.Allocator");

        var path_parameters = std.ArrayList([]const u8).init(self.allocator);
        defer path_parameters.deinit();

        var has_body_param = false;

        if (op.parameters) |params| {
            if (params.len > 0) try parts.append(", ");
            var first = true;
            for (params) |param| {
                if (!first) try parts.append(", ");
                first = false;

                // Determine parameter type based on Swagger v2.0 parameter
                var data_type: []const u8 = "[]const u8"; // Default to string
                var name: []const u8 = param.name;

                if (param.in == .body) {
                    has_body_param = true;
                    name = "requestBody";
                    if (param.schema.?.ref) |ref| {
                        if (extractTypeFromReference(ref)) |type_name| {
                            data_type = type_name;
                        }
                    }
                } else if (param.in == .path) {
                    try path_parameters.append(name);
                }

                if (param.type) |param_type| {
                    data_type = try converter.getDataType(@tagName(param_type));
                }

                try parts.append(name);
                try parts.append(": ");
                try parts.append(data_type);
            }
        }

        try parts.append(") !void {\n");

        const method_body = try generateImplementation(self.allocator, path, method, op, has_body_param);
        defer self.allocator.free(method_body);

        try parts.append(method_body);
        try parts.append("}\n\n");

        return try std.mem.join(self.allocator, "", parts.items);
    }
};

fn extractTypeFromReference(ref: []const u8) ?[]const u8 {
    // Extract type name from $ref like "#/definitions/Pet" -> "Pet"
    const prefix = "#/definitions/";
    if (std.mem.startsWith(u8, ref, prefix)) {
        return ref[prefix.len..];
    }
    return null;
}

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

fn generateImplementation(allocator: std.mem.Allocator, path: []const u8, method: []const u8, op: models.v2.Operation, has_request_body: bool) ![]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    if (op.parameters) |parameters| {
        if (parameters.len > 0) {
            for (parameters) |parameter| {
                if (parameter.in != .path and parameter.in != .body) {
                    try parts.append("    _ = ");
                    try parts.append(parameter.name);
                    try parts.append(";\n");
                }
            }
            if (has_request_body) {
                try parts.append("\n");
            }
            try parts.append("\n");
        }
    }

    try parts.append("    var client = std.http.Client.init(allocator);\n");
    try parts.append("    defer client.deinit();\n\n");

    var allocations = std.ArrayList([]const u8).init(allocator);
    defer allocations.deinit();

    if (op.parameters) |parameters| {
        if (parameters.len > 0) {
            var new_path = path;
            for (parameters) |parameter| {
                if (parameter.in != .path) continue;
                const param = parameter.name;
                const size = std.mem.replacementSize(u8, new_path, param, "s");
                const output = try allocator.alloc(u8, size);
                _ = std.mem.replace(u8, new_path, param, "s", output);
                new_path = output;
                try allocations.append(output);
            }
            try parts.append("    const uri_str = try std.mem.allocPrint(\"");
            try parts.append(new_path);
            try parts.append("\", .{");
            var pos: i32 = 0;
            for (parameters) |parameter| {
                if (parameter.in != .path) continue;
                const param = parameter.name;
                try parts.append(param);
                pos += 1;
                if (pos < parameters.len)
                    try parts.append(", ");
            }
            try parts.append("});\n");
            try parts.append("    const uri = try std.Uri.parse(uri_str);\n");
        } else {
            try parts.append("    const uri = try std.Uri.parse(\"");
            try parts.append(path);
            try parts.append("\");\n");
        }
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

    // We assume that the request body is a JSON object
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
