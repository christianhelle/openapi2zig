const std = @import("std");
const Schema = @import("../../models/common/document.zig").Schema;
const ident = @import("ident_utils.zig");

/// How component schema names become Zig type names.
pub const Mode = enum {
    /// Names are used as written, so `microsoft.graph.user` is
    /// `@"microsoft.graph.user"`.
    raw,
    /// Dotted names lose their shared prefix and become PascalCase:
    /// `microsoft.graph.user` is `User` and `microsoft.graph.security.alert` is
    /// `SecurityAlert`, which is also reachable as `security.Alert`.
    namespaced,

    pub fn fromString(value: []const u8) ?Mode {
        if (std.mem.eql(u8, value, "raw")) return .raw;
        if (std.mem.eql(u8, value, "namespaced")) return .namespaced;
        return null;
    }
};

const Entry = struct {
    /// Snake case namespace segments, outermost first. Empty for top-level types.
    namespace: []const []const u8,
    /// The type's name inside its namespace.
    leaf: []const u8,
};

/// Maps component schema names to the Zig names the generators emit.
///
/// Every type is declared once under its flat PascalCase name, so references
/// never depend on namespace nesting. `appendNamespaceAliases` adds the nested
/// `security.Alert` style access on top.
pub const ModelNameMap = struct {
    arena: std.heap.ArenaAllocator,
    flat: std.StringHashMapUnmanaged([]const u8) = .empty,
    entries: std.StringHashMapUnmanaged(Entry) = .empty,
    /// Every emitted flat type name, for constant-time conflict checks.
    declared: std.StringHashMapUnmanaged(void) = .empty,

    pub fn init(allocator: std.mem.Allocator, schemas: std.StringHashMap(Schema)) !ModelNameMap {
        var self: ModelNameMap = .{ .arena = std.heap.ArenaAllocator.init(allocator) };
        errdefer self.deinit();
        try self.build(allocator, schemas);
        return self;
    }

    pub fn deinit(self: *ModelNameMap) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// The Zig name for a schema, or `raw` itself when the schema is unknown.
    pub fn flatName(self: *const ModelNameMap, raw: []const u8) []const u8 {
        return self.flat.get(raw) orelse raw;
    }

    fn build(self: *ModelNameMap, tmp: std.mem.Allocator, schemas: std.StringHashMap(Schema)) !void {
        const arena = self.arena.allocator();

        const keys = try tmp.alloc([]const u8, schemas.count());
        defer tmp.free(keys);
        var index: usize = 0;
        var key_iterator = schemas.keyIterator();
        while (key_iterator.next()) |key| : (index += 1) keys[index] = key.*;
        std.mem.sort([]const u8, keys, {}, lessThan);

        const strip = commonSegmentPrefix(keys);

        var used: std.StringHashMapUnmanaged(void) = .empty;
        defer used.deinit(tmp);
        var used_leaves: std.StringHashMapUnmanaged(void) = .empty;
        defer used_leaves.deinit(tmp);

        for (keys) |raw| {
            const segments = try splitSegments(tmp, raw);
            defer tmp.free(segments);
            const kept = if (segments.len > strip) segments[strip..] else segments[segments.len - 1 ..];

            var flat_name: std.ArrayList(u8) = .empty;
            defer flat_name.deinit(tmp);
            for (kept) |segment| try appendPascal(tmp, &flat_name, segment);
            if (flat_name.items.len == 0) try flat_name.appendSlice(tmp, "Schema");

            // Collisions get a suffix, deterministically because keys are sorted.
            while (used.contains(flat_name.items)) try flat_name.append(tmp, '_');
            const flat_copy = try arena.dupe(u8, flat_name.items);
            try used.put(tmp, flat_copy, {});

            var leaf: std.ArrayList(u8) = .empty;
            defer leaf.deinit(tmp);
            try appendPascal(tmp, &leaf, kept[kept.len - 1]);
            if (leaf.items.len == 0) try leaf.appendSlice(tmp, "Schema");

            const namespace = try arena.alloc([]const u8, kept.len - 1);
            var namespace_key: std.ArrayList(u8) = .empty;
            defer namespace_key.deinit(tmp);
            for (kept[0 .. kept.len - 1], 0..) |segment, i| {
                var snake: std.ArrayList(u8) = .empty;
                defer snake.deinit(tmp);
                try appendSnake(tmp, &snake, segment);
                // Namespaces live next to `root` and `std` in models.zig.
                if (std.mem.eql(u8, snake.items, "root") or std.mem.eql(u8, snake.items, "std") or std.mem.eql(u8, snake.items, "builtin")) {
                    try snake.append(tmp, '_');
                }
                namespace[i] = try arena.dupe(u8, snake.items);
                try namespace_key.appendSlice(tmp, snake.items);
                try namespace_key.append(tmp, '.');
            }

            // Two types with the same leaf in one namespace keep distinct aliases.
            while (true) {
                const probe = try std.fmt.allocPrint(tmp, "{s}{s}", .{ namespace_key.items, leaf.items });
                defer tmp.free(probe);
                if (!used_leaves.contains(probe)) {
                    try used_leaves.put(tmp, try arena.dupe(u8, probe), {});
                    break;
                }
                try leaf.append(tmp, '_');
            }

            const raw_copy = try arena.dupe(u8, raw);
            try self.flat.put(arena, raw_copy, flat_copy);
            try self.declared.put(arena, flat_copy, {});
            try self.entries.put(arena, raw_copy, .{ .namespace = namespace, .leaf = try arena.dupe(u8, leaf.items) });
        }
    }

    /// Appends `pub const security = struct { pub const Alert = SecurityAlert; };`
    /// style declarations for every type that lives in a namespace.
    pub fn appendNamespaceAliases(self: *const ModelNameMap, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        const raws = try allocator.alloc([]const u8, self.entries.count());
        defer allocator.free(raws);
        var index: usize = 0;
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.namespace.len == 0) continue;
            raws[index] = entry.key_ptr.*;
            index += 1;
        }
        const namespaced = raws[0..index];
        if (namespaced.len == 0) return;

        // Sort by namespace path, then leaf, so each struct is emitted once.
        const context: SortContext = .{ .map = self };
        std.mem.sort([]const u8, namespaced, context, SortContext.lessThan);

        var open: std.ArrayList([]const u8) = .empty;
        defer open.deinit(allocator);
        try out.appendSlice(allocator, "const root = @This();\n");
        for (namespaced) |raw| {
            const entry = self.entries.get(raw).?;
            // Close namespaces that this entry is no longer inside.
            var common: usize = 0;
            while (common < open.items.len and common < entry.namespace.len and
                std.mem.eql(u8, open.items[common], entry.namespace[common])) common += 1;
            while (open.items.len > common) {
                _ = open.pop();
                try out.appendSlice(allocator, "};\n");
            }
            for (entry.namespace[common..]) |segment| {
                try out.appendSlice(allocator, "pub const ");
                try ident.appendIdentifier(out, allocator, segment);
                try out.appendSlice(allocator, " = struct {\n");
                try open.append(allocator, segment);
            }
            try out.appendSlice(allocator, "pub const ");
            try ident.appendIdentifier(out, allocator, entry.leaf);
            try out.appendSlice(allocator, " = ");
            // Nested structs cannot see sibling declarations of the file by
            // bare name once a namespace reuses it, so go through the root.
            try out.appendSlice(allocator, "root.");
            try ident.appendIdentifier(out, allocator, self.flatName(raw));
            try out.appendSlice(allocator, ";\n");
        }
        while (open.items.len > 0) {
            _ = open.pop();
            try out.appendSlice(allocator, "};\n");
        }
    }

    const SortContext = struct {
        map: *const ModelNameMap,

        fn lessThan(context: SortContext, a: []const u8, b: []const u8) bool {
            const ea = context.map.entries.get(a).?;
            const eb = context.map.entries.get(b).?;
            const shared = @min(ea.namespace.len, eb.namespace.len);
            for (0..shared) |i| {
                switch (std.mem.order(u8, ea.namespace[i], eb.namespace[i])) {
                    .lt => return true,
                    .gt => return false,
                    .eq => {},
                }
            }
            if (ea.namespace.len != eb.namespace.len) return ea.namespace.len < eb.namespace.len;
            return std.mem.lessThan(u8, ea.leaf, eb.leaf);
        }
    };
};

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn splitSegments(allocator: std.mem.Allocator, name: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);
    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |segment| {
        if (segment.len > 0) try list.append(allocator, segment);
    }
    if (list.items.len == 0) try list.append(allocator, name);
    return list.toOwnedSlice(allocator);
}

/// The number of leading dot-separated segments shared by every dotted name,
/// never counting a name's last segment.
fn commonSegmentPrefix(sorted_keys: []const []const u8) usize {
    var prefix: ?[]const u8 = null; // the shared prefix, as text without a trailing dot
    var shared_segments: usize = 0;
    for (sorted_keys) |key| {
        if (std.mem.indexOfScalar(u8, key, '.') == null) continue;
        // Only the segments before the last one may be stripped.
        const last_dot = std.mem.lastIndexOfScalar(u8, key, '.').?;
        const head = key[0..last_dot];
        if (prefix == null) {
            prefix = head;
            shared_segments = std.mem.count(u8, head, ".") + 1;
            continue;
        }
        var current = prefix.?;
        // Shrink the prefix until `head` starts with it on a segment boundary.
        while (current.len > 0 and !startsWithSegments(head, current)) {
            const cut = std.mem.lastIndexOfScalar(u8, current, '.') orelse 0;
            current = current[0..cut];
        }
        prefix = current;
        shared_segments = if (current.len == 0) 0 else std.mem.count(u8, current, ".") + 1;
        if (shared_segments == 0) return 0;
    }
    return shared_segments;
}

fn startsWithSegments(text: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, text, prefix)) return false;
    return text.len == prefix.len or text[prefix.len] == '.';
}

fn appendPascal(allocator: std.mem.Allocator, out: *std.ArrayList(u8), segment: []const u8) !void {
    var upper_next = true;
    for (segment) |c| {
        if (!std.ascii.isAlphanumeric(c)) {
            upper_next = true;
            continue;
        }
        try out.append(allocator, if (upper_next) std.ascii.toUpper(c) else c);
        upper_next = false;
    }
}

fn appendSnake(allocator: std.mem.Allocator, out: *std.ArrayList(u8), segment: []const u8) !void {
    for (segment, 0..) |c, i| {
        if (!std.ascii.isAlphanumeric(c)) {
            if (out.items.len > 0 and out.items[out.items.len - 1] != '_') try out.append(allocator, '_');
            continue;
        }
        if (std.ascii.isUpper(c) and i > 0 and out.items.len > 0 and out.items[out.items.len - 1] != '_') {
            const prev = segment[i - 1];
            const next_lower = i + 1 < segment.len and std.ascii.isLower(segment[i + 1]);
            if (std.ascii.isLower(prev) or std.ascii.isDigit(prev) or (std.ascii.isUpper(prev) and next_lower)) {
                try out.append(allocator, '_');
            }
        }
        try out.append(allocator, std.ascii.toLower(c));
    }
}
