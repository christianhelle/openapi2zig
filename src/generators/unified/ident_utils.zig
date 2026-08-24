const std = @import("std");

pub fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

pub fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn isReservedIdent(name: []const u8) bool {
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

/// Keywords that cannot be used bare as struct field names. Primitive type
/// names such as `type`, `bool`, and `void` are valid field names in Zig and
/// `zig fmt` rewrites their escaped form back to the bare keyword.
pub fn isReservedFieldIdent(name: []const u8) bool {
    const reserved_field = [_][]const u8{
        "addrspace",   "align",       "allowzero", "and",      "anyframe", "anytype", "asm",         "break",
        "callconv",    "catch",       "comptime",  "const",    "continue", "defer",   "else",        "enum",
        "errdefer",    "error",       "export",    "extern",   "fn",       "for",     "if",          "inline",
        "linksection", "noalias",     "nosuspend", "opaque",   "or",       "orelse",  "packed",      "pub",
        "resume",      "return",      "struct",    "suspend",  "switch",   "test",    "threadlocal", "try",
        "union",       "unreachable", "var",       "volatile", "while",
    };
    for (reserved_field) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

pub fn isBareIdentifier(name: []const u8) bool {
    if (name.len == 0 or !isIdentStart(name[0]) or isReservedIdent(name)) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return true;
}

pub fn isBareFieldIdentifier(name: []const u8) bool {
    if (name.len == 0 or !isIdentStart(name[0]) or isReservedFieldIdent(name)) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return true;
}

pub fn appendIdentifier(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8) !void {
    try appendIdentifierAs(buffer, allocator, name, isBareIdentifier);
}

pub fn appendFieldIdentifier(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8) !void {
    try appendIdentifierAs(buffer, allocator, name, isBareFieldIdentifier);
}

fn neverBare(_: []const u8) bool {
    return false;
}

/// Append `name` as an escaped identifier in the form `@"..."`, quoting even
/// when the name is a valid bare identifier. Embedded backslashes, quotes, and
/// control characters are escaped so the output is always valid Zig.
pub fn appendEscapedIdentifier(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8) !void {
    try appendIdentifierAs(buffer, allocator, name, neverBare);
}

fn appendIdentifierAs(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8, comptime is_bare: fn ([]const u8) bool) !void {
    if (is_bare(name)) {
        try buffer.appendSlice(allocator, name);
        return;
    }
    try buffer.appendSlice(allocator, "@\"");
    for (name) |c| {
        switch (c) {
            '\\', '"' => {
                try buffer.append(allocator, '\\');
                try buffer.append(allocator, c);
            },
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            else => {
                if (std.ascii.isControl(c)) {
                    const hex = "0123456789abcdef";
                    try buffer.appendSlice(allocator, "\\x");
                    try buffer.append(allocator, hex[c >> 4]);
                    try buffer.append(allocator, hex[c & 0x0f]);
                } else {
                    try buffer.append(allocator, c);
                }
            },
        }
    }
    try buffer.appendSlice(allocator, "\"");
}

test "isIdentStart" {
    try std.testing.expect(isIdentStart('a'));
    try std.testing.expect(isIdentStart('Z'));
    try std.testing.expect(isIdentStart('_'));
    try std.testing.expect(!isIdentStart('0'));
    try std.testing.expect(!isIdentStart('-'));
}

test "isIdentContinue" {
    try std.testing.expect(isIdentContinue('a'));
    try std.testing.expect(isIdentContinue('Z'));
    try std.testing.expect(isIdentContinue('_'));
    try std.testing.expect(isIdentContinue('0'));
    try std.testing.expect(!isIdentContinue('-'));
}

test "isReservedIdent" {
    try std.testing.expect(isReservedIdent("if"));
    try std.testing.expect(isReservedIdent("return"));
    try std.testing.expect(isReservedIdent("struct"));
    try std.testing.expect(isReservedIdent("type"));
    try std.testing.expect(!isReservedIdent("foo"));
    try std.testing.expect(!isReservedIdent(""));
}

test "isReservedFieldIdent" {
    try std.testing.expect(isReservedFieldIdent("if"));
    try std.testing.expect(isReservedFieldIdent("return"));
    try std.testing.expect(isReservedFieldIdent("struct"));
    try std.testing.expect(!isReservedFieldIdent("type"));
    try std.testing.expect(!isReservedFieldIdent("foo"));
    try std.testing.expect(!isReservedFieldIdent(""));
}

test "isBareIdentifier" {
    try std.testing.expect(isBareIdentifier("foo"));
    try std.testing.expect(isBareIdentifier("_bar"));
    try std.testing.expect(!isBareIdentifier(""));
    try std.testing.expect(!isBareIdentifier("0foo"));
    try std.testing.expect(!isBareIdentifier("if"));
}

test "isBareFieldIdentifier" {
    try std.testing.expect(isBareFieldIdentifier("foo"));
    try std.testing.expect(isBareFieldIdentifier("type"));
    try std.testing.expect(!isBareFieldIdentifier(""));
    try std.testing.expect(!isBareFieldIdentifier("0foo"));
    try std.testing.expect(!isBareFieldIdentifier("if"));
}

test "appendIdentifier" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try appendIdentifier(&buf, std.testing.allocator, "simple");
    try std.testing.expectEqualStrings("simple", buf.items);
    buf.clearRetainingCapacity();
    try appendIdentifier(&buf, std.testing.allocator, "has space");
    try std.testing.expectEqualStrings("@\"has space\"", buf.items);
    buf.clearRetainingCapacity();
    try appendIdentifier(&buf, std.testing.allocator, "quote\"here");
    try std.testing.expectEqualStrings("@\"quote\\\"here\"", buf.items);
    buf.clearRetainingCapacity();
    try appendIdentifier(&buf, std.testing.allocator, "type");
    try std.testing.expectEqualStrings("@\"type\"", buf.items);
}

test "appendFieldIdentifier" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try appendFieldIdentifier(&buf, std.testing.allocator, "type");
    try std.testing.expectEqualStrings("type", buf.items);
    buf.clearRetainingCapacity();
    try appendFieldIdentifier(&buf, std.testing.allocator, "if");
    try std.testing.expectEqualStrings("@\"if\"", buf.items);
    buf.clearRetainingCapacity();
    try appendFieldIdentifier(&buf, std.testing.allocator, "has space");
    try std.testing.expectEqualStrings("@\"has space\"", buf.items);
}

test "appendEscapedIdentifier" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try appendEscapedIdentifier(&buf, std.testing.allocator, "simple");
    try std.testing.expectEqualStrings("@\"simple\"", buf.items);
    buf.clearRetainingCapacity();
    try appendEscapedIdentifier(&buf, std.testing.allocator, "quote\"here");
    try std.testing.expectEqualStrings("@\"quote\\\"here\"", buf.items);
    buf.clearRetainingCapacity();
    try appendEscapedIdentifier(&buf, std.testing.allocator, "back\\slash");
    try std.testing.expectEqualStrings("@\"back\\\\slash\"", buf.items);
}

test "appendEscapedIdentifier escapes ASCII control characters" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try appendEscapedIdentifier(&buf, std.testing.allocator, &.{ 0x01 });
    try std.testing.expectEqualStrings("@\"\\x01\"", buf.items);
    buf.clearRetainingCapacity();
    try appendEscapedIdentifier(&buf, std.testing.allocator, &.{ 0x7f });
    try std.testing.expectEqualStrings("@\"\\x7f\"", buf.items);
}
