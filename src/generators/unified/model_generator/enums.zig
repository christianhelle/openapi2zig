const std = @import("std");
const Schema = @import("../../../models/common/document.zig").Schema;
const UnifiedModelGenerator = @import("../model_generator.zig").UnifiedModelGenerator;

/// The string values of an enum schema that can become a Zig enum, or null when
/// it has to stay a plain string: not a string enum, empty, a duplicate, an
/// empty member name, or a value that clashes with the `_unknown` member.
pub fn enumMembers(schema: Schema) ?[]const std.json.Value {
    if (schema.type != .string or schema.ref != null) return null;
    const values = schema.enum_values orelse return null;
    if (values.len == 0) return null;
    for (values, 0..) |value, i| {
        const text = switch (value) {
            .string => |s| s,
            else => return null,
        };
        if (text.len == 0 or std.mem.eql(u8, text, "_unknown")) return null;
        for (text) |c| if (c < 0x20 or c == 0x7f or c == '"' or c == '\\') return null;
        for (values[0..i]) |earlier| {
            if (std.mem.eql(u8, earlier.string, text)) return null;
        }
    }
    return values;
}

/// Emits `pub const Name = enum { a, b, _unknown, ... }` with JSON support.
/// Values the SDK does not know parse as `_unknown` instead of failing, so a
/// server that adds a value does not break existing programs.
pub fn generateStringEnum(self: *UnifiedModelGenerator, name: []const u8, members: []const std.json.Value) !void {
    try self.buffer.appendSlice(self.allocator, "pub const ");
    try self.appendIdentifier(name);
    try self.buffer.appendSlice(self.allocator, " = enum {\n");
    for (members) |member| {
        try self.buffer.appendSlice(self.allocator, "    ");
        try self.appendFieldIdentifier(member.string);
        try self.buffer.appendSlice(self.allocator, ",\n");
    }
    try self.buffer.appendSlice(self.allocator,
        \\    /// A value this version of the SDK does not know.
        \\    _unknown,
        \\
        \\    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
        \\        const text = try std.json.innerParse([]const u8, allocator, source, options);
        \\        return fromWire(text);
        \\    }
        \\
        \\    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
        \\        _ = allocator;
        \\        _ = options;
        \\        if (source != .string) return error.UnexpectedToken;
        \\        return fromWire(source.string);
        \\    }
        \\
        \\    /// An unknown value has no wire form, so it is written as `null`.
        \\    pub fn jsonStringify(self: @This(), jw: anytype) !void {
        \\        if (self == ._unknown) return jw.write(null);
        \\        try jw.write(@tagName(self));
        \\    }
        \\
        \\    fn fromWire(text: []const u8) @This() {
        \\        return std.meta.stringToEnum(@This(), text) orelse ._unknown;
        \\    }
        \\};
        \\
        \\
    );
}
