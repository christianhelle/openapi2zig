//! Escaping for text from the SDK config or the OpenAPI description that ends
//! up inside generated Zig source.

const std = @import("std");

/// The contents of a Zig string literal for `text`: quotes, backslashes and
/// control characters are escaped, so the text can never end the literal.
pub fn escapeString(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (text) |c| switch (c) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0...8, 11, 12, 14...31, 127 => try out.print(allocator, "\\x{x:0>2}", .{c}),
        else => try out.append(allocator, c),
    };
    return out.toOwnedSlice(allocator);
}

/// `text` for the body of a `//!` comment. Every line after the first gets the
/// `//!` prefix, so a multi-line description stays a comment.
pub fn docComment(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (text) |c| switch (c) {
        '\r' => {},
        '\n' => try out.appendSlice(allocator, "\n//! "),
        // Zig rejects tabs and other control bytes inside comments.
        '\t' => try out.appendSlice(allocator, "    "),
        0...8, 11, 12, 14...31, 127 => try out.append(allocator, ' '),
        else => try out.append(allocator, c),
    };
    return out.toOwnedSlice(allocator);
}
