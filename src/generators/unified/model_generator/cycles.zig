const std = @import("std");
const Schema = @import("../../../models/common/document.zig").Schema;
const UnifiedModelGenerator = @import("../model_generator.zig").UnifiedModelGenerator;

const State = enum(u8) { visiting, done };

/// Finds the by-value reference fields that close a cycle between model types.
///
/// A Zig struct cannot contain itself, directly or through other structs, so
/// one field of every cycle has to be a pointer. Graph-style descriptions are
/// full of such cycles (`user.drive.list.lastModifiedByUser`). The walk visits
/// schemas and fields in name order, so the chosen fields are stable.
///
/// The result holds `"{type name}\x00{field name}"` keys, using the Zig names
/// that the declarations are emitted under.
pub fn collectPointerFields(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
    self.clearPointerFields();

    const keys = try self.allocator.alloc([]const u8, schemas.count());
    defer self.allocator.free(keys);
    var index: usize = 0;
    var key_iterator = schemas.keyIterator();
    while (key_iterator.next()) |key| : (index += 1) keys[index] = key.*;
    std.mem.sort([]const u8, keys, {}, lessThan);

    var states: std.StringHashMapUnmanaged(State) = .empty;
    defer states.deinit(self.allocator);

    for (keys) |key| {
        if (states.contains(key)) continue;
        try visit(self, schemas, &states, key);
    }
}

fn visit(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema), states: *std.StringHashMapUnmanaged(State), name: []const u8) std.mem.Allocator.Error!void {
    try states.put(self.allocator, name, .visiting);
    defer states.put(self.allocator, name, .done) catch {};

    const schema = schemas.get(name) orelse return;
    const properties = schema.properties orelse return;

    const fields = try self.allocator.alloc([]const u8, properties.count());
    defer self.allocator.free(fields);
    var index: usize = 0;
    var field_iterator = properties.keyIterator();
    while (field_iterator.next()) |field| : (index += 1) fields[index] = field.*;
    std.mem.sort([]const u8, fields, {}, lessThan);

    for (fields) |field| {
        const property = properties.get(field).?;
        const ref = property.ref orelse continue;
        const target = refTarget(ref);
        if (!schemas.contains(target)) continue;

        if (states.get(target)) |state| {
            if (state == .visiting) try self.markPointerField(name, field);
            continue;
        }
        try visit(self, schemas, states, target);
    }
}

fn refTarget(ref: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, ref, '/')) |slash| return ref[slash + 1 ..];
    return ref;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
