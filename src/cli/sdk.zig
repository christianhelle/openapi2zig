const std = @import("std");
const ident_utils = @import("../generators/unified/ident_utils.zig");

/// An SDK name becomes the Zig module name and the `build.zig.zon` package
/// name, so it must be a lowercase bare Zig identifier.
pub fn isValidSdkName(name: []const u8) bool {
    if (name.len == 0 or name.len > 32) return false;
    if (!(std.ascii.isLower(name[0]) or name[0] == '_')) return false;
    for (name) |c| {
        if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
    }
    return !ident_utils.isReservedIdent(name);
}
