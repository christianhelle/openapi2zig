const std = @import("std");

/// Normalizes generated Zig source so that it is already `zig fmt` clean.
///
/// Without this, the generator emits source that `zig fmt` immediately rewrites
/// (trailing whitespace on empty doc-comment lines, runs of blank lines, extra
/// trailing newlines). The on-disk file then no longer matches the code the
/// header checksum describes, which defeats the "skip writing unchanged files"
/// check and causes the output to be rewritten on every run.
///
/// Callers must compute the header checksum over the normalized code so the
/// checksum always describes exactly what is written to disk.
pub fn normalize(allocator: std.mem.Allocator, code: []const u8) ![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    var pending_blank_lines: usize = 0;
    var wrote_any_line = false;

    var lines = std.mem.splitScalar(u8, code, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, " \t\r");

        if (line.len == 0) {
            // Blank lines are buffered so runs of them collapse into one, and
            // so trailing blank lines are dropped entirely.
            pending_blank_lines += 1;
            continue;
        }

        if (wrote_any_line and pending_blank_lines > 0 and !startsBlock(line)) {
            try buffer.append(allocator, '\n');
        }
        pending_blank_lines = 0;

        try buffer.appendSlice(allocator, line);
        try buffer.append(allocator, '\n');
        wrote_any_line = true;
    }

    return try buffer.toOwnedSlice(allocator);
}

/// `zig fmt` removes blank lines that directly precede a closing delimiter, so
/// a line starting one must not be preceded by a blank line.
fn startsBlock(line: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    if (trimmed.len == 0) return false;
    return switch (trimmed[0]) {
        '}', ')', ']' => true,
        else => false,
    };
}
