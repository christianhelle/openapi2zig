const std = @import("std");

pub const Var = struct {
    name: []const u8,
    value: []const u8,
};

pub const TemplateError = error{ UnknownVariable, UnterminatedPlaceholder };

/// Replaces every `{{name}}` placeholder in `template` with the matching value
/// from `vars`. Carriage returns are dropped so templates checked out with CRLF
/// line endings still render identically everywhere.
pub fn expand(allocator: std.mem.Allocator, template: []const u8, vars: []const Var) (TemplateError || std.mem.Allocator.Error)![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        const c = template[i];
        if (c == '\r') {
            i += 1;
            continue;
        }
        if (c == '{' and i + 1 < template.len and template[i + 1] == '{') {
            const end = std.mem.indexOfPos(u8, template, i + 2, "}}") orelse return error.UnterminatedPlaceholder;
            const name = std.mem.trim(u8, template[i + 2 .. end], " ");
            const value = lookup(vars, name) orelse return error.UnknownVariable;
            try out.appendSlice(allocator, value);
            i = end + 2;
            continue;
        }
        try out.append(allocator, c);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn lookup(vars: []const Var, name: []const u8) ?[]const u8 {
    for (vars) |v| {
        if (std.mem.eql(u8, v.name, name)) return v.value;
    }
    return null;
}
