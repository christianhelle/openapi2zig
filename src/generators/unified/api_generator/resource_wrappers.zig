const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../../models/common/document.zig").Operation;
const ident = @import("../ident_utils.zig");
const helpers = @import("helpers.zig");
const OperationRef = helpers.OperationRef;
const ResourceWrapper = helpers.ResourceWrapper;
const operationRefLessThan = helpers.operationRefLessThan;
const resourceWrapperLessThan = helpers.resourceWrapperLessThan;
const stringLessThan = helpers.stringLessThan;
const sameStringList = helpers.sameStringList;
const containsString = helpers.containsString;
const isVersionSegment = helpers.isVersionSegment;
const isPathParam = helpers.isPathParam;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

pub fn generateResourceWrappers(self: *UnifiedApiGenerator, document: UnifiedDocument) !void {
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

    var wrappers = std.ArrayList(ResourceWrapper).empty;
    defer {
        for (wrappers.items) |wrapper| {
            for (wrapper.segments) |segment| self.allocator.free(segment);
            self.allocator.free(wrapper.segments);
            self.allocator.free(wrapper.method_name);
        }
        wrappers.deinit(self.allocator);
    }

    for (operations.items) |op_ref| {
        const operation_id = op_ref.operation.operationId orelse continue;
        const segments = try self.resourceSegments(op_ref.path, op_ref.operation);
        if (segments.len == 0) {
            self.allocator.free(segments);
            continue;
        }
        errdefer {
            for (segments) |segment| self.allocator.free(segment);
            self.allocator.free(segments);
        }

        try wrappers.append(self.allocator, .{
            .segments = segments,
            .method_name = try self.resourceMethodName(operation_id, op_ref.method),
            .operation_id = operation_id,
            .method = op_ref.method,
            .path = op_ref.path,
            .operation = op_ref.operation,
        });
    }

    for (wrappers.items, 0..) |*left, i| {
        for (wrappers.items[i + 1 ..]) |*right| {
            if (sameStringList(left.segments, right.segments) and std.mem.eql(u8, left.method_name, right.method_name)) {
                left.collides = true;
                right.collides = true;
            }
        }
    }

    std.mem.sort(ResourceWrapper, wrappers.items, {}, resourceWrapperLessThan);

    // Detect when wrapper method name matches its containing struct name
    // or when the derived method name equals the operation id (ambiguous reference)
    for (wrappers.items) |*wrapper| {
        const last_segment = wrapper.segments[wrapper.segments.len - 1];
        if (std.mem.eql(u8, wrapper.method_name, last_segment) or std.mem.eql(u8, wrapper.method_name, wrapper.operation_id)) {
            wrapper.collides = true;
            wrapper.needs_alias = true;
        }
    }

    // Generate aliases for operations whose wrapper needs them
    for (wrappers.items) |wrapper| {
        if (wrapper.needs_alias) {
            const alias_line = try std.fmt.allocPrint(self.allocator, "const _{s} = {s};\n", .{ wrapper.operation_id, wrapper.operation_id });
            defer self.allocator.free(alias_line);
            try self.buffer.appendSlice(self.allocator, alias_line);
            if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                const result_line = try std.fmt.allocPrint(self.allocator, "const _{s}Result = {s}Result;\n", .{ wrapper.operation_id, wrapper.operation_id });
                defer self.allocator.free(result_line);
                try self.buffer.appendSlice(self.allocator, result_line);
            }
        }
    }
    if (wrappers.items.len > 0) try self.buffer.appendSlice(self.allocator, "\n");

    if (wrappers.items.len == 0) {
        try self.buffer.appendSlice(self.allocator, "pub const resources = struct {};\n\n");
        return;
    }

    try self.buffer.appendSlice(self.allocator, "pub const resources = struct {\n");
    try self.generateResourceLevel(wrappers.items, 0, 1, &.{});
    try self.buffer.appendSlice(self.allocator, "};\n\n");

    var top_segments = std.ArrayList([]const u8).empty;
    defer top_segments.deinit(self.allocator);
    for (wrappers.items) |wrapper| {
        const top = wrapper.segments[0];
        if (!containsString(top_segments.items, top)) try top_segments.append(self.allocator, top);
    }
    std.mem.sort([]const u8, top_segments.items, {}, stringLessThan);
    for (top_segments.items) |top| {
        if (self.resourceAliasConflicts(top, document)) continue;
        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.buffer.appendSlice(self.allocator, top);
        try self.buffer.appendSlice(self.allocator, " = resources.");
        try self.buffer.appendSlice(self.allocator, top);
        try self.buffer.appendSlice(self.allocator, ";\n");
    }
    if (top_segments.items.len > 0) try self.buffer.appendSlice(self.allocator, "\n");
}

pub fn generateResourceLevel(self: *UnifiedApiGenerator, wrappers: []ResourceWrapper, depth: usize, indent: usize, ancestor_names: []const []const u8) !void {
    var children = std.ArrayList([]const u8).empty;
    defer children.deinit(self.allocator);
    for (wrappers) |wrapper| {
        if (wrapper.segments.len > depth and !containsString(children.items, wrapper.segments[depth])) {
            try children.append(self.allocator, wrapper.segments[depth]);
        }
    }
    std.mem.sort([]const u8, children.items, {}, stringLessThan);

    var declarations = std.ArrayList([]const u8).empty;
    defer declarations.deinit(self.allocator);
    try declarations.appendSlice(self.allocator, ancestor_names);
    var allocated_declarations = std.ArrayList([]const u8).empty;
    defer {
        for (allocated_declarations.items) |name| self.allocator.free(name);
        allocated_declarations.deinit(self.allocator);
    }

    for (children.items) |child| try declarations.append(self.allocator, child);

    // Detect wrapper method name collision with ancestor/child struct names
    for (wrappers) |*wrapper_at_depth| {
        if (wrapper_at_depth.segments.len == depth and containsString(declarations.items, wrapper_at_depth.method_name)) {
            wrapper_at_depth.collides = true;
        }
    }

    for (wrappers) |wrapper| {
        if (wrapper.segments.len == depth) {
            const name = try self.resourceWrapperNameAlloc(wrapper);
            try allocated_declarations.append(self.allocator, name);
            try declarations.append(self.allocator, name);
            if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{name});
                try allocated_declarations.append(self.allocator, result_name);
                try declarations.append(self.allocator, result_name);
            }
            if (wrapper.operation.streaming and std.mem.eql(u8, wrapper.method, "POST")) {
                const stream_decl_name = try std.fmt.allocPrint(self.allocator, "{s}Stream", .{wrapper.operation_id});
                try declarations.append(self.allocator, stream_decl_name);
                try allocated_declarations.append(self.allocator, stream_decl_name);
                const events_decl_name = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{wrapper.operation_id});
                try declarations.append(self.allocator, events_decl_name);
                try allocated_declarations.append(self.allocator, events_decl_name);
            }
        }
    }

    for (wrappers) |wrapper| {
        if (wrapper.segments.len == depth) {
            try self.generateResourceMethod(wrapper, declarations.items, indent);
            if (self.hasReturnValue(wrapper.method, wrapper.operation)) {
                try self.generateResourceResultMethod(wrapper, declarations.items, indent);
            }
            if (wrapper.operation.streaming and std.mem.eql(u8, wrapper.method, "POST")) {
                const stream_name = try std.fmt.allocPrint(self.allocator, "{s}Streaming", .{wrapper.operation_id});
                defer self.allocator.free(stream_name);
                try self.generateResourceStreamMethods(wrapper, stream_name, indent);
            }
        }
    }

    for (children.items) |child| {
        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.buffer.appendSlice(self.allocator, child);
        try self.buffer.appendSlice(self.allocator, " = struct {\n");

        var child_wrappers = std.ArrayList(ResourceWrapper).empty;
        defer child_wrappers.deinit(self.allocator);
        for (wrappers) |wrapper| {
            if (wrapper.segments.len > depth and std.mem.eql(u8, wrapper.segments[depth], child)) {
                try child_wrappers.append(self.allocator, wrapper);
            }
        }
        try self.generateResourceLevel(child_wrappers.items, depth + 1, indent + 1, declarations.items);

        try self.appendIndent(indent);
        try self.buffer.appendSlice(self.allocator, "};\n");
    }
}

pub fn generateResourceMethod(self: *UnifiedApiGenerator, wrapper: ResourceWrapper, forbidden_names: []const []const u8, indent: usize) !void {
    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "pub fn ");
    const wrapper_name = try self.resourceWrapperNameAlloc(wrapper);
    defer self.allocator.free(wrapper_name);
    try self.buffer.appendSlice(self.allocator, wrapper_name);
    try self.appendWrapperSignatureAndReturn(wrapper.method, wrapper.operation, forbidden_names, wrapper.path);
    try self.buffer.appendSlice(self.allocator, " {\n");
    try self.appendIndent(indent + 1);
    try self.buffer.appendSlice(self.allocator, "return ");
    if (wrapper.needs_alias) try self.buffer.appendSlice(self.allocator, "_");
    try self.appendIdentifier(wrapper.operation_id);
    try self.appendWrapperCallArguments(wrapper.operation, forbidden_names);
    try self.buffer.appendSlice(self.allocator, ";\n");
    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "}\n");
}

pub fn generateResourceResultMethod(self: *UnifiedApiGenerator, wrapper: ResourceWrapper, forbidden_names: []const []const u8, indent: usize) !void {
    const wrapper_name = try self.resourceWrapperNameAlloc(wrapper);
    defer self.allocator.free(wrapper_name);
    const result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{wrapper_name});
    defer self.allocator.free(result_name);
    const operation_result_name = try std.fmt.allocPrint(self.allocator, "{s}Result", .{wrapper.operation_id});
    defer self.allocator.free(operation_result_name);

    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.buffer.appendSlice(self.allocator, result_name);
    try self.appendWrapperResultSignature(wrapper.method, wrapper.operation, forbidden_names, wrapper.path);
    try self.buffer.appendSlice(self.allocator, " {\n");
    try self.appendIndent(indent + 1);
    try self.buffer.appendSlice(self.allocator, "return ");
    if (wrapper.needs_alias) try self.buffer.appendSlice(self.allocator, "_");
    try self.appendIdentifier(operation_result_name);
    try self.appendWrapperCallArguments(wrapper.operation, forbidden_names);
    try self.buffer.appendSlice(self.allocator, ";\n");
    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "}\n");
}

pub fn appendWrapperResultSignature(self: *UnifiedApiGenerator, method: []const u8, operation: Operation, forbidden_names: []const []const u8, path: []const u8) !void {
    try self.buffer.appendSlice(self.allocator, "(client: *Client");
    try self.appendOperationParameters(operation, forbidden_names, method, path);
    try self.buffer.appendSlice(self.allocator, ") !ApiResult(");
    try self.appendReturnType(method, operation);
    try self.buffer.appendSlice(self.allocator, ")");
}

pub fn resourceWrapperNameAlloc(self: *UnifiedApiGenerator, wrapper: ResourceWrapper) ![]const u8 {
    if (!wrapper.collides) return try self.allocator.dupe(u8, wrapper.method_name);
    const collision_name = try self.sanitizeIdentifierAlloc(wrapper.operation_id);
    defer self.allocator.free(collision_name);
    return try std.fmt.allocPrint(self.allocator, "{s}_", .{collision_name});
}

pub fn generateResourceStreamMethods(self: *UnifiedApiGenerator, wrapper: ResourceWrapper, stream_name: []const u8, indent: usize) !void {
    const stream_method_name = try std.fmt.allocPrint(self.allocator, "{s}Stream", .{wrapper.operation_id});
    defer self.allocator.free(stream_method_name);
    const events_method_name = try std.fmt.allocPrint(self.allocator, "{s}StreamEvents", .{wrapper.operation_id});
    defer self.allocator.free(events_method_name);

    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.buffer.appendSlice(self.allocator, stream_method_name);
    try self.buffer.appendSlice(self.allocator, "(client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
    try self.appendIndent(indent + 1);
    try self.buffer.appendSlice(self.allocator, "return ");
    try self.buffer.appendSlice(self.allocator, stream_name);
    try self.buffer.appendSlice(self.allocator, "(client, requestBody, callback, cancellation_token);\n");
    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "}\n");

    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "pub fn ");
    try self.buffer.appendSlice(self.allocator, events_method_name);
    try self.buffer.appendSlice(self.allocator, "(comptime Event: type, client: *Client, requestBody: anytype, callback: anytype, cancellation_token: ?*CancellationToken) !void {\n");
    try self.appendIndent(indent + 1);
    try self.buffer.appendSlice(self.allocator, "return ");
    try self.buffer.appendSlice(self.allocator, stream_name);
    try self.buffer.appendSlice(self.allocator, "Events(Event, client, requestBody, callback, cancellation_token);\n");
    try self.appendIndent(indent);
    try self.buffer.appendSlice(self.allocator, "}\n");
}

pub fn appendWrapperSignatureAndReturn(self: *UnifiedApiGenerator, method: []const u8, operation: Operation, forbidden_names: []const []const u8, path: []const u8) !void {
    try self.buffer.appendSlice(self.allocator, "(client: *Client");
    try self.appendOperationParameters(operation, forbidden_names, method, path);
    if (self.hasReturnValue(method, operation)) {
        try self.buffer.appendSlice(self.allocator, ") !Owned(");
        try self.appendReturnType(method, operation);
        try self.buffer.appendSlice(self.allocator, ")");
    } else {
        try self.buffer.appendSlice(self.allocator, ") !void");
    }
}

pub fn appendOperationParameters(self: *UnifiedApiGenerator, operation: Operation, forbidden_names: []const []const u8, method: []const u8, path: []const u8) !void {
    if (operation.parameters) |params| {
        if (self.args.parameters_as_struct) {
            try self.appendOptionsParam(operation, method, path);
            try self.appendBodyParams(params);
            return;
        }
        for (params) |param| {
            try self.buffer.appendSlice(self.allocator, ", ");
            const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
            try self.appendParameterName(name, forbidden_names);
            try self.buffer.appendSlice(self.allocator, ": ");
            if ((param.location == .query or param.location == .header) and !param.required) {
                try self.buffer.appendSlice(self.allocator, "?");
            }
            try self.appendParamBaseType(param);
        }
    }
}

pub fn appendWrapperCallArguments(self: *UnifiedApiGenerator, operation: Operation, forbidden_names: []const []const u8) !void {
    try self.buffer.appendSlice(self.allocator, "(client");
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
            try self.appendParameterName(name, forbidden_names);
        }
    }
    try self.buffer.appendSlice(self.allocator, ")");
}

pub fn appendParameterName(self: *UnifiedApiGenerator, name: []const u8, forbidden_names: []const []const u8) !void {
    if (containsString(forbidden_names, name)) {
        const safe_name = try self.sanitizeIdentifierAlloc(name);
        defer self.allocator.free(safe_name);
        try self.buffer.appendSlice(self.allocator, safe_name);
        try self.buffer.appendSlice(self.allocator, "_param");
    } else {
        try self.appendIdentifier(name);
    }
}

pub fn resourceAliasConflicts(self: *UnifiedApiGenerator, alias: []const u8, document: UnifiedDocument) bool {
    const reserved_aliases = [_][]const u8{ "organization", "project", "value" };
    for (reserved_aliases) |reserved_alias| {
        if (std.mem.eql(u8, alias, reserved_alias)) return true;
    }

    // With models inlined into the same file (no model prefix), a schema declares
    // a top-level type of its own name, which the alias would redeclare.
    if (self.model_prefix.len == 0) {
        if (document.schemas) |schemas| {
            if (schemas.contains(alias)) return true;
        }
    }

    var path_iterator = document.paths.iterator();
    while (path_iterator.next()) |entry| {
        const path_item = entry.value_ptr.*;
        if (operationHasParameterNamed(self, path_item.get, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.get, "GET", alias)) return true;
        if (operationHasParameterNamed(self, path_item.post, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.post, "POST", alias)) return true;
        if (operationHasParameterNamed(self, path_item.put, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.put, "PUT", alias)) return true;
        if (operationHasParameterNamed(self, path_item.delete, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.delete, "DELETE", alias)) return true;
        if (operationHasParameterNamed(self, path_item.patch, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.patch, "PATCH", alias)) return true;
        if (operationHasParameterNamed(self, path_item.head, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.head, "HEAD", alias)) return true;
        if (operationHasParameterNamed(self, path_item.options, alias)) return true;
        if (operationDeclaresTopLevelName(self, path_item.options, "OPTIONS", alias)) return true;
    }
    return false;
}

pub fn operationHasParameterNamed(self: *UnifiedApiGenerator, maybe_operation: ?Operation, name: []const u8) bool {
    const operation = maybe_operation orelse return false;
    if (operation.parameters) |params| {
        for (params) |param| {
            const param_name: []const u8 = if (param.location == .body) "requestBody" else param.name;
            const sanitized = self.sanitizeIdentifierAlloc(param_name) catch return true;
            defer self.allocator.free(sanitized);
            if (std.mem.eql(u8, sanitized, name)) return true;
        }
    }
    return false;
}

pub fn operationDeclaresTopLevelName(self: *UnifiedApiGenerator, maybe_operation: ?Operation, method: []const u8, name: []const u8) bool {
    const operation = maybe_operation orelse return false;
    const operation_id = operation.operationId orelse return false;
    if (std.mem.eql(u8, operation_id, name)) return true;

    const raw_name = std.fmt.allocPrint(self.allocator, "{s}Raw", .{operation_id}) catch return true;
    defer self.allocator.free(raw_name);
    if (std.mem.eql(u8, raw_name, name)) return true;

    if (self.hasReturnValue(method, operation)) {
        const result_name = std.fmt.allocPrint(self.allocator, "{s}Result", .{operation_id}) catch return true;
        defer self.allocator.free(result_name);
        if (std.mem.eql(u8, result_name, name)) return true;
    }

    if (operation.streaming and std.mem.eql(u8, method, "POST")) {
        const stream_name = std.fmt.allocPrint(self.allocator, "{s}Streaming", .{operation_id}) catch return true;
        defer self.allocator.free(stream_name);
        if (std.mem.eql(u8, stream_name, name)) return true;

        const events_name = std.fmt.allocPrint(self.allocator, "{s}Events", .{stream_name}) catch return true;
        defer self.allocator.free(events_name);
        if (std.mem.eql(u8, events_name, name)) return true;
    }

    return false;
}

pub fn resourceSegments(self: *UnifiedApiGenerator, path: []const u8, operation: Operation) ![][]const u8 {
    return switch (self.args.resource_wrappers) {
        .none => self.allocator.alloc([]const u8, 0),
        .paths => self.resourceSegmentsFromPath(path),
        .tags => if (operation.tags) |tags| blk: {
            if (tags.len > 0) {
                const segments = try self.allocator.alloc([]const u8, 1);
                segments[0] = try self.sanitizeIdentifierAlloc(tags[0]);
                break :blk segments;
            }
            break :blk try self.resourceSegmentsFromPath(path);
        } else self.resourceSegmentsFromPath(path),
        .hybrid => self.resourceSegmentsHybrid(path, operation),
    };
}

pub fn resourceSegmentsHybrid(self: *UnifiedApiGenerator, path: []const u8, operation: Operation) ![][]const u8 {
    const path_segments = try self.resourceSegmentsFromPath(path);
    errdefer {
        for (path_segments) |segment| self.allocator.free(segment);
        self.allocator.free(path_segments);
    }

    if (operation.tags == null or operation.tags.?.len == 0) return path_segments;
    const tag = try self.sanitizeIdentifierAlloc(operation.tags.?[0]);
    errdefer self.allocator.free(tag);
    if (path_segments.len > 0 and std.mem.eql(u8, path_segments[0], tag)) {
        self.allocator.free(tag);
        return path_segments;
    }

    const segments = try self.allocator.alloc([]const u8, path_segments.len + 1);
    segments[0] = tag;
    for (path_segments, 0..) |segment, i| segments[i + 1] = segment;
    self.allocator.free(path_segments);
    return segments;
}

pub fn resourceSegmentsFromPath(self: *UnifiedApiGenerator, path: []const u8) ![][]const u8 {
    var segments = std.ArrayList([]const u8).empty;
    errdefer {
        for (segments.items) |segment| self.allocator.free(segment);
        segments.deinit(self.allocator);
    }

    var iterator = std.mem.splitScalar(u8, path, '/');
    while (iterator.next()) |raw_segment| {
        if (raw_segment.len == 0 or isVersionSegment(raw_segment) or isPathParam(raw_segment)) continue;
        try segments.append(self.allocator, try self.sanitizeIdentifierAlloc(raw_segment));
    }
    return try segments.toOwnedSlice(self.allocator);
}

pub fn resourceMethodName(self: *UnifiedApiGenerator, operation_id: []const u8, method: []const u8) ![]const u8 {
    _ = method;
    const verbs = [_]struct { prefix: []const u8, name: []const u8 }{
        .{ .prefix = "create", .name = "create" },
        .{ .prefix = "list", .name = "list" },
        .{ .prefix = "retrieve", .name = "retrieve" },
        .{ .prefix = "get", .name = "get" },
        .{ .prefix = "delete", .name = "delete" },
        .{ .prefix = "update", .name = "update" },
        .{ .prefix = "modify", .name = "update" },
        .{ .prefix = "cancel", .name = "cancel" },
    };
    for (verbs) |verb| {
        if (std.mem.startsWith(u8, operation_id, verb.prefix) and
            (operation_id.len == verb.prefix.len or std.ascii.isUpper(operation_id[verb.prefix.len])))
        {
            return try self.allocator.dupe(u8, verb.name);
        }
    }
    return self.sanitizeIdentifierAlloc(operation_id);
}

pub fn sanitizeIdentifierAlloc(self: *UnifiedApiGenerator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(self.allocator);
    for (value, 0..) |c, i| {
        const lower = std.ascii.toLower(c);
        const valid = if (i == 0) ident.isIdentStart(lower) else ident.isIdentContinue(lower);
        try out.append(self.allocator, if (valid) lower else '_');
    }
    if (out.items.len == 0 or !ident.isIdentStart(out.items[0])) try out.insert(self.allocator, 0, '_');
    if (ident.isReservedIdent(out.items)) try out.appendSlice(self.allocator, "_");
    return try out.toOwnedSlice(self.allocator);
}

pub fn appendIndent(self: *UnifiedApiGenerator, indent: usize) !void {
    for (0..indent) |_| try self.buffer.appendSlice(self.allocator, "    ");
}
