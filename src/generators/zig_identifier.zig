const std = @import("std");

const zig_keywords = [_][]const u8{
    "addrspace",
    "align",
    "allowzero",
    "and",
    "anyframe",
    "anytype",
    "asm",
    "async",
    "await",
    "break",
    "callconv",
    "catch",
    "comptime",
    "const",
    "continue",
    "defer",
    "else",
    "enum",
    "errdefer",
    "error",
    "export",
    "extern",
    "false",
    "fn",
    "for",
    "if",
    "inline",
    "linksection",
    "noalias",
    "noinline",
    "nosuspend",
    "null",
    "opaque",
    "or",
    "orelse",
    "packed",
    "pub",
    "resume",
    "return",
    "struct",
    "suspend",
    "switch",
    "test",
    "threadlocal",
    "true",
    "type",
    "try",
    "undefined",
    "union",
    "unreachable",
    "usingnamespace",
    "var",
    "volatile",
    "while",
};

pub fn append(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, identifier: []const u8) !void {
    if (isPlainIdentifier(identifier) and !isKeyword(identifier)) {
        try buffer.appendSlice(allocator, identifier);
        return;
    }

    try buffer.appendSlice(allocator, "@\"");
    for (identifier) |char| {
        try appendEscapedByte(buffer, allocator, char);
    }
    try buffer.append(allocator, '"');
}

fn isPlainIdentifier(identifier: []const u8) bool {
    if (identifier.len == 0) return false;
    if (!isIdentifierStart(identifier[0])) return false;

    for (identifier[1..]) |char| {
        if (!isIdentifierContinue(char)) return false;
    }

    return true;
}

fn isIdentifierStart(char: u8) bool {
    return char == '_' or (char >= 'A' and char <= 'Z') or (char >= 'a' and char <= 'z');
}

fn isIdentifierContinue(char: u8) bool {
    return isIdentifierStart(char) or (char >= '0' and char <= '9');
}

fn isKeyword(identifier: []const u8) bool {
    for (zig_keywords) |keyword| {
        if (std.mem.eql(u8, identifier, keyword)) {
            return true;
        }
    }

    return false;
}

fn appendEscapedByte(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, char: u8) !void {
    switch (char) {
        '\\' => try buffer.appendSlice(allocator, "\\\\"),
        '"' => try buffer.appendSlice(allocator, "\\\""),
        '\n' => try buffer.appendSlice(allocator, "\\n"),
        '\r' => try buffer.appendSlice(allocator, "\\r"),
        '\t' => try buffer.appendSlice(allocator, "\\t"),
        0...8, 11...12, 14...31, 127 => try appendHexEscape(buffer, allocator, char),
        else => try buffer.append(allocator, char),
    }
}

fn appendHexEscape(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, char: u8) !void {
    const hex_digits = "0123456789abcdef";
    const hi: usize = char >> 4;
    const lo: usize = char & 0x0f;
    const escaped = [_]u8{ '\\', 'x', hex_digits[hi], hex_digits[lo] };

    try buffer.appendSlice(allocator, &escaped);
}
