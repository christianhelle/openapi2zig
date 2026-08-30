const std = @import("std");
const UnifiedDocument = @import("../../../models/common/document.zig").UnifiedDocument;
const Schema = @import("../../../models/common/document.zig").Schema;
const ident = @import("../ident_utils.zig");
const model_generator = @import("../model_generator.zig");
const UnifiedModelGenerator = model_generator.UnifiedModelGenerator;
const isExtensibleRequest = model_generator.isExtensibleRequest;
const unions = @import("unions.zig");
const nonNullUnionChild = unions.nonNullUnionChild;
const unionVariants = unions.unionVariants;
const isNullableSchema = unions.isNullableSchema;
const isNullSchema = unions.isNullSchema;

pub fn arrayChildSchema(schema: Schema) ?Schema {
    if (schema.type == .array or schema.items != null) {
        if (schema.items) |items| return items.*;
        return null;
    }
    if (nonNullUnionChild(schema)) |child| return arrayChildSchema(child);
    return null;
}

pub fn canGenerateNamedArrayItemType(self: *UnifiedModelGenerator, schema: Schema) !bool {
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

pub fn canGenerateNamedFieldType(self: *UnifiedModelGenerator, schema: Schema) !bool {
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

pub fn generateFieldHelpers(self: *UnifiedModelGenerator, owner_name: []const u8, properties: std.StringHashMap(Schema)) !void {
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

pub fn appendNamedArrayTypeForField(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8, field_schema: Schema) !bool {
    const item_schema = arrayChildSchema(field_schema) orelse return false;
    if (!try self.canGenerateNamedArrayItemType(item_schema)) return false;
    if (isNullableSchema(field_schema)) try self.buffer.appendSlice(self.allocator, "?");
    const type_name = try self.arrayFieldItemTypeNameAlloc(owner_name, field_name);
    defer self.allocator.free(type_name);
    try self.buffer.appendSlice(self.allocator, "[]const ");
    try self.appendIdentifier(type_name);
    return true;
}

pub fn appendNamedFieldTypeForField(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8, field_schema: Schema) !bool {
    if (arrayChildSchema(field_schema) != null) return false;
    if (!try self.canGenerateNamedFieldType(field_schema)) return false;
    if (isNullableSchema(field_schema)) try self.buffer.appendSlice(self.allocator, "?");
    const type_name = try self.fieldTypeNameAlloc(owner_name, field_name);
    defer self.allocator.free(type_name);
    try self.appendIdentifier(type_name);
    return true;
}

pub fn generateStructFields(self: *UnifiedModelGenerator, owner_name: []const u8, properties: std.StringHashMap(Schema), required: ?[][]const u8) !void {
    var prop_iterator = properties.iterator();
    while (prop_iterator.next()) |entry| {
        const field_name = entry.key_ptr.*;
        const field_schema = entry.value_ptr.*;
        const is_required = self.isFieldRequired(field_name, required);
        try self.generateStructField(owner_name, field_name, field_schema, is_required);
    }
}

pub fn generateStructField(self: *UnifiedModelGenerator, owner_name: []const u8, field_name: []const u8, field_schema: Schema, is_required: bool) !void {
    try self.buffer.appendSlice(self.allocator, "    ");
    try self.appendFieldIdentifier(field_name);
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

pub fn generateJsonStringify(self: *UnifiedModelGenerator, properties: std.StringHashMap(Schema), required: ?[][]const u8) !void {
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
            try self.appendFieldIdentifier(field_name);
            try self.buffer.appendSlice(self.allocator, ");\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "        if (self.");
            try self.appendFieldIdentifier(field_name);
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

pub fn appendZigType(self: *UnifiedModelGenerator, schema: Schema) !void {
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
        if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
        if (std.mem.lastIndexOf(u8, ref, "/")) |last_slash| {
            try self.appendIdentifier(ref[last_slash + 1 ..]);
            return;
        }
        try self.buffer.appendSlice(self.allocator, "[]const u8");
        return;
    }

    if (schema.type) |schema_type| {
        switch (schema_type) {
            .string => {
                if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
                try self.buffer.appendSlice(self.allocator, "[]const u8");
            },
            .integer => {
                if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
                try self.buffer.appendSlice(self.allocator, "i64");
            },
            .number => {
                if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
                try self.buffer.appendSlice(self.allocator, "f64");
            },
            .boolean => {
                if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
                try self.buffer.appendSlice(self.allocator, "bool");
            },
            .array => {
                if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
                if (schema.items) |items| {
                    try self.buffer.appendSlice(self.allocator, "[]const ");
                    try self.appendArrayItemType(items.*);
                } else {
                    try self.buffer.appendSlice(self.allocator, "[]const std.json.Value");
                }
            },
            .object, .reference => {
                if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
                try self.buffer.appendSlice(self.allocator, "std.json.Value");
            },
            .null => try self.buffer.appendSlice(self.allocator, "void"),
        }
        return;
    }

    if (isNullableSchema(schema)) try self.buffer.appendSlice(self.allocator, "?");
    try self.buffer.appendSlice(self.allocator, "std.json.Value");
}

pub fn appendArrayItemType(self: *UnifiedModelGenerator, schema: Schema) !void {
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

pub fn isFieldRequired(self: *UnifiedModelGenerator, field_name: []const u8, required: ?[][]const u8) bool {
    _ = self;
    if (required == null) return false;

    for (required.?) |req_field| {
        if (std.mem.eql(u8, field_name, req_field)) {
            return true;
        }
    }

    return false;
}
