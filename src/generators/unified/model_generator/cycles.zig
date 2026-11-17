const std = @import("std");
const Schema = @import("../../../models/common/document.zig").Schema;
const UnifiedModelGenerator = @import("../model_generator.zig").UnifiedModelGenerator;

const State = enum(u8) { visiting, done };

/// One step of the walk: `owner` contains `target` by value. `field` is the
/// property that holds it, or null when `owner` is a union with a variant of
/// that type (a union cannot hide a variant behind a pointer, so the pointer
/// goes on a property earlier in the cycle).
const Edge = struct {
    owner: []const u8,
    field: ?[]const u8,
    target: []const u8,
};

/// Finds the by-value reference fields that close a cycle between model types.
///
/// A Zig struct cannot contain itself, directly or through other structs or
/// unions, so one property of every cycle has to be a pointer. Graph-style
/// descriptions are full of such cycles (`user.drive.list.lastModifiedByUser`).
/// The walk visits schemas and fields in name order, so the chosen fields are
/// stable.
///
/// The result holds `"{type name}\x00{field name}"` keys, using the Zig names
/// that the declarations are emitted under.
pub fn collectPointerFields(self: *UnifiedModelGenerator, schemas: std.StringHashMap(Schema)) !void {
    self.clearPointerFields();

    const keys = try sortedKeys(self.allocator, schemas);
    defer self.allocator.free(keys);

    var states: std.StringHashMapUnmanaged(State) = .empty;
    defer states.deinit(self.allocator);
    var path: std.ArrayList(Edge) = .empty;
    defer path.deinit(self.allocator);

    // Moving a cut to another edge can leave a cycle behind that a finished
    // node already reported, so walk again, skipping the fields chosen so far,
    // until a whole pass finds nothing new.
    var round: usize = 0;
    while (round < 64) : (round += 1) {
        const before = self.pointer_fields.count();
        states.clearRetainingCapacity();
        path.clearRetainingCapacity();
        for (keys) |key| {
            if (states.contains(key)) continue;
            try visit(self, schemas, &states, &path, key);
        }
        if (self.pointer_fields.count() == before) break;
    }
}

fn visit(
    self: *UnifiedModelGenerator,
    schemas: std.StringHashMap(Schema),
    states: *std.StringHashMapUnmanaged(State),
    path: *std.ArrayList(Edge),
    name: []const u8,
) std.mem.Allocator.Error!void {
    try states.put(self.allocator, name, .visiting);
    defer states.put(self.allocator, name, .done) catch {};

    const schema = schemas.get(name) orelse return;

    if (schema.properties) |properties| {
        const fields = try sortedKeysOf(self.allocator, properties);
        defer self.allocator.free(fields);
        for (fields) |field| {
            const property = properties.get(field).?;
            // A field that is already a pointer no longer contains its target.
            if (self.isPointerField(self.typeName(name), field)) continue;
            const ref = property.ref orelse continue;
            try follow(self, schemas, states, path, .{ .owner = name, .field = field, .target = refTarget(ref) });
        }
    }

    // A component that is only a reference is an alias of its target.
    if (schema.type == .reference) {
        if (schema.ref) |ref| try follow(self, schemas, states, path, .{ .owner = name, .field = null, .target = refTarget(ref) });
    }

    // A union holds one of its variants by value.
    for ([_]?[]Schema{ schema.one_of, schema.any_of }) |maybe_variants| {
        const variants = maybe_variants orelse continue;
        for (variants) |variant| {
            const ref = variant.ref orelse continue;
            try follow(self, schemas, states, path, .{ .owner = name, .field = null, .target = refTarget(ref) });
        }
    }
}

fn follow(
    self: *UnifiedModelGenerator,
    schemas: std.StringHashMap(Schema),
    states: *std.StringHashMapUnmanaged(State),
    path: *std.ArrayList(Edge),
    edge: Edge,
) std.mem.Allocator.Error!void {
    if (!schemas.contains(edge.target)) return;

    if (states.get(edge.target)) |state| {
        if (state == .visiting) try breakCycle(self, path.items, edge);
        return;
    }
    try path.append(self.allocator, edge);
    defer _ = path.pop();
    try visit(self, schemas, states, path, edge.target);
}

/// `closing` points back at a schema that is still being visited. Put the
/// pointer on the first property edge of the cycle: the cycle runs from where
/// `closing.target` appears on the path to `closing` itself.
fn breakCycle(self: *UnifiedModelGenerator, path: []const Edge, closing: Edge) !void {
    var start: usize = path.len;
    for (path, 0..) |edge, i| {
        if (std.mem.eql(u8, edge.owner, closing.target)) {
            start = i;
            break;
        }
    }
    // A self reference has no earlier edges: the cycle is just `closing`.
    if (start == path.len and !std.mem.eql(u8, closing.owner, closing.target)) return;

    // Prefer the edge that closes the cycle; when that is a union variant, use
    // the nearest property edge before it.
    if (closing.field) |field| return self.markPointerField(closing.owner, field);
    var i = path.len;
    while (i > start) {
        i -= 1;
        if (path[i].field) |field| return self.markPointerField(path[i].owner, field);
    }
}

fn refTarget(ref: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, ref, '/')) |slash| return ref[slash + 1 ..];
    return ref;
}

fn sortedKeys(allocator: std.mem.Allocator, map: std.StringHashMap(Schema)) ![][]const u8 {
    const keys = try allocator.alloc([]const u8, map.count());
    var index: usize = 0;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| : (index += 1) keys[index] = key.*;
    std.mem.sort([]const u8, keys, {}, lessThan);
    return keys;
}

fn sortedKeysOf(allocator: std.mem.Allocator, map: std.StringHashMap(Schema)) ![][]const u8 {
    return sortedKeys(allocator, map);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
