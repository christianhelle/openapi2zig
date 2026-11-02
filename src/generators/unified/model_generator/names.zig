const std = @import("std");
const Generator = @import("../model_generator.zig").UnifiedModelGenerator;

pub const HelperKind = enum { field, array_field_item, variant, array_item };

/// Component names are never renamed: every $ref continues to use its original
/// spelling. Inline declarations get a separate name for each logical location,
/// shared by declaration emission and every use of that helper type.
pub fn helperNameAlloc(self: *Generator, owner: []const u8, kind: HelperKind, detail: []const u8, suggested: []const u8) ![]const u8 {
    const key = try std.fmt.allocPrint(self.allocator, "{d}:{s}:{s}:{s}", .{ owner.len, owner, @tagName(kind), detail });
    defer self.allocator.free(key);
    if (self.helper_names.get(key)) |existing| return self.allocator.dupe(u8, existing);
    var suffix: usize = 1;
    var name = try self.allocator.dupe(u8, suggested);
    defer self.allocator.free(name);
    while (self.declaration_names.contains(name)) {
        const next = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ suggested, suffix + 1 });
        self.allocator.free(name);
        name = next;
        suffix += 1;
    }
    try self.helper_names.ensureUnusedCapacity(1);
    try self.declaration_names.ensureUnusedCapacity(1);
    const owned_key = try self.allocator.dupe(u8, key);
    errdefer self.allocator.free(owned_key);
    const owned_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(owned_name);
    const result = try self.allocator.dupe(u8, name);
    self.declaration_names.putAssumeCapacity(owned_name, {});
    self.helper_names.putAssumeCapacity(owned_key, owned_name);
    return result;
}

pub fn arrayItemTypeNameAlloc(self: *Generator, owner: []const u8) ![]const u8 {
    const suggested = try std.fmt.allocPrint(self.allocator, "{s}Item", .{owner});
    defer self.allocator.free(suggested);
    return helperNameAlloc(self, owner, .array_item, "", suggested);
}

pub fn clearNames(self: *Generator) void {
    // declaration_names borrows component names and helper_names' values.
    self.declaration_names.clearRetainingCapacity();
    var iterator = self.helper_names.iterator();
    while (iterator.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }
    self.helper_names.clearRetainingCapacity();
}
