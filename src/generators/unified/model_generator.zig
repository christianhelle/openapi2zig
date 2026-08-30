const std = @import("std");
const UnifiedDocument = @import("../../models/common/document.zig").UnifiedDocument;
const Schema = @import("../../models/common/document.zig").Schema;
const ident = @import("ident_utils.zig");

pub fn isExtensibleRequest(name: []const u8) bool {
    return std.mem.eql(u8, name, "CreateResponse") or
        std.mem.eql(u8, name, "CreateChatCompletionRequest");
}

pub const UnifiedModelGenerator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    source_schemas: ?*const std.StringHashMap(Schema) = null,

    pub const unionVariants = @import("model_generator/unions.zig").unionVariants;
    pub const isNullSchema = @import("model_generator/unions.zig").isNullSchema;
    pub const nonNullUnionChild = @import("model_generator/unions.zig").nonNullUnionChild;
    pub const isStringLikeSchema = @import("model_generator/unions.zig").isStringLikeSchema;
    pub const isNullableSchema = @import("model_generator/unions.zig").isNullableSchema;
    pub const isPrimitiveUnionSchema = @import("model_generator/unions.zig").isPrimitiveUnionSchema;
    pub const schemaVariantTag = @import("model_generator/unions.zig").schemaVariantTag;
    pub const refName = @import("model_generator/unions.zig").refName;
    pub const variantTypeNameAlloc = @import("model_generator/unions.zig").variantTypeNameAlloc;
    pub const appendTitleIdentPart = @import("model_generator/unions.zig").appendTitleIdentPart;
    pub const fieldTypeNameAlloc = @import("model_generator/unions.zig").fieldTypeNameAlloc;
    pub const arrayFieldItemTypeNameAlloc = @import("model_generator/unions.zig").arrayFieldItemTypeNameAlloc;
    pub const discriminatorVariantsAreSafe = @import("model_generator/unions.zig").discriminatorVariantsAreSafe;
    pub const generateInlineVariantTypes = @import("model_generator/unions.zig").generateInlineVariantTypes;
    pub const generateDiscriminatorUnion = @import("model_generator/unions.zig").generateDiscriminatorUnion;
    pub const variantFieldNameAlloc = @import("model_generator/unions.zig").variantFieldNameAlloc;
    pub const resolvedSchema = @import("model_generator/unions.zig").resolvedSchema;
    pub const stringEnumValues = @import("model_generator/unions.zig").stringEnumValues;
    pub const arrayVariantFieldNameAlloc = @import("model_generator/unions.zig").arrayVariantFieldNameAlloc;
    pub const structuralVariantFieldNameAlloc = @import("model_generator/unions.zig").structuralVariantFieldNameAlloc;
    pub const appendStructuralVariantType = @import("model_generator/unions.zig").appendStructuralVariantType;
    pub const structuralUnionVariantsAreSafe = @import("model_generator/unions.zig").structuralUnionVariantsAreSafe;
    pub const generateStructuralUnion = @import("model_generator/unions.zig").generateStructuralUnion;
    pub const generateUnionAlias = @import("model_generator/unions.zig").generateUnionAlias;
    pub const appendJsonValueBackedUnionType = @import("model_generator/unions.zig").appendJsonValueBackedUnionType;
    pub const generateManualSchema = @import("model_generator/manual.zig").generateManualSchema;
    pub const generateOpenAiDynamicFieldTypes = @import("model_generator/manual.zig").generateOpenAiDynamicFieldTypes;
    pub const generateManualAliases = @import("model_generator/manual.zig").generateManualAliases;
    pub const appendManualFieldType = @import("model_generator/manual.zig").appendManualFieldType;
    pub const arrayChildSchema = @import("model_generator/fields.zig").arrayChildSchema;
    pub const canGenerateNamedArrayItemType = @import("model_generator/fields.zig").canGenerateNamedArrayItemType;
    pub const canGenerateNamedFieldType = @import("model_generator/fields.zig").canGenerateNamedFieldType;
    pub const generateFieldHelpers = @import("model_generator/fields.zig").generateFieldHelpers;
    pub const appendNamedArrayTypeForField = @import("model_generator/fields.zig").appendNamedArrayTypeForField;
    pub const appendNamedFieldTypeForField = @import("model_generator/fields.zig").appendNamedFieldTypeForField;
    pub const generateStructFields = @import("model_generator/fields.zig").generateStructFields;
    pub const generateStructField = @import("model_generator/fields.zig").generateStructField;
    pub const generateJsonStringify = @import("model_generator/fields.zig").generateJsonStringify;
    pub const appendZigType = @import("model_generator/fields.zig").appendZigType;
    pub const appendArrayItemType = @import("model_generator/fields.zig").appendArrayItemType;
    pub const isFieldRequired = @import("model_generator/fields.zig").isFieldRequired;

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
            self.source_schemas = &schemas;
            defer self.source_schemas = null;
            try self.generateSchemas(schemas);
            try self.generateManualAliases(schemas);
        }

        return try self.allocator.dupe(u8, self.buffer.items);
    }

    pub fn appendIdentifier(self: *UnifiedModelGenerator, name: []const u8) !void {
        try ident.appendIdentifier(&self.buffer, self.allocator, name);
    }

    pub fn appendFieldIdentifier(self: *UnifiedModelGenerator, name: []const u8) !void {
        try ident.appendFieldIdentifier(&self.buffer, self.allocator, name);
    }

    pub fn generateHeader(self: *UnifiedModelGenerator) !void {
        try self.buffer.appendSlice(self.allocator,
            \\const std = @import("std");
            \\
            \\
        );
    }

    pub fn generateSchemas(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
        var schema_iterator = schemas.iterator();
        while (schema_iterator.next()) |entry| {
            const schema_name = entry.key_ptr.*;
            const schema = entry.value_ptr.*;
            try self.generateSchema(schema_name, schema);
        }
    }

    pub fn generateSchema(self: *UnifiedModelGenerator, name: []const u8, schema: Schema) anyerror!void {
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
            try self.generateEmptyObjectStruct(name);
            return;
        }

        if (schema.type == .object) {
            try self.appendJsonValueBackedUnionType(name);
            return;
        }

        if (schema.type == .array) {
            if (schema.items) |items| {
                if (items.ref) |ref| {
                    try self.buffer.appendSlice(self.allocator, "pub const ");
                    try self.appendIdentifier(name);
                    try self.buffer.appendSlice(self.allocator, " = []const ");
                    try self.appendIdentifier(refName(ref));
                    try self.buffer.appendSlice(self.allocator, ";\n\n");
                    return;
                } else if (try self.canGenerateNamedArrayItemType(items.*)) {
                    const item_type_name = try std.fmt.allocPrint(self.allocator, "{s}Item", .{name});
                    defer self.allocator.free(item_type_name);
                    try self.generateSchema(item_type_name, items.*);
                    try self.buffer.appendSlice(self.allocator, "pub const ");
                    try self.appendIdentifier(name);
                    try self.buffer.appendSlice(self.allocator, " = []const ");
                    try self.appendIdentifier(item_type_name);
                    try self.buffer.appendSlice(self.allocator, ";\n\n");
                    return;
                }
            }
            try self.buffer.appendSlice(self.allocator, "pub const ");
            try self.appendIdentifier(name);
            try self.buffer.appendSlice(self.allocator, " = ");
            try self.appendZigType(schema);
            try self.buffer.appendSlice(self.allocator, ";\n\n");
            return;
        }

        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator, " = ");
        try self.appendZigType(schema);
        try self.buffer.appendSlice(self.allocator, ";\n\n");
    }

    pub fn generateEmptyObjectStruct(self: *UnifiedModelGenerator, name: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.appendIdentifier(name);
        try self.buffer.appendSlice(self.allocator,
            \\ = struct {
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
    }

    pub fn appendStringLiteral(self: *UnifiedModelGenerator, value: []const u8) !void {
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

    pub fn sanitizeIdentifierAlloc(self: *UnifiedModelGenerator, value: []const u8) ![]const u8 {
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
            const valid = if (out.items.len == 0) ident.isIdentStart(lower) else ident.isIdentContinue(lower);
            const byte = if (valid) lower else '_';
            if (byte == '_' and prev_was_underscore) continue;
            try out.append(self.allocator, byte);
            prev_was_underscore = byte == '_';
        }
        while (out.items.len > 0 and out.items[out.items.len - 1] == '_') _ = out.pop();
        if (out.items.len == 0 or !ident.isIdentStart(out.items[0])) try out.insert(self.allocator, 0, '_');
        if (ident.isReservedIdent(out.items)) try out.appendSlice(self.allocator, "_");
        return try out.toOwnedSlice(self.allocator);
    }
};
