const std = @import("std");

pub fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

pub fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn isReservedIdent(name: []const u8) bool {
    const reserved = [_][]const u8{
        "addrspace", "align",    "allowzero", "and",    "anyerror",    "anyframe", "anyopaque",      "anytype",
        "asm",       "async",    "await",     "bool",   "break",       "callconv", "catch",          "comptime",
        "const",     "continue", "defer",     "else",   "enum",        "errdefer", "error",          "export",
        "extern",    "false",    "fn",        "for",    "if",          "inline",   "isize",          "linksection",
        "noalias",   "noreturn", "nosuspend", "null",   "opaque",      "or",       "orelse",         "packed",
        "pub",       "resume",   "return",    "struct", "suspend",     "switch",   "test",           "threadlocal",
        "true",      "try",      "undefined", "union",  "unreachable", "usize",    "usingnamespace", "var",
        "void",      "volatile", "while",
    };
    for (reserved) |word| {
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

pub fn appendIdentifier(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8) !void {
    if (isBareIdentifier(name)) {
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
            else => try buffer.append(allocator, c),
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
    try std.testing.expect(!isReservedIdent("foo"));
    try std.testing.expect(!isReservedIdent(""));
}

test "isBareIdentifier" {
    try std.testing.expect(isBareIdentifier("foo"));
    try std.testing.expect(isBareIdentifier("_bar"));
    try std.testing.expect(!isBareIdentifier(""));
    try std.testing.expect(!isBareIdentifier("0foo"));
    try std.testing.expect(!isBareIdentifier("if"));
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
}
