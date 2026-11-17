const std = @import("std");
const document = @import("../../../models/common/document.zig");
const Operation = document.Operation;
const UnifiedDocument = document.UnifiedDocument;
const UnifiedApiGenerator = @import("../api_generator.zig").UnifiedApiGenerator;

/// An extra source file produced next to `client.zig`.
pub const SplitFile = struct {
    /// Path relative to the directory of `client.zig`, such as `client/users.zig`.
    name: []u8,
    content: []u8,
};

const TagFile = struct {
    file_name: []const u8,
    body: std.ArrayList(u8),
};

/// Emits every operation into a file of its tag (`client/<tag>.zig`) and leaves
/// `client.zig` with the client itself plus a re-export of each operation, so
/// that the public API is the same as for a single file.
///
/// The shared helpers of `client.zig` are made `pub` and aliased at the top of
/// each tag file, which lets the operation code stay exactly as it is.
pub fn generateApiClientSplit(self: *UnifiedApiGenerator, doc: UnifiedDocument) !void {
    try makeTopLevelDeclarationsPublic(self);
    const shared = try topLevelNames(self);
    defer {
        for (shared) |name| self.allocator.free(name);
        self.allocator.free(shared);
    }

    var tags: std.StringArrayHashMapUnmanaged(TagFile) = .empty;
    defer {
        for (tags.values()) |*tag| {
            tag.body.deinit(self.allocator);
            self.allocator.free(tag.file_name);
        }
        for (tags.keys()) |key| self.allocator.free(key);
        tags.deinit(self.allocator);
    }

    const paths = try self.allocator.alloc([]const u8, doc.paths.count());
    defer self.allocator.free(paths);
    var index: usize = 0;
    var path_iterator = doc.paths.keyIterator();
    while (path_iterator.next()) |path| : (index += 1) paths[index] = path.*;
    std.mem.sort([]const u8, paths, {}, lessThan);

    var used_files: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var it = used_files.keyIterator();
        while (it.next()) |key| self.allocator.free(key.*);
        used_files.deinit(self.allocator);
    }

    for (paths) |path| {
        const item = doc.paths.get(path).?;
        const methods = [_]struct { name: []const u8, operation: ?Operation }{
            .{ .name = "GET", .operation = item.get },
            .{ .name = "POST", .operation = item.post },
            .{ .name = "PUT", .operation = item.put },
            .{ .name = "DELETE", .operation = item.delete },
            .{ .name = "PATCH", .operation = item.patch },
            .{ .name = "HEAD", .operation = item.head },
            .{ .name = "OPTIONS", .operation = item.options },
        };
        for (methods) |method| {
            const operation = method.operation orelse continue;
            const tag = firstTag(operation);
            const entry = try tags.getOrPut(self.allocator, tag);
            if (!entry.found_existing) {
                const key = try self.allocator.dupe(u8, tag);
                errdefer self.allocator.free(key);
                const file_name = try uniqueFileName(self, &used_files, tag);
                entry.key_ptr.* = key;
                entry.value_ptr.* = .{ .file_name = file_name, .body = .empty };
            }
            // The operation code appends to `self.buffer`, so lend it the tag's.
            std.mem.swap(std.ArrayList(u8), &self.buffer, &entry.value_ptr.body);
            defer std.mem.swap(std.ArrayList(u8), &self.buffer, &entry.value_ptr.body);
            try self.generateOperation(method.name, path, operation, doc);
        }
    }

    // Alphabetical by file name, so output order never depends on the spec.
    const order = try self.allocator.alloc(usize, tags.count());
    defer self.allocator.free(order);
    for (order, 0..) |*slot, i| slot.* = i;
    const files = tags.values();
    std.mem.sort(usize, order, files, struct {
        fn lessThan(values: []TagFile, a: usize, b: usize) bool {
            return std.mem.lessThan(u8, values[a].file_name, values[b].file_name);
        }
    }.lessThan);

    for (order) |tag_index| {
        const tag = &files[tag_index];
        try writeTagFile(self, tag, shared);
    }
}

fn writeTagFile(self: *UnifiedApiGenerator, tag: *TagFile, shared: []const []const u8) !void {
    var content: std.ArrayList(u8) = .empty;
    errdefer content.deinit(self.allocator);
    try content.appendSlice(self.allocator, "//! The operations of one tag. Generated; shared helpers live in `../client.zig`.\n\nconst std = @import(\"std\");\nconst _client_zig = @import(\"../client.zig\");\n");
    for (shared) |name| {
        try content.appendSlice(self.allocator, "const ");
        try content.appendSlice(self.allocator, name);
        try content.appendSlice(self.allocator, " = _client_zig.");
        try content.appendSlice(self.allocator, name);
        try content.appendSlice(self.allocator, ";\n");
    }
    try content.append(self.allocator, '\n');
    try content.appendSlice(self.allocator, tag.body.items);

    // Re-export each declaration from client.zig.
    const declared = try topLevelNamesOf(self, tag.body.items);
    defer {
        for (declared) |name| self.allocator.free(name);
        self.allocator.free(declared);
    }
    for (declared) |name| {
        try self.buffer.appendSlice(self.allocator, "pub const ");
        try self.buffer.appendSlice(self.allocator, name);
        try self.buffer.appendSlice(self.allocator, " = @import(\"client/");
        try self.buffer.appendSlice(self.allocator, tag.file_name);
        try self.buffer.appendSlice(self.allocator, "\").");
        try self.buffer.appendSlice(self.allocator, name);
        try self.buffer.appendSlice(self.allocator, ";\n");
    }

    const path = try std.fmt.allocPrint(self.allocator, "client/{s}", .{tag.file_name});
    errdefer self.allocator.free(path);
    try self.split_files.append(self.allocator, .{ .name = path, .content = try content.toOwnedSlice(self.allocator) });
}

fn firstTag(operation: Operation) []const u8 {
    if (operation.tags) |tags| {
        if (tags.len > 0 and tags[0].len > 0) return tags[0];
    }
    return "default";
}

/// `users.user` becomes `users_user.zig`; clashes get a numeric suffix.
fn uniqueFileName(self: *UnifiedApiGenerator, used: *std.StringHashMapUnmanaged(void), tag: []const u8) ![]const u8 {
    var stem: std.ArrayList(u8) = .empty;
    defer stem.deinit(self.allocator);
    for (tag) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            if (std.ascii.isUpper(c) and stem.items.len > 0 and std.ascii.isLower(stem.items[stem.items.len - 1])) {
                try stem.append(self.allocator, '_');
            }
            try stem.append(self.allocator, std.ascii.toLower(c));
        } else if (stem.items.len > 0 and stem.items[stem.items.len - 1] != '_') {
            try stem.append(self.allocator, '_');
        }
    }
    while (stem.items.len > 0 and stem.items[stem.items.len - 1] == '_') _ = stem.pop();
    if (stem.items.len == 0) try stem.appendSlice(self.allocator, "default");
    if (std.ascii.isDigit(stem.items[0])) try stem.insertSlice(self.allocator, 0, "t_");

    var candidate = try std.fmt.allocPrint(self.allocator, "{s}.zig", .{stem.items});
    errdefer self.allocator.free(candidate);
    var counter: usize = 2;
    while (used.contains(candidate)) : (counter += 1) {
        self.allocator.free(candidate);
        candidate = try std.fmt.allocPrint(self.allocator, "{s}_{d}.zig", .{ stem.items, counter });
    }
    try used.put(self.allocator, try self.allocator.dupe(u8, candidate), {});
    return candidate;
}

/// Turns `fn x` and `const x` at the start of a line into `pub` declarations,
/// so tag files can use the helpers of `client.zig`.
fn makeTopLevelDeclarationsPublic(self: *UnifiedApiGenerator) !void {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(self.allocator);
    var lines = std.mem.splitScalar(u8, self.buffer.items, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(self.allocator, '\n');
        first = false;
        // `std` stays private: a public `std` would expose the whole standard
        // library as part of the client's API.
        const is_std = std.mem.startsWith(u8, line, "const std = ");
        if (!is_std and (std.mem.startsWith(u8, line, "fn ") or std.mem.startsWith(u8, line, "const "))) {
            try out.appendSlice(self.allocator, "pub ");
        }
        try out.appendSlice(self.allocator, line);
    }
    self.buffer.clearRetainingCapacity();
    try self.buffer.appendSlice(self.allocator, out.items);
    out.deinit(self.allocator);
}

fn topLevelNames(self: *UnifiedApiGenerator) ![]const []const u8 {
    const names = try topLevelNamesOf(self, self.buffer.items);
    errdefer {
        for (names) |name| self.allocator.free(name);
        self.allocator.free(names);
    }
    // `std` is imported by every tag file itself.
    var kept: std.ArrayList([]const u8) = .empty;
    errdefer kept.deinit(self.allocator);
    for (names) |name| {
        if (std.mem.eql(u8, name, "std")) { // (kept in case a later change makes it public)
            self.allocator.free(name);
        } else {
            try kept.append(self.allocator, name);
        }
    }
    self.allocator.free(names);
    return kept.toOwnedSlice(self.allocator);
}

/// The names of `pub fn` and `pub const` declarations at the start of lines.
/// Each name is returned exactly as it must be written (`@"x.y"` stays quoted).
fn topLevelNamesOf(self: *UnifiedApiGenerator, text: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |name| self.allocator.free(name);
        names.deinit(self.allocator);
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const rest = if (std.mem.startsWith(u8, line, "pub fn "))
            line["pub fn ".len..]
        else if (std.mem.startsWith(u8, line, "pub const "))
            line["pub const ".len..]
        else
            continue;
        const end = nameEnd(rest) orelse continue;
        if (end == 0) continue;
        try names.append(self.allocator, try self.allocator.dupe(u8, rest[0..end]));
    }
    return names.toOwnedSlice(self.allocator);
}

fn nameEnd(text: []const u8) ?usize {
    if (std.mem.startsWith(u8, text, "@\"")) {
        var i: usize = 2;
        while (i < text.len) : (i += 1) {
            if (text[i] == '\\') {
                i += 1;
                continue;
            }
            if (text[i] == '"') return i + 1;
        }
        return null;
    }
    var i: usize = 0;
    while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) : (i += 1) {}
    return i;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
