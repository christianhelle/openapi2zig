const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const Operation = @import("../../../models/common/document.zig").Operation;
const Parameter = @import("../../../models/common/document.zig").Parameter;
const helpers = @import("helpers.zig");
const classifyBody = helpers.classifyBody;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

pub fn appendFlatCallArguments(self: *UnifiedApiGenerator, operation: Operation) !void {
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
            try self.appendFlatParamIdentifier(name);
        }
    }
    try self.buffer.appendSlice(self.allocator, ")");
}

/// Emit the base Zig type for a parameter, without the optional prefix or
/// null default that callers may add.
pub fn appendParamBaseType(self: *UnifiedApiGenerator, param: Parameter) !void {
    if (param.location == .body) {
        const kind = classifyBody(param.content_type);
        if (kind == .binary or kind == .text) {
            try self.buffer.appendSlice(self.allocator, "[]const u8");
        } else if (param.schema) |schema| {
            try self.appendZigTypeFromSchema(schema);
        } else {
            try self.buffer.appendSlice(self.allocator, "std.json.Value");
        }
    } else {
        if (param.schema) |schema| {
            try self.appendZigQueryTypeFromSchema(schema);
        } else if (param.type) |param_type| {
            try self.appendZigTypeFromSchemaType(param_type);
        } else {
            try self.buffer.appendSlice(self.allocator, "[]const u8");
        }
    }
}

/// Emit the `options` struct parameter wrapping all non-body parameters of
/// an operation. Optional parameters become nullable fields with a `null`
/// default; required parameters stay non-optional.
pub fn appendOptionsParam(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
    var count: usize = 0;
    if (operation.parameters) |params| {
        for (params) |param| {
            if (param.location != .body) count += 1;
        }
    }
    if (count == 0) return;

    try self.buffer.appendSlice(self.allocator, ", options: ");
    try self.appendOptionsTypeName(operation, method, path);
}

/// Build the map key identifying an operation in options_type_names.
/// Operation ids are namespaced separately from path-based fallback keys,
/// and the HTTP method disambiguates fallback operations sharing a path,
/// so distinct operations can never overwrite one another's entry.
pub fn optionsTypeKeyAlloc(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) ![]const u8 {
    if (operation.operationId) |op_id| {
        return try std.fmt.allocPrint(self.allocator, "op:{s}", .{op_id});
    }
    return try std.fmt.allocPrint(self.allocator, "path:{s}:{s}", .{ method, path });
}

/// Emit the name of the options struct type for an operation. The name
/// derives from the operation id so all functions of an operation share
/// the same type; operations without an operation id use the same fallback
/// as the flat function name, derived from the operation path. The name is
/// reserved by generateOptionsType so every variant references the same
/// disambiguated type.
pub fn appendOptionsTypeName(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
    const key = try self.optionsTypeKeyAlloc(operation, method, path);
    defer self.allocator.free(key);
    if (self.options_type_names.get(key)) |name| {
        if (operation.operationId == null) {
            try self.appendEscapedIdentifier(name);
        } else {
            try self.appendIdentifier(name);
        }
        return;
    }
    try self.appendRawOptionsTypeName(operation, path);
}

pub fn appendRawOptionsTypeName(self: *UnifiedApiGenerator, operation: Operation, path: []const u8) !void {
    if (self.operationNameOf(operation)) |op_id| {
        const name = try std.fmt.allocPrint(self.allocator, "{s}Options", .{op_id});
        defer self.allocator.free(name);
        try self.appendIdentifier(name);
    } else {
        const name = try std.fmt.allocPrint(self.allocator, "operation{s}Options", .{path[1..]});
        defer self.allocator.free(name);
        try self.appendEscapedIdentifier(name);
    }
}

/// Emit a top-level declaration of the options struct type for an
/// operation when parameters-as-struct is enabled and the operation has
/// non-body parameters. The type name is reserved so it never collides
/// with operation names, schemas, or runtime declarations.
pub fn generateOptionsType(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, document: UnifiedDocument) !void {
    if (!self.args.parameters_as_struct) return;
    var count: usize = 0;
    if (operation.parameters) |params| {
        for (params) |param| {
            if (param.location != .body) count += 1;
        }
    }
    if (count == 0) return;

    var candidate = if (self.operationNameOf(operation)) |op_id|
        try std.fmt.allocPrint(self.allocator, "{s}Options", .{op_id})
    else
        try std.fmt.allocPrint(self.allocator, "operation{s}Options", .{path[1..]});
    defer self.allocator.free(candidate);
    while (self.topLevelNameConflicts(candidate, document)) {
        const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_", .{candidate});
        self.allocator.free(candidate);
        candidate = suffixed;
    }
    const key = try self.optionsTypeKeyAlloc(operation, method, path);
    defer self.allocator.free(key);
    if (self.options_type_names.fetchRemove(key)) |kv| {
        self.allocator.free(kv.key);
        self.allocator.free(kv.value);
    }
    {
        const key_copy_ = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy_);
        const candidate_copy_ = try self.allocator.dupe(u8, candidate);
        errdefer self.allocator.free(candidate_copy_);
        try self.options_type_names.put(key_copy_, candidate_copy_);
    }

    try self.buffer.appendSlice(self.allocator, "pub const ");
    try self.appendOptionsTypeName(operation, method, path);
    try self.buffer.appendSlice(self.allocator, " = struct {\n");
    if (operation.parameters) |params| {
        for (params, 0..) |param, i| {
            if (param.location == .body) continue;
            const field_name = try self.optionsFieldNameAlloc(operation, method, path, i);
            defer self.allocator.free(field_name);
            try self.buffer.appendSlice(self.allocator, "    ");
            try self.appendFieldIdentifier(field_name);
            try self.buffer.appendSlice(self.allocator, ": ");
            const optional = param.location != .path and !param.required;
            if (optional) try self.buffer.appendSlice(self.allocator, "?");
            try self.appendParamBaseType(param);
            if (optional) try self.buffer.appendSlice(self.allocator, " = null");
            try self.buffer.appendSlice(self.allocator, ",\n");
        }
    }
    try self.buffer.appendSlice(self.allocator, "};\n\n");
}

/// Emit individual `requestBody` arguments for body parameters, used after
/// the `options` struct when parameters-as-struct is enabled.
pub fn appendBodyParams(self: *UnifiedApiGenerator, params: []Parameter) !void {
    for (params) |param| {
        if (param.location != .body) continue;
        try self.buffer.appendSlice(self.allocator, ", requestBody: ");
        try self.appendParamBaseType(param);
    }
}

/// Compute the field name of a parameter in the options struct. When the
/// escaped name collides with an earlier parameter, a numeric suffix is
/// appended so generated structs never declare duplicate fields.
/// Field-identifier escaping is injective, so comparing raw names is
/// equivalent to comparing escaped names. Results are cached so repeated
/// references don't rescan the operation's parameter list. `index` is the
/// parameter's position in `operation.parameters` and uniquely identifies
/// it, so parameters sharing a name and location never share a cache entry.
pub fn optionsFieldNameAlloc(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, index: usize) ![]const u8 {
    const memo_key = try self.optionsFieldNameKeyAlloc(operation, method, path, index);
    defer self.allocator.free(memo_key);
    if (self.options_field_names.get(memo_key)) |cached| {
        return try self.allocator.dupe(u8, cached);
    }
    const field_name = try self.computeOptionsFieldName(operation, index);
    errdefer self.allocator.free(field_name);
    {
        const memo_key_copy_ = try self.allocator.dupe(u8, memo_key);
        errdefer self.allocator.free(memo_key_copy_);
        const field_name_copy_ = try self.allocator.dupe(u8, field_name);
        errdefer self.allocator.free(field_name_copy_);
        try self.options_field_names.put(memo_key_copy_, field_name_copy_);
    }
    return field_name;
}

/// Build the cache key identifying a parameter within an operation for
/// options_field_names. The operation key disambiguates operations, and
/// the index uniquely identifies the parameter within one.
pub fn optionsFieldNameKeyAlloc(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, index: usize) ![]const u8 {
    const op_key = try self.optionsTypeKeyAlloc(operation, method, path);
    defer self.allocator.free(op_key);
    return try std.fmt.allocPrint(self.allocator, "{s}\x1f{d}", .{ op_key, index });
}

/// Scan an operation's non-body parameters to resolve the disambiguated
/// field name of the parameter at `index`. A numeric suffix is appended
/// when the natural name is already taken by an earlier parameter or is
/// any other parameter's original name, so generated structs never declare
/// duplicate fields. Field-identifier escaping is injective, so comparing
/// raw names is equivalent to comparing escaped names.
pub fn computeOptionsFieldName(self: *UnifiedApiGenerator, operation: Operation, index: usize) ![]const u8 {
    var used = std.StringHashMap(void).init(self.allocator);
    var reserved = std.StringHashMap(void).init(self.allocator);
    var allocated = std.ArrayList([]const u8).empty;
    defer {
        for (allocated.items) |item| self.allocator.free(item);
        allocated.deinit(self.allocator);
        used.deinit();
        reserved.deinit();
    }
    if (operation.parameters) |params| {
        for (params) |p| {
            if (p.location == .body) continue;
            try reserved.put(p.name, {});
        }
        for (params, 0..) |p, i| {
            if (p.location == .body) continue;
            var name = p.name;
            var counter: usize = 0;
            while (used.contains(name) or (reserved.contains(name) and !std.mem.eql(u8, name, p.name))) {
                counter += 1;
                const suffixed = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ p.name, counter });
                try allocated.append(self.allocator, suffixed);
                name = suffixed;
            }
            if (i == index) return try self.allocator.dupe(u8, name);
            try used.put(name, {});
        }
    }
    return try self.allocator.dupe(u8, if (operation.parameters) |params| params[index].name else "");
}

/// Emit a reference to a parameter argument. In parameters-as-struct mode
/// the value lives in the `options` struct and must use field escaping and
/// duplicate-name disambiguation.
pub fn appendParamReference(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8, index: usize, parameter: Parameter) !void {
    if (self.args.parameters_as_struct) {
        const field_name = try self.optionsFieldNameAlloc(operation, method, path, index);
        defer self.allocator.free(field_name);
        try self.buffer.appendSlice(self.allocator, "options.");
        try self.appendFieldIdentifier(field_name);
    } else {
        try self.appendFlatParamIdentifier(parameter.name);
    }
}

pub fn appendFlatOperationParameters(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
    if (operation.parameters) |params| {
        if (self.args.parameters_as_struct) {
            try self.appendOptionsParam(operation, method, path);
            try self.appendBodyParams(params);
            return;
        }
        for (params) |param| {
            try self.buffer.appendSlice(self.allocator, ", ");
            const name: []const u8 = if (param.location == .body) "requestBody" else param.name;
            try self.appendFlatParamIdentifier(name);
            try self.buffer.appendSlice(self.allocator, ": ");
            if ((param.location == .query or param.location == .header) and !param.required) try self.buffer.appendSlice(self.allocator, "?");
            try self.appendParamBaseType(param);
        }
    }
}

pub fn appendUnusedParameters(self: *UnifiedApiGenerator, operation: Operation, method: []const u8, path: []const u8) !void {
    if (operation.parameters) |parameters| {
        for (parameters, 0..) |parameter, i| {
            if (parameter.location != .path and parameter.location != .body and parameter.location != .query and parameter.location != .header) {
                try self.buffer.appendSlice(self.allocator, "    _ = ");
                try self.appendParamReference(operation, method, path, i, parameter);
                try self.buffer.appendSlice(self.allocator, ";\n");
            }
        }
    }
}
