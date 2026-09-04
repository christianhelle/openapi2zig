const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../../models/common/document.zig").Operation;
const ident = @import("../ident_utils.zig");
const helpers = @import("helpers.zig");
const OperationRef = helpers.OperationRef;
const TagClient = helpers.TagClient;
const operationRefLessThan = helpers.operationRefLessThan;
const tagClientLessThan = helpers.tagClientLessThan;
const toPascalCaseAlloc = helpers.toPascalCaseAlloc;
const operationDeclaresTopLevelName = @import("resource_wrappers.zig").operationDeclaresTopLevelName;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

pub fn generateTagClients(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
    var operations = std.ArrayList(OperationRef).empty;
    defer operations.deinit(self.allocator);

    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        const path = entry.key_ptr.*;
        const path_item = entry.value_ptr.*;
        if (path_item.get) |op| try operations.append(self.allocator, .{ .path = path, .method = "GET", .operation = op });
        if (path_item.post) |op| try operations.append(self.allocator, .{ .path = path, .method = "POST", .operation = op });
        if (path_item.put) |op| try operations.append(self.allocator, .{ .path = path, .method = "PUT", .operation = op });
        if (path_item.delete) |op| try operations.append(self.allocator, .{ .path = path, .method = "DELETE", .operation = op });
        if (path_item.patch) |op| try operations.append(self.allocator, .{ .path = path, .method = "PATCH", .operation = op });
        if (path_item.head) |op| try operations.append(self.allocator, .{ .path = path, .method = "HEAD", .operation = op });
        if (path_item.options) |op| try operations.append(self.allocator, .{ .path = path, .method = "OPTIONS", .operation = op });
    }
    std.mem.sort(OperationRef, operations.items, {}, operationRefLessThan);

    var groups = std.ArrayList(TagClient).empty;
    defer {
        for (groups.items) |*group| {
            self.allocator.free(group.name);
            group.methods.deinit(self.allocator);
        }
        groups.deinit(self.allocator);
    }

    for (operations.items) |op_ref| {
        const struct_name = try self.tagClientNameAlloc(op_ref.operation);

        var group_index: ?usize = null;
        for (groups.items, 0..) |group, i| {
            if (std.mem.eql(u8, group.name, struct_name)) {
                group_index = i;
                break;
            }
        }

        if (group_index) |idx| {
            self.allocator.free(struct_name);
            try groups.items[idx].methods.append(self.allocator, op_ref);
        } else {
            errdefer self.allocator.free(struct_name);
            var methods = std.ArrayList(OperationRef).empty;
            errdefer methods.deinit(self.allocator);
            try methods.append(self.allocator, op_ref);
            try groups.append(self.allocator, .{ .name = struct_name, .methods = methods });
        }
    }

    std.mem.sort(TagClient, groups.items, {}, tagClientLessThan);

    // Emit file-scope aliases for operations whose tag-client method name
    // matches the flat function it delegates to. Without the alias, the
    // unqualified call inside the method (e.g. `return listPets(self.client)`)
    // is an ambiguous reference between the struct method and the flat fn.
    var alias_count: usize = 0;
    for (operations.items) |op_ref| {
        const op_id = op_ref.operation.operationId orelse continue;
        const prospective = try self.tagClientMethodNameAlloc(op_id);
        defer self.allocator.free(prospective);
        if (!std.mem.eql(u8, prospective, op_id)) continue;

        // The alias target is the flat function name, which may be a Zig
        // keyword (e.g. operationId "if" → @"if") and so must be quoted.
        const main_alias = try std.fmt.allocPrint(self.allocator, "const _{s} = ", .{op_id});
        defer self.allocator.free(main_alias);
        try self.buffer.appendSlice(self.allocator, main_alias);
        try self.appendIdentifier(op_id);
        try self.buffer.appendSlice(self.allocator, ";\n");
        const raw_alias = try std.fmt.allocPrint(self.allocator, "const _{s}Raw = {s}Raw;\n", .{ op_id, op_id });
        defer self.allocator.free(raw_alias);
        try self.buffer.appendSlice(self.allocator, raw_alias);
        if (self.hasReturnValue(op_ref.method, op_ref.operation)) {
            const result_alias = try std.fmt.allocPrint(self.allocator, "const _{s}Result = {s}Result;\n", .{ op_id, op_id });
            defer self.allocator.free(result_alias);
            try self.buffer.appendSlice(self.allocator, result_alias);
        }
        if (op_ref.operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
            const stream_alias = try std.fmt.allocPrint(self.allocator, "const _{s}Streaming = {s}Streaming;\n", .{ op_id, op_id });
            defer self.allocator.free(stream_alias);
            try self.buffer.appendSlice(self.allocator, stream_alias);
        }
        alias_count += 1;
    }
    if (alias_count > 0) try self.buffer.appendSlice(self.allocator, "\n");

    var used_struct_names = std.StringHashMap(void).init(self.allocator);
    defer {
        var name_iterator = used_struct_names.keyIterator();
        while (name_iterator.next()) |key| self.allocator.free(key.*);
        used_struct_names.deinit();
    }

    for (groups.items) |group| {
        const struct_name = try self.uniqueTagClientStructNameAlloc(group.name, document, used_struct_names);
        used_struct_names.put(struct_name, {}) catch {
            self.allocator.free(struct_name);
            return error.OutOfMemory;
        };

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.buffer.appendSlice(self.allocator, " = struct {\n");
        try self.buffer.appendSlice(self.allocator, "    client: *Client,\n\n");
        try self.buffer.appendSlice(self.allocator, "    pub fn init(client: *Client) ");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.buffer.appendSlice(self.allocator, " {\n");
        try self.buffer.appendSlice(self.allocator, "        return .{ .client = client };\n");
        try self.buffer.appendSlice(self.allocator, "    }\n\n");

        var used_method_names = std.StringHashMap(void).init(self.allocator);
        defer {
            var method_iterator = used_method_names.keyIterator();
            while (method_iterator.next()) |key| self.allocator.free(key.*);
            used_method_names.deinit();
        }

        for (group.methods.items) |op_ref| {
            const method_name = try self.uniqueTagClientMethodNameAlloc(op_ref, used_method_names);
            try self.registerTagClientMethodNames(method_name, op_ref, &used_method_names);
            try self.generateTagClientMethod(struct_name, method_name, op_ref);
        }

        try self.buffer.appendSlice(self.allocator, "};\n\n");
    }
}

pub fn generateEndpointClients(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
    var operations = std.ArrayList(OperationRef).empty;
    defer operations.deinit(self.allocator);

    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        const path = entry.key_ptr.*;
        const path_item = entry.value_ptr.*;
        if (path_item.get) |op| try operations.append(self.allocator, .{ .path = path, .method = "GET", .operation = op });
        if (path_item.post) |op| try operations.append(self.allocator, .{ .path = path, .method = "POST", .operation = op });
        if (path_item.put) |op| try operations.append(self.allocator, .{ .path = path, .method = "PUT", .operation = op });
        if (path_item.delete) |op| try operations.append(self.allocator, .{ .path = path, .method = "DELETE", .operation = op });
        if (path_item.patch) |op| try operations.append(self.allocator, .{ .path = path, .method = "PATCH", .operation = op });
        if (path_item.head) |op| try operations.append(self.allocator, .{ .path = path, .method = "HEAD", .operation = op });
        if (path_item.options) |op| try operations.append(self.allocator, .{ .path = path, .method = "OPTIONS", .operation = op });
    }
    std.mem.sort(OperationRef, operations.items, {}, operationRefLessThan);

    var used_struct_names = std.StringHashMap(void).init(self.allocator);
    defer {
        var name_iterator = used_struct_names.keyIterator();
        while (name_iterator.next()) |key| self.allocator.free(key.*);
        used_struct_names.deinit();
    }

    for (operations.items) |op_ref| {
        const struct_name = try self.endpointClientNameAlloc(op_ref, document, used_struct_names);
        used_struct_names.put(struct_name, {}) catch {
            self.allocator.free(struct_name);
            return error.OutOfMemory;
        };
        try self.generateEndpointClient(struct_name, op_ref);
    }
}

pub fn endpointFallbackNameAlloc(self: *UnifiedApiGenerator, method: []const u8, path: []const u8) ![]const u8 {
    var combined = std.ArrayList(u8).empty;
    defer combined.deinit(self.allocator);
    for (method) |c| try combined.append(self.allocator, std.ascii.toLower(c));
    try combined.appendSlice(self.allocator, path);
    return toPascalCaseAlloc(self.allocator, combined.items);
}

pub fn endpointClientNameAlloc(self: *UnifiedApiGenerator, op_ref: OperationRef, document: UnifiedDocument, used_names: std.StringHashMap(void)) ![]const u8 {
    var candidate = if (op_ref.operation.operationId) |op_id|
        try toPascalCaseAlloc(self.allocator, op_id)
    else
        try self.endpointFallbackNameAlloc(op_ref.method, op_ref.path);
    errdefer self.allocator.free(candidate);
    while (self.topLevelNameConflicts(candidate, document) or used_names.contains(candidate)) {
        const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
        self.allocator.free(candidate);
        candidate = suffixed;
    }
    return candidate;
}

pub fn generateEndpointClient(self: *UnifiedApiGenerator, struct_name: []const u8, op_ref: OperationRef) !void {
    const method = op_ref.method;
    const operation = op_ref.operation;
    const has_return = self.hasReturnValue(method, operation);

    try self.buffer.appendSlice(self.allocator, "pub const ");
    try self.buffer.appendSlice(self.allocator, struct_name);
    try self.buffer.appendSlice(self.allocator, " = struct {\n");
    try self.buffer.appendSlice(self.allocator, "    client: *Client,\n\n");
    try self.buffer.appendSlice(self.allocator, "    pub fn init(client: *Client) ");
    try self.buffer.appendSlice(self.allocator, struct_name);
    try self.buffer.appendSlice(self.allocator, " {\n");
    try self.buffer.appendSlice(self.allocator, "        return .{ .client = client };\n");
    try self.buffer.appendSlice(self.allocator, "    }\n\n");

    try self.buffer.appendSlice(self.allocator, "    pub fn execute(self: *");
    try self.buffer.appendSlice(self.allocator, struct_name);
    try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
    if (has_return) {
        try self.buffer.appendSlice(self.allocator, ") !Owned(");
        try self.appendReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, ") {\n");
    } else {
        try self.buffer.appendSlice(self.allocator, ") !void {\n");
    }
    try self.buffer.appendSlice(self.allocator, "        return ");
    if (operation.operationId) |op_id| {
        try self.appendIdentifier(op_id);
    } else {
        try self.buffer.appendSlice(self.allocator, "@\"operation");
        try self.buffer.appendSlice(self.allocator, op_ref.path[1..]);
        try self.buffer.appendSlice(self.allocator, "\"");
    }
    try self.appendTagClientCallArguments(operation);
    try self.buffer.appendSlice(self.allocator, ";\n");
    try self.buffer.appendSlice(self.allocator, "    }\n\n");

    if (operation.operationId) |op_id| {
        const raw_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{op_id});
        defer self.allocator.free(raw_operation_name);

        try self.buffer.appendSlice(self.allocator, "    pub fn executeRaw(self: *");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
        try self.buffer.appendSlice(self.allocator, ") !RawResponse {\n");
        try self.buffer.appendSlice(self.allocator, "        return ");
        try self.appendIdentifier(raw_operation_name);
        try self.appendTagClientCallArguments(operation);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.buffer.appendSlice(self.allocator, "    }\n\n");

        if (has_return) {
            const result_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{op_id});
            defer self.allocator.free(result_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn executeResult(self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
            try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
            try self.appendReturnType(method, operation);
            try self.buffer.appendSlice(self.allocator, ") {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            try self.appendIdentifier(result_operation_name);
            try self.appendTagClientCallArguments(operation);
            try self.buffer.appendSlice(self.allocator, ";\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");
        }

        if (operation.streaming and std.mem.eql(u8, method, "POST")) {
            const stream_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{op_id});
            defer self.allocator.free(stream_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn executeStreaming(self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            try self.appendIdentifier(stream_operation_name);
            try self.buffer.appendSlice(self.allocator, "(self.client, requestBody, callback, cancellation_token);\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");

            const stream_events_operation_name = try std.fmt.allocPrint(self.allocator, "{s}StreamingEvents", .{op_id});
            defer self.allocator.free(stream_events_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn executeStreamingEvents(comptime Event: type, self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            try self.appendIdentifier(stream_events_operation_name);
            try self.buffer.appendSlice(self.allocator, "(Event, self.client, requestBody, callback, cancellation_token);\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");
        }
    }

    try self.buffer.appendSlice(self.allocator, "};\n\n");
}

pub fn topLevelNameConflicts(self: *UnifiedApiGenerator, name: []const u8, document: UnifiedDocument) bool {
    const runtime_names = [_][]const u8{
        "Client",        "Owned",                     "RawResponse",        "ParseErrorResponse",  "ApiResult",        "HttpObserver",  "CancellationToken",
        "requestRaw",    "requestRawWithContentType", "getRaw",             "postJsonRaw",         "parseRawResponse", "getJsonResult", "postJsonResult",
        "parseSseBytes", "parseSseReader",            "parseSseBytesTyped", "parseSseReaderTyped",
    };
    for (runtime_names) |runtime_name| {
        if (std.mem.eql(u8, name, runtime_name)) return true;
    }

    var options_iterator = self.options_type_names.valueIterator();
    while (options_iterator.next()) |options_name| {
        if (std.mem.eql(u8, options_name.*, name)) return true;
    }

    if (document.schemas) |schemas| {
        var schema_iterator = schemas.iterator();
        while (schema_iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) return true;
        }
    }

    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        const path_item = entry.value_ptr.*;
        if (operationDeclaresTopLevelName(self, path_item.get, "GET", name)) return true;
        if (operationDeclaresTopLevelName(self, path_item.post, "POST", name)) return true;
        if (operationDeclaresTopLevelName(self, path_item.put, "PUT", name)) return true;
        if (operationDeclaresTopLevelName(self, path_item.delete, "DELETE", name)) return true;
        if (operationDeclaresTopLevelName(self, path_item.patch, "PATCH", name)) return true;
        if (operationDeclaresTopLevelName(self, path_item.head, "HEAD", name)) return true;
        if (operationDeclaresTopLevelName(self, path_item.options, "OPTIONS", name)) return true;
    }
    return false;
}

pub fn uniqueTagClientStructNameAlloc(self: *UnifiedApiGenerator, name: []const u8, document: UnifiedDocument, used_names: std.StringHashMap(void)) ![]const u8 {
    var candidate = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(candidate);
    while (self.topLevelNameConflicts(candidate, document) or used_names.contains(candidate)) {
        const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
        self.allocator.free(candidate);
        candidate = suffixed;
    }
    return candidate;
}

pub fn isReservedTagClientMethod(name: []const u8) bool {
    return ident.isReservedIdent(name) or
        std.mem.eql(u8, name, "init") or
        std.mem.eql(u8, name, "client") or
        std.mem.eql(u8, name, "deinit");
}

pub fn uniqueTagClientMethodNameAlloc(self: *UnifiedApiGenerator, op_ref: OperationRef, used_names: std.StringHashMap(void)) ![]const u8 {
    var candidate = if (op_ref.operation.operationId) |op_id|
        try self.tagClientMethodNameAlloc(op_id)
    else
        try self.tagClientFallbackMethodNameAlloc(op_ref);
    errdefer self.allocator.free(candidate);
    while (try self.tagClientMethodNamesCollide(candidate, op_ref, used_names)) {
        const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
        self.allocator.free(candidate);
        candidate = suffixed;
    }
    return candidate;
}

// True when any struct member name the tag-client method for op_ref emits
// (the main name plus its Raw/Result/Streaming variants) collides with a
// name already claimed by a sibling method or a reserved identifier.

pub fn tagClientMethodNamesCollide(self: *UnifiedApiGenerator, candidate: []const u8, op_ref: OperationRef, used_names: std.StringHashMap(void)) !bool {
    if (isReservedTagClientMethod(candidate) or used_names.contains(candidate)) return true;
    if (op_ref.operation.operationId == null) return false;

    const raw = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{candidate});
    defer self.allocator.free(raw);
    if (used_names.contains(raw)) return true;

    if (self.hasReturnValue(op_ref.method, op_ref.operation)) {
        const result = try std.fmt.allocPrint(self.allocator, "{s}Result", .{candidate});
        defer self.allocator.free(result);
        if (used_names.contains(result)) return true;
    }
    if (op_ref.operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
        const streaming = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{candidate});
        defer self.allocator.free(streaming);
        if (used_names.contains(streaming)) return true;
        const stream_events = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{candidate});
        defer self.allocator.free(stream_events);
        if (used_names.contains(stream_events)) return true;
    }
    return false;
}

// Registers every struct member name the tag-client method for op_ref will
// emit, transferring ownership of each to used_names.

pub fn registerTagClientMethodNames(self: *UnifiedApiGenerator, method_name: []const u8, op_ref: OperationRef, used_names: *std.StringHashMap(void)) !void {
    try self.registerTagClientMethodName(method_name, used_names);
    if (op_ref.operation.operationId == null) return;

    try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}Raw", .{method_name}), used_names);
    if (self.hasReturnValue(op_ref.method, op_ref.operation)) {
        try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}Result", .{method_name}), used_names);
    }
    if (op_ref.operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
        try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{method_name}), used_names);
        try self.registerTagClientMethodName(try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{method_name}), used_names);
    }
}

pub fn registerTagClientMethodName(self: *UnifiedApiGenerator, name: []const u8, used_names: *std.StringHashMap(void)) !void {
    used_names.put(name, {}) catch {
        self.allocator.free(name);
        return error.OutOfMemory;
    };
}

pub fn tagClientFallbackMethodNameAlloc(self: *UnifiedApiGenerator, op_ref: OperationRef) ![]const u8 {
    const pascal = try self.endpointFallbackNameAlloc(op_ref.method, op_ref.path);
    defer self.allocator.free(pascal);
    const method = try self.allocator.dupe(u8, pascal);
    if (method.len > 0) method[0] = std.ascii.toLower(method[0]);
    return method;
}

pub fn tagClientNameAlloc(self: *UnifiedApiGenerator, operation: Operation) ![]const u8 {
    const tag: []const u8 = if (operation.tags) |tags| (if (tags.len > 0) tags[0] else "") else "";
    if (tag.len == 0) return try self.allocator.dupe(u8, "DefaultClient");
    const pascal = try toPascalCaseAlloc(self.allocator, tag);
    defer self.allocator.free(pascal);
    return try std.fmt.allocPrint(self.allocator, "{s}Client", .{pascal});
}

pub fn tagClientMethodNameAlloc(self: *UnifiedApiGenerator, operation_id: []const u8) ![]const u8 {
    const pascal = try toPascalCaseAlloc(self.allocator, operation_id);
    defer self.allocator.free(pascal);
    const method = try self.allocator.dupe(u8, pascal);
    if (method.len > 0) method[0] = std.ascii.toLower(method[0]);
    return method;
}

pub fn generateTagClientMethod(self: *UnifiedApiGenerator, struct_name: []const u8, method_name: []const u8, op_ref: OperationRef) !void {
    const operation = op_ref.operation;
    const op_id = operation.operationId;
    const has_return = self.hasReturnValue(op_ref.method, operation);

    // When the method name matches the operation id, the unqualified
    // delegation call inside the method would be an ambiguous reference to
    // the file-scope flat function. Route through the `_` aliases emitted
    // by generateTagClients instead. Operations without an operationId
    // delegate to the raw @"operation{path}" flat fallback, which never
    // matches the derived method name, so no alias is needed.
    const needs_alias = if (op_id) |id| blk: {
        const prospective_name = try self.tagClientMethodNameAlloc(id);
        defer self.allocator.free(prospective_name);
        break :blk std.mem.eql(u8, prospective_name, id);
    } else false;

    try self.buffer.appendSlice(self.allocator, "    pub fn ");
    try self.buffer.appendSlice(self.allocator, method_name);
    try self.buffer.appendSlice(self.allocator, "(self: *");
    try self.buffer.appendSlice(self.allocator, struct_name);
    try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
    if (has_return) {
        try self.buffer.appendSlice(self.allocator, ") !Owned(");
        try self.appendReturnType(op_ref.method, operation);
        try self.buffer.appendSlice(self.allocator, ") {\n");
    } else {
        try self.buffer.appendSlice(self.allocator, ") !void {\n");
    }
    try self.buffer.appendSlice(self.allocator, "        return ");
    if (op_id) |id| {
        if (needs_alias) {
            // The alias name is the literal `_` + operationId, which stays a
            // valid bare identifier even when the operationId is a Zig keyword.
            try self.buffer.appendSlice(self.allocator, "_");
            try self.buffer.appendSlice(self.allocator, id);
        } else {
            try self.appendIdentifier(id);
        }
    } else {
        try self.buffer.appendSlice(self.allocator, "@\"operation");
        try self.buffer.appendSlice(self.allocator, op_ref.path[1..]);
        try self.buffer.appendSlice(self.allocator, "\"");
    }
    try self.appendTagClientCallArguments(operation);
    try self.buffer.appendSlice(self.allocator, ";\n");
    try self.buffer.appendSlice(self.allocator, "    }\n\n");

    if (op_id) |id| {
        const raw_method_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{method_name});
        defer self.allocator.free(raw_method_name);
        const raw_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Raw", .{id});
        defer self.allocator.free(raw_operation_name);

        try self.buffer.appendSlice(self.allocator, "    pub fn ");
        try self.buffer.appendSlice(self.allocator, raw_method_name);
        try self.buffer.appendSlice(self.allocator, "(self: *");
        try self.buffer.appendSlice(self.allocator, struct_name);
        try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
        try self.buffer.appendSlice(self.allocator, ") !RawResponse {\n");
        try self.buffer.appendSlice(self.allocator, "        return ");
        if (needs_alias) try self.buffer.appendSlice(self.allocator, "_");
        try self.appendIdentifier(raw_operation_name);
        try self.appendTagClientCallArguments(operation);
        try self.buffer.appendSlice(self.allocator, ";\n");
        try self.buffer.appendSlice(self.allocator, "    }\n\n");

        if (has_return) {
            const result_method_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{method_name});
            defer self.allocator.free(result_method_name);
            const result_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{id});
            defer self.allocator.free(result_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn ");
            try self.buffer.appendSlice(self.allocator, result_method_name);
            try self.buffer.appendSlice(self.allocator, "(self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.appendFlatOperationParameters(operation, op_ref.method, op_ref.path);
            try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
            try self.appendReturnType(op_ref.method, operation);
            try self.buffer.appendSlice(self.allocator, ") {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            if (needs_alias) try self.buffer.appendSlice(self.allocator, "_");
            try self.appendIdentifier(result_operation_name);
            try self.appendTagClientCallArguments(operation);
            try self.buffer.appendSlice(self.allocator, ";\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");
        }

        if (operation.streaming and std.mem.eql(u8, op_ref.method, "POST")) {
            const stream_method_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{method_name});
            defer self.allocator.free(stream_method_name);
            const stream_operation_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{id});
            defer self.allocator.free(stream_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn ");
            try self.buffer.appendSlice(self.allocator, stream_method_name);
            try self.buffer.appendSlice(self.allocator, "(self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            if (needs_alias) try self.buffer.appendSlice(self.allocator, "_");
            try self.appendIdentifier(stream_operation_name);
            try self.buffer.appendSlice(self.allocator, "(self.client, requestBody, callback, cancellation_token);\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");

            const stream_events_method_name = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{method_name});
            defer self.allocator.free(stream_events_method_name);
            const stream_events_operation_name = try std.fmt.allocPrint(self.allocator, "{s}StreamingEvents", .{id});
            defer self.allocator.free(stream_events_operation_name);

            try self.buffer.appendSlice(self.allocator, "    pub fn ");
            try self.buffer.appendSlice(self.allocator, stream_events_method_name);
            try self.buffer.appendSlice(self.allocator, "(comptime Event: type, self: *");
            try self.buffer.appendSlice(self.allocator, struct_name);
            try self.buffer.appendSlice(self.allocator, ", requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
            try self.buffer.appendSlice(self.allocator, "        return ");
            try self.appendIdentifier(stream_events_operation_name);
            try self.buffer.appendSlice(self.allocator, "(Event, self.client, requestBody, callback, cancellation_token);\n");
            try self.buffer.appendSlice(self.allocator, "    }\n\n");
        }
    }
}

pub fn appendTagClientCallArguments(self: *UnifiedApiGenerator, operation: Operation) !void {
    try self.buffer.appendSlice(self.allocator, "(self.client");
    if (operation.parameters) |params| {
        if (self.args.parameters_as_struct) {
            for (params) |param| {
                if (param.location == .body) continue;
                try self.buffer.appendSlice(self.allocator, ", options");
                break;
            }
        }
        for (params) |param| {
            if (self.args.parameters_as_struct and param.location != .body) continue;
            try self.buffer.appendSlice(self.allocator, ", ");
            const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
            try self.appendFlatParamIdentifier(name);
        }
    }
    try self.buffer.appendSlice(self.allocator, ")");
}
