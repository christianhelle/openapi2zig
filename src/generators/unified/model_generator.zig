const std = @import("std");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Schema = @import("../../models/common/document.zig").Schema;

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isReservedIdent(name: []const u8) bool {
    const reserved = [_][]const u8{
        "addrspace", "align",    "allowzero", "and",       "anyerror", "anyframe",    "anyopaque", "anytype",
        "asm",       "async",    "await",     "bool",      "break",    "callconv",    "catch",     "comptime",
        "const",     "continue", "defer",     "else",      "enum",     "errdefer",    "error",     "export",
        "extern",    "false",    "fn",        "for",       "if",       "inline",      "isize",     "linksection",
        "noalias",   "noreturn", "nosuspend", "null",      "opaque",   "or",          "orelse",    "packed",
        "pub",       "resume",   "return",    "struct",    "suspend",  "switch",      "test",      "threadlocal",
        "true",      "try",      "type",      "undefined", "union",    "unreachable", "usize",     "usingnamespace",
        "var",       "void",     "volatile",  "while",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn isBareIdentifier(name: []const u8) bool {
    if (name.len == 0 or !isIdentStart(name[0]) or isReservedIdent(name)) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return true;
}

fn isExtensibleRequest(name: []const u8) bool {
    return std.mem.eql(u8, name, "CreateResponse") or
        std.mem.eql(u8, name, "CreateChatCompletionRequest");
}

pub const UnifiedModelGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    source_schemas: ?*const std.StringHashMap(Schema) = null,

    pub fn init(allocator: std.mem.Allocator) UnifiedModelGenerator {
        return UnifiedModelGenerator{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).empty,
        };
    }

    pub fn deinit(self: *UnifiedModelGenerator) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn generate(self: *UnifiedModelGenerator, document: UnifiedDocument) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.generateHeader();

        if (document.schemas) |schemas| {
            try self.generateSchemas(schemas);
            try self.generateManualAliases(schemas);
        }

        return try self.allocator.dupe(u8, self.buffer.items);
    }

    fn appendIdentifier(self: *UnifiedModelGenerator, name: []const u8) !void {
        if (name.len == 0) {
            try self.buffer.appendSlice(self.allocator, "__empty");
            return;
        }
        if (isBareIdentifier(name)) {
            try self.buffer.appendSlice(self.allocator, name);
            return;
        }

        try self.buffer.appendSlice(self.allocator, "@\"");
        for (name) |c| {
            switch (c) {
                '\\', '"' => {
                    try self.buffer.append(self.allocator, '\\');
                    try self.buffer.append(self.allocator, c);
                },
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
        try self.buffer.appendSlice(self.allocator, "\"");
    }

    fn generateHeader(self: *UnifiedModelGenerator) !void {
        try self.buffer.appendSlice(self.allocator, "const std = @import(\"std\");\n\n");
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n");
        try self.buffer.appendSlice(self.allocator, "// Generated Zig structures from OpenAPI\n");
        try self.buffer.appendSlice(self.allocator, "///////////////////////////////////////////\n\n");
    }

    fn generateSchemas(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
        self.source_schemas = &schemas;
        defer self.source_schemas = null;

        var schema_iterator = schemas.iterator();
        while (schema_iterator.next()) |entry| {
            const schema_name = entry.key_ptr.*;
            const schema = entry.value_ptr.*;
            try self.generateSchema(schema_name, schema);
        }
    }

    fn generateSchema(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) anyerror!void {
        if (try self.generateManualSchema(name, schema)) return;
        if (schema.type == .reference) return;

        if (try self.generateUnionAlias(name, schema)) return;
        if (try self.generateDiscriminatorUnion(name, schema)) return;
        if (try self.generateStructuralUnion(name, schema)) return;

        if (schema.description) |description| {
            if (std.mem.eql(u8, description, "OpenAPI oneOf with discriminator could not be generated safely; generator currently uses std.json.Value.")) {
                try self.buffer.appendSlice(self.allocator, "// OpenAPI oneOf with discriminator could not be generated safely; generator currently uses std.json.Value.\n");
            }
        }
        if (schema.properties) |properties| {
            if (properties.count() > 0) {
                try self.generateFieldHelpers(name, properties);
                try self.buffer.appendSlice(self.allocator, "pub const ");
                try self.appendIdentifier(name);
                try self.buffer.appendSlice(self.allocator, " = struct {\n");
                try self.generateStructFields(name, properties, schema.required);
                if (std.mem.eql(u8, name, "ChatCompletionRequestAssistantMessage") and !properties.contains("reasoning_details")) {
                    try self.buffer.appendSlice(self.allocator, "    reasoning_details: ?std.json.Value = null,\n");
                }
                if (isExtensibleRequest(name)) {
                    try self.buffer.appendSlice(self.allocator, "    extra_body: ?std.json.Value = null,\n");
                    try self.generateJsonStringify(properties, schema.required);
                }
                try self.buffer.appendSlice(self.allocator, "};\n\n");
                return;
            }
        }

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator, " = ");
        try self.appendZigType(schema);
        try self.buffer.appendSlice(self.allocator, ";\n\n");
    }

    fn appendStringLiteral(self: *UnifiedModelGenerator, value: []const u8) !void {
        try self.buffer.append(self.allocator, '"');
        for (value) |c| {
            switch (c) {
                '\\', '"' => {
                    try self.buffer.append(self.allocator, '\\');
                    try self.buffer.append(self.allocator, c);
                },
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
        try self.buffer.append(self.allocator, '"');
    }

    fn sanitizeIdentifierAlloc(self: *UnifiedModelGenerator, value: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);
        var prev_was_underscore = false;
        for (value, 0..) |c, i| {
            const next = if (i + 1 < value.len) value[i + 1] else 0;
            const prev = if (i > 0) value[i - 1] else 0;
            const insert_word_break = std.ascii.isUpper(c) and i > 0 and out.items.len > 0 and !prev_was_underscore and
                ((std.ascii.isLower(prev) or std.ascii.isDigit(prev)) or (std.ascii.isUpper(prev) and std.ascii.isLower(next)));
            if (insert_word_break) try out.append(self.allocator, '_');

            const lower = std.ascii.toLower(c);
            const valid = if (out.items.len == 0) isIdentStart(lower) else isIdentContinue(lower);
            const byte = if (valid) lower else '_';
            if (byte == '_' and prev_was_underscore) continue;
            try out.append(self.allocator, byte);
            prev_was_underscore = byte == '_';
        }
        while (out.items.len > 0 and out.items[out.items.len - 1] == '_') _ = out.pop();
        if (out.items.len == 0 or !isIdentStart(out.items[0])) try out.insert(self.allocator, 0, '_');
        if (isReservedIdent(out.items)) try out.appendSlice(self.allocator, "_");
        return try out.toOwnedSlice(self.allocator);
    }

    fn unionVariants(schema: Schema) ?[]Schema {
        if (schema.one_of) |variants| return variants;
        if (schema.any_of) |variants| return variants;
        return null;
    }

    fn isNullSchema(schema: Schema) bool {
        return schema.type == .null;
    }

    fn nonNullUnionChild(schema: Schema) ?Schema {
        const variants = unionVariants(schema) orelse return null;
        var child: ?Schema = null;
        for (variants) |variant| {
            if (isNullSchema(variant)) continue;
            if (child != null) return null;
            child = variant;
        }
        return child;
    }

    fn isStringLikeSchema(self: *UnifiedModelGenerator, schema: Schema) bool {
        if (schema.ref) |ref| {
            const schemas = self.source_schemas orelse return false;
            return self.isStringLikeSchema(schemas.get(refName(ref)) orelse return false);
        }
        if (schema.type == .string) return true;
        if (unionVariants(schema)) |variants| {
            for (variants) |variant| {
                if (isNullSchema(variant)) continue;
                if (!self.isStringLikeSchema(variant)) return false;
            }
            return true;
        }
        return false;
    }

    fn isNullableSchema(schema: Schema) bool {
        const variants = unionVariants(schema) orelse return false;
        for (variants) |variant| if (isNullSchema(variant)) return true;
        return false;
    }

    fn isPrimitiveUnionSchema(schema: Schema) bool {
        const variants = unionVariants(schema) orelse return false;
        if (variants.len == 0) return false;
        for (variants) |variant| {
            if (isNullSchema(variant)) continue;
            if (variant.ref != null or variant.properties != null or variant.items != null) return false;
            switch (variant.type orelse return false) {
                .string, .integer, .number, .boolean => {},
                else => return false,
            }
        }
        return true;
    }

    fn schemaVariantTag(self: *UnifiedModelGenerator, schema: Schema, discriminator_property: []const u8) ?[]const u8 {
        const target = if (schema.ref) |ref| blk: {
            const schemas = self.source_schemas orelse return null;
            break :blk schemas.get(refName(ref)) orelse return null;
        } else schema;
        const properties = target.properties orelse return null;
        const field = properties.get(discriminator_property) orelse return null;
        const enum_values = field.enum_values orelse return null;
        if (enum_values.len == 0) return null;
        return switch (enum_values[0]) {
            .string => |value| value,
            else => null,
        };
    }

    fn refName(ref: []const u8) []const u8 {
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| return ref[last_slash + 1 ..];
        return ref;
    }

    fn variantTypeNameAlloc(self: *UnifiedModelGenerator, union_name: []const u8, variant: Schema, index: usize) ![]const u8 {
        if (variant.ref) |ref| return try self.allocator.dupe(u8, refName(ref));
        return try std.fmt.allocPrint(self.allocator, "{s}Variant{d}", .{ union_name, index });
    }

    fn appendTitleIdentPart(self: *UnifiedModelGenerator, out: *std.ArrayList(u8), value: []const u8, capitalize_first: bool) !void {
        if (value.len == 0) {
            try out.appendSlice(self.allocator, if (capitalize_first or out.items.len > 0) "Empty" else "empty");
            return;
        }
        var capitalize_next = true;
        for (value) |c| {
            if (std.ascii.isAlphanumeric(c)) {
                const should_capitalize = capitalize_next and (capitalize_first or out.items.len > 0);
                try out.append(self.allocator, if (should_capitalize) std.ascii.toUpper(c) else c);
                capitalize_next = false;
            } else {
                capitalize_next = true;
            }
        }
    }

    fn fieldTypeNameAlloc(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);
        try self.appendTitleIdentPart(&out, owner_name, false);
        try self.appendTitleIdentPart(&out, field_name, true);
        if (out.items.len == 0 or !isIdentStart(out.items[0])) try out.insert(self.allocator, 0, '_');
        return try out.toOwnedSlice(self.allocator);
    }

    fn arrayFieldItemTypeNameAlloc(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8) ![]const u8 {
        const field_type_name = try self.fieldTypeNameAlloc(owner_name, field_name);
        defer self.allocator.free(field_type_name);
        return try std.fmt.allocPrint(self.allocator, "{s}Item", .{field_type_name});
    }

    fn discriminatorVariantsAreSafe(self: *UnifiedModelGenerator, variants: []Schema, discriminator_property: []const u8) !bool {
        var names = std.StringHashMap(void).init(self.allocator);
        defer {
            var iterator = names.iterator();
            while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
            names.deinit();
        }

        for (variants) |variant| {
            const tag = self.schemaVariantTag(variant, discriminator_property) orelse return false;
            if (variant.ref == null and (variant.properties == null or variant.properties.?.count() == 0)) return false;
            const name = try self.sanitizeIdentifierAlloc(tag);
            errdefer self.allocator.free(name);
            if (std.mem.eql(u8, name, "raw") or names.contains(name)) {
                self.allocator.free(name);
                return false;
            }
            try names.put(name, {});
        }
        return true;
    }

    fn generateInlineVariantTypes(self: *UnifiedModelGenerator, union_name: []const u8, variants: []Schema) !void {
        for (variants, 0..) |variant, i| {
            if (variant.ref != null) continue;
            const type_name = try self.variantTypeNameAlloc(union_name, variant, i);
            defer self.allocator.free(type_name);
            if (variant.type == .array) {
                if (variant.items) |item_schema| {
                    if (try self.canGenerateNamedArrayItemType(item_schema.*)) {
                        const item_type_name = try std.fmt.allocPrint(self.allocator, "{s}Item", .{type_name});
                        defer self.allocator.free(item_type_name);
                        try self.generateSchema(item_type_name, item_schema.*);
                    }
                }
            }
            if (variant.properties) |properties| {
                if (properties.count() > 0) {
                    try self.generateFieldHelpers(type_name, properties);
                    try self.buffer.appendSlice(self.allocator, "pub const ");
                    try self.appendIdentifier(type_name);
                    try self.buffer.appendSlice(self.allocator, " = struct {\n");
                    try self.generateStructFields(type_name, properties, variant.required);
                    try self.buffer.appendSlice(self.allocator, "};\n\n");
                    continue;
                }
            }
            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.appendIdentifier(type_name);
            try self.buffer.appendSlice(self.allocator, " = ");
            try self.appendZigType(variant);
            try self.buffer.appendSlice(self.allocator, ";\n\n");
        }
    }

    fn generateDiscriminatorUnion(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) !bool {
        const variants = unionVariants(schema) orelse return false;
        const discriminator_property = schema.discriminator_property orelse return false;
        if (!try self.discriminatorVariantsAreSafe(variants, discriminator_property)) return false;

        try self.generateInlineVariantTypes(name, variants);

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator, " = union(enum) {\n");

        for (variants, 0..) |variant, i| {
            const tag = self.schemaVariantTag(variant, discriminator_property).?;
            const field_name = try self.sanitizeIdentifierAlloc(tag);
            defer self.allocator.free(field_name);
            const type_name = try self.variantTypeNameAlloc(name, variant, i);
            defer self.allocator.free(type_name);
            try self.buffer.appendSlice(self.allocator, "    ");
            try self.buffer.appendSlice(self.allocator, field_name);
            try self.buffer.appendSlice(self.allocator, ": ");
            try self.appendIdentifier(type_name);
            try self.buffer.appendSlice(self.allocator, ",\n");
        }

        try self.buffer.appendSlice(self.allocator,
            \\    raw: std.json.Value,
            \\
            \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
            \\        return jsonParseFromValue(allocator, value, options);
            \\    }
            \\
            \\    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
            \\        if (source != .object) return error.UnexpectedToken;
        );
        try self.buffer.appendSlice(self.allocator, "        const discriminator = source.object.get(");
        try self.appendStringLiteral(discriminator_property);
        try self.buffer.appendSlice(self.allocator,
            \\) orelse return .{ .raw = source };
            \\        if (discriminator != .string) return .{ .raw = source };
            \\
        );

        for (variants, 0..) |variant, i| {
            const tag = self.schemaVariantTag(variant, discriminator_property).?;
            const field_name = try self.sanitizeIdentifierAlloc(tag);
            defer self.allocator.free(field_name);
            const type_name = try self.variantTypeNameAlloc(name, variant, i);
            defer self.allocator.free(type_name);
            try self.buffer.appendSlice(self.allocator, "        if (std.mem.eql(u8, discriminator.string, ");
            try self.appendStringLiteral(tag);
            try self.buffer.appendSlice(self.allocator, ")) {\n");
            try self.buffer.appendSlice(self.allocator, "            return .{ .");
            try self.buffer.appendSlice(self.allocator, field_name);
            try self.buffer.appendSlice(self.allocator, " = try std.json.parseFromValueLeaky(");
            try self.appendIdentifier(type_name);
            try self.buffer.appendSlice(self.allocator, ", allocator, source, options) };\n");
            try self.buffer.appendSlice(self.allocator, "        }\n");
        }

        try self.buffer.appendSlice(self.allocator,
            \\
            \\        return .{ .raw = source };
            \\    }
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        switch (self) {
        );

        for (variants) |variant| {
            const tag = self.schemaVariantTag(variant, discriminator_property).?;
            const field_name = try self.sanitizeIdentifierAlloc(tag);
            defer self.allocator.free(field_name);
            try self.buffer.appendSlice(self.allocator, "            .");
            try self.buffer.appendSlice(self.allocator, field_name);
            try self.buffer.appendSlice(self.allocator, " => |value| try jw.write(value),\n");
        }

        try self.buffer.appendSlice(self.allocator,
            \\            .raw => |value| try jw.write(value),
            \\        }
            \\    }
            \\};
            \\
            \\
        );
        return true;
    }

    fn variantFieldNameAlloc(self: *UnifiedModelGenerator, variant: Schema, index: usize) ![]const u8 {
        if (self.schemaVariantTag(variant, "event")) |tag| return try self.sanitizeIdentifierAlloc(tag);
        if (self.schemaVariantTag(variant, "type")) |tag| return try self.sanitizeIdentifierAlloc(tag);
        if (variant.ref) |ref| return try self.sanitizeIdentifierAlloc(refName(ref));
        if (variant.title) |title| {
            if (std.ascii.indexOfIgnoreCase(title, "text") != null and variant.type == .string) return try self.allocator.dupe(u8, "text");
            return try self.sanitizeIdentifierAlloc(title);
        }
        if (variant.type) |schema_type| {
            return try self.allocator.dupe(u8, switch (schema_type) {
                .string => "string",
                .integer => "integer",
                .number => "number",
                .boolean => "boolean",
                .array => "items",
                .object => "object",
                else => "value",
            });
        }
        return try std.fmt.allocPrint(self.allocator, "variant_{d}", .{index});
    }

    fn resolvedSchema(self: *UnifiedModelGenerator, schema: Schema) ?Schema {
        if (schema.ref) |ref| {
            const schemas = self.source_schemas orelse return null;
            return schemas.get(refName(ref));
        }
        return schema;
    }

    fn stringEnumValues(self: *UnifiedModelGenerator, schema: Schema) ?[]const std.json.Value {
        const resolved = self.resolvedSchema(schema) orelse return null;
        if (resolved.type != .string) return null;
        const values = resolved.enum_values orelse return null;
        if (values.len == 0) return null;
        for (values) |value| if (value != .string) return null;
        return values;
    }

    fn arrayVariantFieldNameAlloc(self: *UnifiedModelGenerator, variant: Schema, index: usize) !?[]const u8 {
        if (variant.type != .array) return null;
        if (variant.title) |title| {
            const name = try self.sanitizeIdentifierAlloc(title);
            if (!std.mem.eql(u8, name, "array")) return name;
            self.allocator.free(name);
        }
        const items = variant.items orelse return try std.fmt.allocPrint(self.allocator, "items_{d}", .{index});
        if (items.ref) |ref| {
            const base = try self.sanitizeIdentifierAlloc(refName(ref));
            defer self.allocator.free(base);
            return try std.fmt.allocPrint(self.allocator, "{s}_items", .{base});
        }
        if (items.type) |item_type| {
            switch (item_type) {
                .string => return try self.allocator.dupe(u8, "strings"),
                .integer => return try self.allocator.dupe(u8, "integers"),
                .number => return try self.allocator.dupe(u8, "numbers"),
                .boolean => return try self.allocator.dupe(u8, "booleans"),
                .array => return try self.allocator.dupe(u8, "arrays"),
                else => {},
            }
        }
        if (items.title) |title| {
            const base = try self.sanitizeIdentifierAlloc(title);
            defer self.allocator.free(base);
            return try std.fmt.allocPrint(self.allocator, "{s}_items", .{base});
        }
        return try std.fmt.allocPrint(self.allocator, "items_{d}", .{index});
    }

    fn structuralVariantFieldNameAlloc(self: *UnifiedModelGenerator, variant: Schema, index: usize) ![]const u8 {
        if (variant.ref) |ref| return try self.sanitizeIdentifierAlloc(refName(ref));
        if (try self.arrayVariantFieldNameAlloc(variant, index)) |name| return name;
        return self.variantFieldNameAlloc(variant, index);
    }

    fn appendStructuralVariantType(self: *UnifiedModelGenerator, union_name: []const u8, variant: Schema, index: usize) !void {
        if (variant.ref != null or variant.properties != null) {
            const type_name = try self.variantTypeNameAlloc(union_name, variant, index);
            defer self.allocator.free(type_name);
            try self.appendIdentifier(type_name);
            return;
        }
        if (variant.type == .array) {
            if (variant.items) |item_schema| {
                if (try self.canGenerateNamedArrayItemType(item_schema.*)) {
                    const type_name = try self.variantTypeNameAlloc(union_name, variant, index);
                    defer self.allocator.free(type_name);
                    const item_type_name = try std.fmt.allocPrint(self.allocator, "{s}Item", .{type_name});
                    defer self.allocator.free(item_type_name);
                    try self.buffer.appendSlice(self.allocator, "[]const ");
                    try self.appendIdentifier(item_type_name);
                    return;
                }
            }
        }
        try self.appendZigType(variant);
    }

    fn structuralUnionVariantsAreSafe(self: *UnifiedModelGenerator, variants: []Schema) !bool {
        var names = std.StringHashMap(void).init(self.allocator);
        defer {
            var iterator = names.iterator();
            while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
            names.deinit();
        }
        for (variants, 0..) |variant, i| {
            if (isNullSchema(variant)) return false;
            if (self.stringEnumValues(variant)) |values| {
                for (values) |value| {
                    const field_name = try self.sanitizeIdentifierAlloc(value.string);
                    errdefer self.allocator.free(field_name);
                    if (std.mem.eql(u8, field_name, "raw") or names.contains(field_name)) {
                        self.allocator.free(field_name);
                        return false;
                    }
                    try names.put(field_name, {});
                }
                continue;
            }
            if (variant.ref == null and variant.type == null and variant.properties == null) return false;
            const field_name = try self.structuralVariantFieldNameAlloc(variant, i);
            errdefer self.allocator.free(field_name);
            if (std.mem.eql(u8, field_name, "raw") or names.contains(field_name)) {
                self.allocator.free(field_name);
                return false;
            }
            try names.put(field_name, {});
        }
        return true;
    }

    fn generateStructuralUnion(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) !bool {
        const variants = unionVariants(schema) orelse return false;
        if (!try self.structuralUnionVariantsAreSafe(variants)) return false;

        try self.generateInlineVariantTypes(name, variants);

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator, " = union(enum) {\n");
        for (variants, 0..) |variant, i| {
            if (self.stringEnumValues(variant)) |values| {
                for (values) |value| {
                    const field_name = try self.sanitizeIdentifierAlloc(value.string);
                    defer self.allocator.free(field_name);
                    try self.buffer.appendSlice(self.allocator, "    ");
                    try self.buffer.appendSlice(self.allocator, field_name);
                    try self.buffer.appendSlice(self.allocator, ",\n");
                }
                continue;
            }
            const field_name = try self.structuralVariantFieldNameAlloc(variant, i);
            defer self.allocator.free(field_name);
            try self.buffer.appendSlice(self.allocator, "    ");
            try self.buffer.appendSlice(self.allocator, field_name);
            try self.buffer.appendSlice(self.allocator, ": ");
            try self.appendStructuralVariantType(name, variant, i);
            try self.buffer.appendSlice(self.allocator, ",\n");
        }

        try self.buffer.appendSlice(self.allocator,
            \\    raw: std.json.Value,
            \\
            \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
            \\        return jsonParseFromValue(allocator, value, options);
            \\    }
            \\
            \\    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        );
        for (variants) |variant| {
            if (self.stringEnumValues(variant)) |values| {
                for (values) |value| {
                    const field_name = try self.sanitizeIdentifierAlloc(value.string);
                    defer self.allocator.free(field_name);
                    try self.buffer.appendSlice(self.allocator, "        if (source == .string and std.mem.eql(u8, source.string, ");
                    try self.appendStringLiteral(value.string);
                    try self.buffer.appendSlice(self.allocator, ")) return .");
                    try self.buffer.appendSlice(self.allocator, field_name);
                    try self.buffer.appendSlice(self.allocator, ";\n");
                }
            }
        }
        for (variants, 0..) |variant, i| {
            if (self.stringEnumValues(variant) != null) continue;
            const field_name = try self.structuralVariantFieldNameAlloc(variant, i);
            defer self.allocator.free(field_name);
            try self.buffer.appendSlice(self.allocator, "        if (std.json.parseFromValueLeaky(");
            try self.appendStructuralVariantType(name, variant, i);
            try self.buffer.appendSlice(self.allocator, ", allocator, source, options)) |value| {\n");
            try self.buffer.appendSlice(self.allocator, "            return .{ .");
            try self.buffer.appendSlice(self.allocator, field_name);
            try self.buffer.appendSlice(self.allocator, " = value };\n");
            try self.buffer.appendSlice(self.allocator, "        } else |_| {}\n");
        }
        try self.buffer.appendSlice(self.allocator,
            \\        return .{ .raw = source };
            \\    }
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        switch (self) {
        );
        for (variants, 0..) |variant, i| {
            if (self.stringEnumValues(variant)) |values| {
                for (values) |value| {
                    const field_name = try self.sanitizeIdentifierAlloc(value.string);
                    defer self.allocator.free(field_name);
                    try self.buffer.appendSlice(self.allocator, "            .");
                    try self.buffer.appendSlice(self.allocator, field_name);
                    try self.buffer.appendSlice(self.allocator, " => try jw.write(");
                    try self.appendStringLiteral(value.string);
                    try self.buffer.appendSlice(self.allocator, "),\n");
                }
                continue;
            }
            const field_name = try self.structuralVariantFieldNameAlloc(variant, i);
            defer self.allocator.free(field_name);
            try self.buffer.appendSlice(self.allocator, "            .");
            try self.buffer.appendSlice(self.allocator, field_name);
            try self.buffer.appendSlice(self.allocator, " => |value| try jw.write(value),\n");
        }
        try self.buffer.appendSlice(self.allocator,
            \\            .raw => |value| try jw.write(value),
            \\        }
            \\    }
            \\};
            \\
            \\
        );
        return true;
    }

    fn generateUnionAlias(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) !bool {
        if (schema.discriminator_property != null) return false;
        if (nonNullUnionChild(schema)) |child| {
            const variants = unionVariants(schema).?;
            var null_count: usize = 0;
            for (variants) |variant| {
                if (isNullSchema(variant)) null_count += 1;
            }
            if (null_count == 1 and variants.len == 2) {
                try self.buffer.appendSlice(self.allocator, "pub const ");
                try self.appendIdentifier(name);
                try self.buffer.appendSlice(self.allocator, " = ?");
                try self.appendZigType(child);
                try self.buffer.appendSlice(self.allocator, ";\n\n");
                return true;
            }
        }
        if (self.isStringLikeSchema(schema)) {
            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.appendIdentifier(name);
            try self.buffer.appendSlice(self.allocator, " = ");
            if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
            try self.buffer.appendSlice(self.allocator, "[]const u8;\n\n");
            return true;
        }

        if (!isPrimitiveUnionSchema(schema)) return false;
        const variants = unionVariants(schema).?;
        var has_string = false;
        var has_integer = false;
        var has_number = false;
        var has_boolean = false;
        for (variants) |variant| {
            if (isNullSchema(variant)) continue;
            switch (variant.type.?) {
                .string => has_string = true,
                .integer => has_integer = true,
                .number => has_number = true,
                .boolean => has_boolean = true,
                else => {},
            }
        }
        const unique_count = @as(u8, @intFromBool(has_string)) + @as(u8, @intFromBool(has_integer)) + @as(u8, @intFromBool(has_number)) + @as(u8, @intFromBool(has_boolean));
        if (unique_count == 1) {
            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.appendIdentifier(name);
            try self.buffer.appendSlice(self.allocator, " = ");
            if (has_string) try self.buffer.appendSlice(self.allocator, "[]const u8") else if (has_integer) try self.buffer.appendSlice(self.allocator, "i64") else if (has_number) try self.buffer.appendSlice(self.allocator, "f64") else try self.buffer.appendSlice(self.allocator, "bool");
            try self.buffer.appendSlice(self.allocator, ";\n\n");
            return true;
        }

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator, " = union(enum) {\n");
        if (has_string) try self.buffer.appendSlice(self.allocator, "    string: []const u8,\n");
        if (has_integer) try self.buffer.appendSlice(self.allocator, "    integer: i64,\n");
        if (has_number) try self.buffer.appendSlice(self.allocator, "    number: f64,\n");
        if (has_boolean) try self.buffer.appendSlice(self.allocator, "    boolean: bool,\n");
        try self.buffer.appendSlice(self.allocator,
            \\    raw: std.json.Value,
            \\
            \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
            \\        return jsonParseFromValue(allocator, value, options);
            \\    }
            \\
            \\    pub fn jsonParseFromValue(_: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) !@This() {
            \\        return switch (source) {
        );
        var emitted_string = false;
        var emitted_integer = false;
        var emitted_number = false;
        var emitted_boolean = false;
        for (variants) |variant| {
            if (isNullSchema(variant)) continue;
            switch (variant.type.?) {
                .string => if (!emitted_string) {
                    emitted_string = true;
                    try self.buffer.appendSlice(self.allocator, "            .string => |value| .{ .string = value },\n");
                },
                .integer => if (!emitted_integer) {
                    emitted_integer = true;
                    try self.buffer.appendSlice(self.allocator, "            .integer => |value| .{ .integer = value },\n");
                },
                .number => if (!emitted_number) {
                    emitted_number = true;
                    try self.buffer.appendSlice(self.allocator, "            .float => |value| .{ .number = value },\n");
                },
                .boolean => if (!emitted_boolean) {
                    emitted_boolean = true;
                    try self.buffer.appendSlice(self.allocator, "            .bool => |value| .{ .boolean = value },\n");
                },
                else => {},
            }
        }
        try self.buffer.appendSlice(self.allocator,
            \\            else => .{ .raw = source },
            \\        };
            \\    }
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        switch (self) {
        );
        if (has_string) try self.buffer.appendSlice(self.allocator, "            .string => |value| try jw.write(value),\n");
        if (has_integer) try self.buffer.appendSlice(self.allocator, "            .integer => |value| try jw.write(value),\n");
        if (has_number) try self.buffer.appendSlice(self.allocator, "            .number => |value| try jw.write(value),\n");
        if (has_boolean) try self.buffer.appendSlice(self.allocator, "            .boolean => |value| try jw.write(value),\n");
        try self.buffer.appendSlice(self.allocator,
            \\            .raw => |value| try jw.write(value),
            \\        }
            \\    }
            \\};
            \\
            \\
        );
        return true;
    }

    fn appendJsonValueBackedUnionType(self: *UnifiedModelGenerator, name: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator,
            \\ = union(enum) {
            \\    null,
            \\    bool: bool,
            \\    integer: i64,
            \\    float: f64,
            \\    number_string: []const u8,
            \\    string: []const u8,
            \\    array: std.json.Array,
            \\    object: std.json.ObjectMap,
            \\
            \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
            \\        return jsonParseFromValue(allocator, value, options);
            \\    }
            \\
            \\    pub fn jsonParseFromValue(_: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) !@This() {
            \\        return switch (source) {
            \\            .null => .null,
            \\            .bool => |value| .{ .bool = value },
            \\            .integer => |value| .{ .integer = value },
            \\            .float => |value| .{ .float = value },
            \\            .number_string => |value| .{ .number_string = value },
            \\            .string => |value| .{ .string = value },
            \\            .array => |value| .{ .array = value },
            \\            .object => |value| .{ .object = value },
            \\        };
            \\    }
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        switch (self) {
            \\            .null => try jw.write(null),
            \\            .bool => |value| try jw.write(value),
            \\            .integer => |value| try jw.write(value),
            \\            .float => |value| try jw.write(value),
            \\            .number_string => |value| try jw.print("{s}", .{value}),
            \\            .string => |value| try jw.write(value),
            \\            .array => |value| try jw.write(value.items),
            \\            .object => |value| {
            \\                try jw.beginObject();
            \\                var iterator = value.iterator();
            \\                while (iterator.next()) |entry| {
            \\                    try jw.objectField(entry.key_ptr.*);
            \\                    try jw.write(entry.value_ptr.*);
            \\                }
            \\                try jw.endObject();
            \\            },
            \\        }
            \\    }
            \\};
            \\
            \\
        );
    }

    fn generateManualSchema(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) !bool {
        _ = schema;
        if (std.mem.eql(u8, name, "EmptyModelParam")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const EmptyModelParam = struct {
                \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
                \\        _ = try std.json.innerParse(std.json.Value, allocator, source, options);
                \\        return .{};
                \\    }
                \\
                \\    pub fn jsonParseFromValue(_: std.mem.Allocator, _: std.json.Value, _: std.json.ParseOptions) !@This() {
                \\        return .{};
                \\    }
                \\
                \\    pub fn jsonStringify(_: @This(), jw: *std.json.Stringify) !void {
                \\        try jw.beginObject();
                \\        try jw.endObject();
                \\    }
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "FunctionParameters") or std.mem.eql(u8, name, "ResponseFormatJsonSchemaSchema")) {
            try self.appendJsonValueBackedUnionType(name);
            return true;
        }

        if (std.mem.eql(u8, name, "CompoundFilter")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const CompoundFilterItem = union(enum) {
                \\    comparison_filter: ComparisonFilter,
                \\    compound_filter: CompoundFilter,
                \\    raw: std.json.Value,
                \\
                \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
                \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
                \\        return jsonParseFromValue(allocator, value, options);
                \\    }
                \\
                \\    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
                \\        if (source != .object) return .{ .raw = source };
                \\        const discriminator = source.object.get("type") orelse return .{ .raw = source };
                \\        if (discriminator != .string) return .{ .raw = source };
                \\        if (std.mem.eql(u8, discriminator.string, "and") or std.mem.eql(u8, discriminator.string, "or")) {
                \\            if (std.json.parseFromValueLeaky(CompoundFilter, allocator, source, options)) |value| return .{ .compound_filter = value } else |_| return .{ .raw = source };
                \\        }
                \\        if (std.mem.eql(u8, discriminator.string, "eq") or std.mem.eql(u8, discriminator.string, "ne") or std.mem.eql(u8, discriminator.string, "gt") or std.mem.eql(u8, discriminator.string, "gte") or std.mem.eql(u8, discriminator.string, "lt") or std.mem.eql(u8, discriminator.string, "lte") or std.mem.eql(u8, discriminator.string, "in") or std.mem.eql(u8, discriminator.string, "nin")) {
                \\            if (std.json.parseFromValueLeaky(ComparisonFilter, allocator, source, options)) |value| return .{ .comparison_filter = value } else |_| return .{ .raw = source };
                \\        }
                \\        return .{ .raw = source };
                \\    }
                \\
                \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
                \\        switch (self) {
                \\            .comparison_filter => |value| try jw.write(value),
                \\            .compound_filter => |value| try jw.write(value),
                \\            .raw => |value| try jw.write(value),
                \\        }
                \\    }
                \\};
                \\
                \\pub const CompoundFilter = struct {
                \\    type: []const u8,
                \\    filters: []const CompoundFilterItem,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ToolChoiceAllowed")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ToolChoiceAllowed = struct {
                \\    type: []const u8,
                \\    mode: []const u8,
                \\    tools: []const Tool,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionAllowedTools")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ChatCompletionAllowedTools = struct {
                \\    mode: []const u8,
                \\    tools: []const ChatCompletionTool,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "CreateChatCompletionResponse")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const CreateChatCompletionResponse = struct {
                \\    id: []const u8,
                \\    object: []const u8,
                \\    created: i64,
                \\    model: []const u8,
                \\    choices: []const ChatCompletionChoice,
                \\    usage: ?CompletionUsage = null,
                \\    system_fingerprint: ?[]const u8 = null,
                \\    service_tier: ?ServiceTier = null,
                \\};
                \\
                \\pub const ChatCompletionChoice = struct {
                \\    index: i64,
                \\    message: ChatCompletionResponseMessage,
                \\    finish_reason: ?[]const u8 = null,
                \\    logprobs: ?std.json.Value = null,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "CreateChatCompletionStreamResponse")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const CreateChatCompletionStreamResponse = struct {
                \\    id: []const u8,
                \\    object: []const u8,
                \\    created: i64,
                \\    model: []const u8,
                \\    choices: []const ChatCompletionChunkChoice,
                \\    usage: ?CompletionUsage = null,
                \\    system_fingerprint: ?[]const u8 = null,
                \\    service_tier: ?ServiceTier = null,
                \\};
                \\
                \\pub const ChatCompletionChunkChoice = struct {
                \\    index: i64,
                \\    delta: ChatCompletionStreamResponseDelta,
                \\    finish_reason: ?[]const u8 = null,
                \\    logprobs: ?std.json.Value = null,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionResponseMessage")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ChatCompletionResponseMessageUrlCitation = struct {
                \\    end_index: i64,
                \\    start_index: i64,
                \\    url: []const u8,
                \\    title: []const u8,
                \\};
                \\
                \\pub const ChatCompletionResponseMessageAnnotation = struct {
                \\    type: []const u8,
                \\    url_citation: ChatCompletionResponseMessageUrlCitation,
                \\};
                \\
                \\pub const ChatCompletionResponseMessage = struct {
                \\    role: []const u8,
                \\    content: ?[]const u8 = null,
                \\    refusal: ?[]const u8 = null,
                \\    tool_calls: ?[]const ChatCompletionMessageToolCall = null,
                \\    reasoning_details: ?std.json.Value = null,
                \\    annotations: ?[]const ChatCompletionResponseMessageAnnotation = null,
                \\    function_call: ?std.json.Value = null,
                \\    audio: ?ChatCompletionResponseMessageAudio = null,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionStreamResponseDelta")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ChatCompletionStreamResponseDelta = struct {
                \\    role: ?[]const u8 = null,
                \\    content: ?[]const u8 = null,
                \\    refusal: ?[]const u8 = null,
                \\    tool_calls: ?[]const ChatCompletionMessageToolCallChunk = null,
                \\    function_call: ?std.json.Value = null,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "InputMessageContent")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const InputMessageContent = union(enum) {
                \\    text: []const u8,
                \\    parts: []const InputContent,
                \\    raw: std.json.Value,
                \\
                \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
                \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
                \\        return jsonParseFromValue(allocator, value, options);
                \\    }
                \\
                \\    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
                \\        return switch (source) {
                \\            .string => |value| .{ .text = value },
                \\            .array => .{ .parts = try std.json.parseFromValueLeaky([]const InputContent, allocator, source, options) },
                \\            else => .{ .raw = source },
                \\        };
                \\    }
                \\
                \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
                \\        switch (self) {
                \\            .text => |value| try jw.write(value),
                \\            .parts => |value| try jw.write(value),
                \\            .raw => |value| try jw.write(value),
                \\        }
                \\    }
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "EasyInputMessage")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const EasyInputMessage = struct {
                \\    role: []const u8,
                \\    content: InputMessageContent,
                \\    phase: ?MessagePhase = null,
                \\    type: ?[]const u8 = null,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionRequestMessageContentPartImage")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ChatCompletionRequestMessageContentPartImageUrl = struct {
                \\    url: []const u8,
                \\    detail: ?[]const u8 = null,
                \\};
                \\
                \\pub const ChatCompletionRequestMessageContentPartImage = struct {
                \\    type: []const u8,
                \\    image_url: ChatCompletionRequestMessageContentPartImageUrl,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionRequestMessageContentPartFile")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ChatCompletionRequestMessageContentPartFileData = struct {
                \\    filename: ?[]const u8 = null,
                \\    file_data: ?[]const u8 = null,
                \\    file_id: ?[]const u8 = null,
                \\};
                \\
                \\pub const ChatCompletionRequestMessageContentPartFile = struct {
                \\    type: []const u8,
                \\    file: ChatCompletionRequestMessageContentPartFileData,
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionRequestMessage")) {
            try self.buffer.appendSlice(self.allocator,
                \\pub const ChatCompletionRequestMessage = struct {
                \\    role: []const u8,
                \\    content: ?std.json.Value = null,
                \\    name: ?[]const u8 = null,
                \\    tool_calls: ?[]const ChatCompletionMessageToolCall = null,
                \\    tool_call_id: ?[]const u8 = null,
                \\    refusal: ?std.json.Value = null,
                \\    reasoning_details: ?std.json.Value = null,
                \\    extra: ?std.json.Value = null,
                \\
                \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
                \\        try jw.beginObject();
                \\        try jw.objectField("role");
                \\        try jw.write(self.role);
                \\        if (self.content) |value| {
                \\            try jw.objectField("content");
                \\            try jw.write(value);
                \\        }
                \\        if (self.name) |value| {
                \\            try jw.objectField("name");
                \\            try jw.write(value);
                \\        }
                \\        if (self.tool_calls) |value| {
                \\            try jw.objectField("tool_calls");
                \\            try jw.write(value);
                \\        }
                \\        if (self.tool_call_id) |value| {
                \\            try jw.objectField("tool_call_id");
                \\            try jw.write(value);
                \\        }
                \\        if (self.refusal) |value| {
                \\            try jw.objectField("refusal");
                \\            try jw.write(value);
                \\        }
                \\        if (self.reasoning_details) |value| {
                \\            try jw.objectField("reasoning_details");
                \\            try jw.write(value);
                \\        }
                \\        if (self.extra) |extra| {
                \\            if (extra == .object) {
                \\                var iterator = extra.object.iterator();
                \\                while (iterator.next()) |entry| {
                \\                    try jw.objectField(entry.key_ptr.*);
                \\                    try jw.write(entry.value_ptr.*);
                \\                }
                \\            }
                \\        }
                \\        try jw.endObject();
                \\    }
                \\};
                \\
                \\
            );
            return true;
        }

        if (std.mem.eql(u8, name, "ChatCompletionMessageToolCalls")) {
            try self.buffer.appendSlice(self.allocator, "pub const ChatCompletionMessageToolCalls = []const ChatCompletionMessageToolCall;\n\n");
            return true;
        }

        return false;
    }

    fn generateOpenAiDynamicFieldTypes(self: *UnifiedModelGenerator) !void {
        try self.buffer.appendSlice(self.allocator,
            \\pub const OpenApi2ZigDynamicObject = std.json.ArrayHashMap(std.json.Value);
            \\
            \\pub const EvalResponsesSourceMetadata = OpenApi2ZigDynamicObject;
            \\pub const EvalRunOutputItemResultSample = OpenApi2ZigDynamicObject;
            \\pub const AssignedRoleDetailsCreatedByUserObj = OpenApi2ZigDynamicObject;
            \\pub const AssignedRoleDetailsMetadata = OpenApi2ZigDynamicObject;
            \\pub const MCPListToolsToolAnnotations = OpenApi2ZigDynamicObject;
            \\
            \\pub const MCPToolHeaders = std.json.ArrayHashMap([]const u8);
            \\
            \\pub const ChatCompletionResponseMessageAudio = struct {
            \\    id: []const u8,
            \\    expires_at: i64,
            \\    data: []const u8,
            \\    transcript: []const u8,
            \\};
            \\
            \\pub const ChatkitWorkflowStateVariable = union(enum) {
            \\    string: []const u8,
            \\    integer: i64,
            \\    boolean: bool,
            \\    number: f64,
            \\
            \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            \\        const value = try std.json.innerParse(std.json.Value, allocator, source, options);
            \\        return jsonParseFromValue(allocator, value, options);
            \\    }
            \\
            \\    pub fn jsonParseFromValue(_: std.mem.Allocator, source: std.json.Value, _: std.json.ParseOptions) !@This() {
            \\        return switch (source) {
            \\            .string => |value| .{ .string = value },
            \\            .integer => |value| .{ .integer = value },
            \\            .bool => |value| .{ .boolean = value },
            \\            .float => |value| .{ .number = value },
            \\            else => error.UnexpectedToken,
            \\        };
            \\    }
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        switch (self) {
            \\            .string => |value| try jw.write(value),
            \\            .integer => |value| try jw.write(value),
            \\            .boolean => |value| try jw.write(value),
            \\            .number => |value| try jw.write(value),
            \\        }
            \\    }
            \\};
            \\
            \\pub const ChatkitWorkflowStateVariables = std.json.ArrayHashMap(ChatkitWorkflowStateVariable);
            \\
            \\
        );
    }

    fn generateManualAliases(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
        if (schemas.contains("ChatkitWorkflow") or schemas.contains("MCPTool") or schemas.contains("ChatCompletionResponseMessage")) {
            try self.generateOpenAiDynamicFieldTypes();
        }
        if (schemas.contains("InputContent") and !schemas.contains("InputMessageContent")) {
            _ = try self.generateManualSchema("InputMessageContent", .{});
        }
        if (schemas.contains("CreateChatCompletionStreamResponse") and !schemas.contains("ChatCompletionChunk")) {
            try self.buffer.appendSlice(self.allocator, "pub const ChatCompletionChunk = CreateChatCompletionStreamResponse;\n\n");
        }
    }

    fn arrayChildSchema(schema: Schema) ?Schema {
        if (schema.type == .array or schema.items != null) {
            if (schema.items) |items| return items.*;
            return null;
        }
        if (nonNullUnionChild(schema)) |child| return arrayChildSchema(child);
        return null;
    }

    fn canGenerateNamedArrayItemType(self: *UnifiedModelGenerator, schema: Schema) !bool {
        if (schema.ref != null) return false;
        if (unionVariants(schema)) |variants| {
            if (schema.discriminator_property) |discriminator_property| {
                return try self.discriminatorVariantsAreSafe(variants, discriminator_property);
            }
            return try self.structuralUnionVariantsAreSafe(variants);
        }
        if (schema.properties) |properties| return properties.count() > 0;
        return false;
    }

    fn canGenerateNamedFieldType(self: *UnifiedModelGenerator, schema: Schema) !bool {
        if (schema.ref != null) return false;
        if (arrayChildSchema(schema) != null) return try self.canGenerateNamedArrayItemType(arrayChildSchema(schema).?);
        if (unionVariants(schema)) |variants| {
            var non_null_count: usize = 0;
            for (variants) |variant| {
                if (!isNullSchema(variant)) non_null_count += 1;
            }
            if (non_null_count == 1) {
                for (variants) |variant| {
                    if (isNullSchema(variant)) continue;
                    return try self.canGenerateNamedFieldType(variant);
                }
            }
            if (schema.discriminator_property) |discriminator_property| {
                return try self.discriminatorVariantsAreSafe(variants, discriminator_property);
            }
            return try self.structuralUnionVariantsAreSafe(variants);
        }
        if (schema.properties) |properties| return properties.count() > 0;
        return false;
    }

    fn generateFieldHelpers(self: *UnifiedModelGenerator, owner_name: []const u8, properties: std.StringHashMap(Schema)) !void {
        var prop_iterator = properties.iterator();
        while (prop_iterator.next()) |entry| {
            const field_name = entry.key_ptr.*;
            const field_schema = entry.value_ptr.*;
            if (arrayChildSchema(field_schema)) |item_schema| {
                if (!try self.canGenerateNamedArrayItemType(item_schema)) continue;
                const type_name = try self.arrayFieldItemTypeNameAlloc(owner_name, field_name);
                defer self.allocator.free(type_name);
                try self.generateSchema(type_name, item_schema);
            } else if (try self.canGenerateNamedFieldType(field_schema)) {
                const type_name = try self.fieldTypeNameAlloc(owner_name, field_name);
                defer self.allocator.free(type_name);
                try self.generateSchema(type_name, field_schema);
            }
        }
    }

    fn appendNamedArrayTypeForField(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8, field_schema: Schema) !bool {
        const item_schema = arrayChildSchema(field_schema) orelse return false;
        if (!try self.canGenerateNamedArrayItemType(item_schema)) return false;
        if (isNullableSchema(field_schema)) try self.buffer.appendSlice(self.allocator, "?");
        const type_name = try self.arrayFieldItemTypeNameAlloc(owner_name, field_name);
        defer self.allocator.free(type_name);
        try self.buffer.appendSlice(self.allocator, "[]const ");
        try self.appendIdentifier(type_name);
        return true;
    }

    fn appendNamedFieldTypeForField(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8, field_schema: Schema) !bool {
        if (arrayChildSchema(field_schema) != null) return false;
        if (!try self.canGenerateNamedFieldType(field_schema)) return false;
        if (isNullableSchema(field_schema)) try self.buffer.appendSlice(self.allocator, "?");
        const type_name = try self.fieldTypeNameAlloc(owner_name, field_name);
        defer self.allocator.free(type_name);
        try self.appendIdentifier(type_name);
        return true;
    }

    fn generateStructFields(self: *UnifiedModelGenerator, owner_name: []const u8, properties: std.StringHashMap(Schema), required: ?[][]const u8) !void {
        var prop_iterator = properties.iterator();
        while (prop_iterator.next()) |entry| {
            const field_name = entry.key_ptr.*;
            const field_schema = entry.value_ptr.*;
            const is_required = self.isFieldRequired(field_name, required);
            try self.generateStructField(owner_name, field_name, field_schema, is_required);
        }
    }

    fn appendManualFieldType(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8) !bool {
        if (std.mem.eql(u8, owner_name, "ChatkitWorkflow") and std.mem.eql(u8, field_name, "state_variables")) {
            try self.buffer.appendSlice(self.allocator, "?ChatkitWorkflowStateVariables");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "EvalResponsesSource") and std.mem.eql(u8, field_name, "metadata")) {
            try self.buffer.appendSlice(self.allocator, "?EvalResponsesSourceMetadata");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "EvalRunOutputItemResult") and std.mem.eql(u8, field_name, "sample")) {
            try self.buffer.appendSlice(self.allocator, "?EvalRunOutputItemResultSample");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "AssignedRoleDetails") and std.mem.eql(u8, field_name, "created_by_user_obj")) {
            try self.buffer.appendSlice(self.allocator, "?AssignedRoleDetailsCreatedByUserObj");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "AssignedRoleDetails") and std.mem.eql(u8, field_name, "metadata")) {
            try self.buffer.appendSlice(self.allocator, "?AssignedRoleDetailsMetadata");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "MCPListToolsTool") and std.mem.eql(u8, field_name, "annotations")) {
            try self.buffer.appendSlice(self.allocator, "?MCPListToolsToolAnnotations");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "MCPTool") and std.mem.eql(u8, field_name, "headers")) {
            try self.buffer.appendSlice(self.allocator, "?MCPToolHeaders");
            return true;
        }
        if (std.mem.eql(u8, owner_name, "FunctionTool") and std.mem.eql(u8, field_name, "parameters")) {
            try self.buffer.appendSlice(self.allocator, "?FunctionParameters");
            return true;
        }
        if ((std.mem.eql(u8, owner_name, "RunObject") or
            std.mem.eql(u8, owner_name, "CreateRunRequest") or
            std.mem.eql(u8, owner_name, "CreateThreadAndRunRequest")) and
            std.mem.eql(u8, field_name, "tool_choice"))
        {
            try self.buffer.appendSlice(self.allocator, "?AssistantsApiToolChoiceOption");
            return true;
        }
        return false;
    }

    fn generateStructField(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8, field_schema: Schema, is_required: bool) !void {
        try self.buffer.appendSlice(self.allocator, "    ");
        try self.appendIdentifier(field_name);
        try self.buffer.appendSlice(self.allocator, ": ");

        if (try self.appendManualFieldType(owner_name, field_name)) {
            if (!is_required) try self.buffer.appendSlice(self.allocator, " = null");
            try self.buffer.appendSlice(self.allocator, ",\n");
            return;
        }

        if (!is_required and !isNullableSchema(field_schema)) {
            try self.buffer.appendSlice(self.allocator, "?");
        }

        if (std.mem.eql(u8, field_name, "model")) {
            if (is_required and isNullableSchema(field_schema)) try self.buffer.appendSlice(self.allocator, "?");
            if (!is_required and isNullableSchema(field_schema)) try self.buffer.appendSlice(self.allocator, "?");
            try self.buffer.appendSlice(self.allocator, "[]const u8");
        } else if (!try self.appendNamedArrayTypeForField(owner_name, field_name, field_schema)) {
            if (!try self.appendNamedFieldTypeForField(owner_name, field_name, field_schema)) {
                try self.appendZigType(field_schema);
            }
        }

        if (!is_required) {
            try self.buffer.appendSlice(self.allocator, " = null");
        }

        try self.buffer.appendSlice(self.allocator, ",\n");
    }

    fn generateJsonStringify(self: *UnifiedModelGenerator, properties: std.StringHashMap(Schema), required: ?[][]const u8) !void {
        try self.buffer.appendSlice(self.allocator,
            \\
            \\    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
            \\        try jw.beginObject();
            \\
        );

        var prop_iterator = properties.iterator();
        while (prop_iterator.next()) |entry| {
            const field_name = entry.key_ptr.*;
            if (self.isFieldRequired(field_name, required)) {
                try self.buffer.appendSlice(self.allocator, "        try jw.objectField(\"");
                try self.buffer.appendSlice(self.allocator, field_name);
                try self.buffer.appendSlice(self.allocator, "\");\n");
                try self.buffer.appendSlice(self.allocator, "        try jw.write(self.");
                try self.appendIdentifier(field_name);
                try self.buffer.appendSlice(self.allocator, ");\n");
            } else {
                try self.buffer.appendSlice(self.allocator, "        if (self.");
                try self.appendIdentifier(field_name);
                try self.buffer.appendSlice(self.allocator, ") |value| {\n");
                try self.buffer.appendSlice(self.allocator, "            try jw.objectField(\"");
                try self.buffer.appendSlice(self.allocator, field_name);
                try self.buffer.appendSlice(self.allocator, "\");\n");
                try self.buffer.appendSlice(self.allocator, "            try jw.write(value);\n");
                try self.buffer.appendSlice(self.allocator, "        }\n");
            }
        }

        try self.buffer.appendSlice(self.allocator,
            \\
            \\        if (self.extra_body) |extra| {
            \\            if (extra == .object) {
            \\                var iterator = extra.object.iterator();
            \\                while (iterator.next()) |entry| {
            \\                    try jw.objectField(entry.key_ptr.*);
            \\                    try jw.write(entry.value_ptr.*);
            \\                }
            \\            }
            \\        }
            \\
            \\        try jw.endObject();
            \\    }
            \\
        );
    }

    fn appendZigType(self: *UnifiedModelGenerator, schema: Schema) !void {
        if (schema.discriminator_property == null and self.isStringLikeSchema(schema)) {
            if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
            try self.buffer.appendSlice(self.allocator, "[]const u8");
            return;
        }

        if (schema.discriminator_property == null) {
            if (nonNullUnionChild(schema)) |child| {
                const variants = unionVariants(schema).?;
                var null_count: usize = 0;
                for (variants) |variant| {
                    if (isNullSchema(variant)) null_count += 1;
                }
                if (null_count == 1 and variants.len == 2) {
                    try self.buffer.appendSlice(self.allocator, "?");
                    try self.appendZigType(child);
                    return;
                }
            }
        }

        if (schema.items != null and schema.type == null) {
            try self.buffer.appendSlice(self.allocator, "[]const ");
            try self.appendArrayItemType(schema.items.?.*);
            return;
        }

        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                try self.appendIdentifier(ref[last_slash + 1 ..]);
                return;
            }
            try self.buffer.appendSlice(self.allocator, "[]const u8");
            return;
        }

        if (schema.type) |schema_type| {
            switch (schema_type) {
                .string => try self.buffer.appendSlice(self.allocator, "[]const u8"),
                .integer => try self.buffer.appendSlice(self.allocator, "i64"),
                .number => try self.buffer.appendSlice(self.allocator, "f64"),
                .boolean => try self.buffer.appendSlice(self.allocator, "bool"),
                .array => {
                    if (schema.items) |items| {
                        try self.buffer.appendSlice(self.allocator, "[]const ");
                        try self.appendArrayItemType(items.*);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "[]const std.json.Value");
                    }
                },
                .object, .reference => try self.buffer.appendSlice(self.allocator, "std.json.Value"),
                .null => try self.buffer.appendSlice(self.allocator, "void"),
            }
            return;
        }

        try self.buffer.appendSlice(self.allocator, "std.json.Value");
    }

    fn appendArrayItemType(self: *UnifiedModelGenerator, schema: Schema) !void {
        if (schema.ref) |ref| {
            if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
                try self.appendIdentifier(ref[last_slash + 1 ..]);
                return;
            }
        }

        if (schema.type) |schema_type| {
            switch (schema_type) {
                .string => try self.buffer.appendSlice(self.allocator, "[]const u8"),
                .integer => try self.buffer.appendSlice(self.allocator, "i64"),
                .number => try self.buffer.appendSlice(self.allocator, "f64"),
                .boolean => try self.buffer.appendSlice(self.allocator, "bool"),
                .array => {
                    if (schema.items) |items| {
                        try self.buffer.appendSlice(self.allocator, "[]const ");
                        try self.appendArrayItemType(items.*);
                    } else {
                        try self.buffer.appendSlice(self.allocator, "std.json.Value");
                    }
                },
                else => try self.buffer.appendSlice(self.allocator, "std.json.Value"),
            }
            return;
        }

        try self.buffer.appendSlice(self.allocator, "std.json.Value");
    }

    fn isFieldRequired(self: *UnifiedModelGenerator, field_name: []const u8, required: ?[][]const u8) bool {
        _ = self;
        if (required == null) return false;

        for (required.?) |req_field| {
            if (std.mem.eql(u8, field_name, req_field)) {
                return true;
            }
        }

        return false;
    }
};
