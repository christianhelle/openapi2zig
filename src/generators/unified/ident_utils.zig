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
