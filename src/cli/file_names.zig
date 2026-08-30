const std = @import("std");
const ident = @import("../generators/unified/ident_utils.zig");
const types = @import("types.zig");
const FileNameOverrides = types.FileNameOverrides;
const FileKind = types.FileKind;

pub fn findDuplicateFileName(file_names: FileNameOverrides) ?[]const u8 {
    const names = [_][]const u8{
        file_names.models orelse FileKind.models.defaultName(),
        file_names.runtime orelse FileKind.runtime.defaultName(),
        file_names.client orelse FileKind.client.defaultName(),
    };
    var i: usize = 0;
    while (i < names.len) : (i += 1) {
        var j = i + 1;
        while (j < names.len) : (j += 1) {
            if (fileNamesCollide(names[i], names[j])) return names[i];
        }
    }
    return null;
}

/// Compare two output file names treating '/' and '\' as equivalent path
/// separators and ignoring case, matching how the same on-disk path resolves on
/// case-insensitive filesystems.
pub fn fileNamesCollide(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const na = if (ca == '/' or ca == '\\') '/' else std.ascii.toLower(ca);
        const nb = if (cb == '/' or cb == '\\') '/' else std.ascii.toLower(cb);
        if (na != nb) return false;
    }
    return true;
}

pub const max_import_alias_len = 128;

/// Derive the Zig import alias for a generated file name into a caller-provided
/// buffer. This is the single source of truth for alias derivation; the
/// allocating `deriveAlias` used by the generator wraps this.
pub fn deriveAliasInto(buf: []u8, file_name: []const u8, fallback: []const u8) []const u8 {
    const stem = if (std.mem.lastIndexOfScalar(u8, file_name, '.')) |dot|
        file_name[0..dot]
    else
        file_name;
    if (stem.len == 0 or stem.len + 1 > buf.len) return fallback;

    var n: usize = 0;
    if (std.ascii.isDigit(stem[0])) {
        buf[n] = '_';
        n += 1;
    }
    for (stem) |c| {
        buf[n] = if (std.ascii.isAlphanumeric(c) or c == '_') c else '_';
        n += 1;
    }
    if (ident.isReservedIdent(buf[0..n])) {
        std.mem.copyBackwards(u8, buf[1 .. n + 1], buf[0..n]);
        buf[0] = '_';
        n += 1;
    }
    return buf[0..n];
}

/// Derive the Zig import alias for a generated file name. The caller owns the
/// returned slice. Mirrors the alias used by the multi-file generator so
/// parse-time validation agrees with the generated imports.
pub fn deriveAlias(allocator: std.mem.Allocator, file_name: []const u8, fallback: []const u8) ![]const u8 {
    var buf: [max_import_alias_len]u8 = undefined;
    return allocator.dupe(u8, deriveAliasInto(&buf, file_name, fallback));
}

/// Return the basename of an import path, treating both '/' and '\' as
/// separators. This handles Windows-style paths correctly on non-Windows hosts.
pub fn importBasename(path: []const u8) []const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return path[i + 1 ..];
        }
    }
    return path;
}

/// Return the directory of an import path, treating both '/' and '\' as
/// separators. Returns null if there is no directory component.
pub fn importDirname(path: []const u8) ?[]const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            if (i == 0) return "";
            return path[0..i];
        }
    }
    return null;
}

pub fn resolveRuntimeModulePath(allocator: std.mem.Allocator, client_name: []const u8, runtime_mod: []const u8) ![]const u8 {
    const client_dir = importDirname(client_name);
    var segments = std.ArrayList([]const u8).empty;
    defer segments.deinit(allocator);
    if (client_dir) |dir| {
        if (dir.len > 0) {
            var it = std.mem.splitAny(u8, dir, "/\\");
            while (it.next()) |part| {
                if (part.len == 0) continue;
                try segments.append(allocator, part);
            }
        }
    }
    var it = std.mem.splitAny(u8, runtime_mod, "/\\");
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (segments.items.len > 0 and !std.mem.eql(u8, segments.getLast(), "..")) {
                _ = segments.pop();
            } else {
                try segments.append(allocator, "..");
            }
        } else {
            try segments.append(allocator, part);
        }
    }
    if (segments.items.len == 0) {
        return try allocator.dupe(u8, "");
    }
    return try std.mem.join(allocator, "/", segments.items);
}

pub fn effectiveAliasesInto(file_names: FileNameOverrides, bufs: *[3][max_import_alias_len]u8) [3][]const u8 {
    var aliases: [3][]const u8 = undefined;
    const kinds = [_]FileKind{ .models, .runtime, .client };
    for (kinds, 0..) |kind, i| {
        const name = file_names.get(kind) orelse kind.defaultName();
        aliases[i] = deriveAliasInto(&bufs[i], name, switch (kind) {
            .models => "models",
            .runtime => "runtime",
            .client => "client",
        });
    }
    return aliases;
}

pub fn findDuplicateAlias(aliases: [3][]const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < aliases.len) : (i += 1) {
        var j = i + 1;
        while (j < aliases.len) : (j += 1) {
            if (std.mem.eql(u8, aliases[i], aliases[j])) return aliases[i];
        }
    }
    return null;
}

/// Aliases that collide with names the generated client declares itself.
pub const reserved_aliases = [_][]const u8{ "std", "Client", "_" };

pub fn findReservedAlias(aliases: [3][]const u8) ?[]const u8 {
    for (aliases) |alias| {
        for (reserved_aliases) |reserved| {
            if (std.mem.eql(u8, alias, reserved)) return alias;
        }
    }
    return null;
}

pub fn validateFileName(name: []const u8) error{InvalidFileName}!void {
    if (std.fs.path.isAbsolute(name)) return error.InvalidFileName;
    var fwd = std.mem.splitScalar(u8, name, '/');
    while (fwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidFileName;
    }
    var bwd = std.mem.splitScalar(u8, name, '\\');
    while (bwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidFileName;
    }
}

/// Return true when `path` is absolute under any platform's conventions. This
/// treats root-relative and Windows drive paths as absolute regardless of the
/// build host, so import validation does not depend on the platform.
pub fn isAbsoluteImportPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '\\') return true;
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return true;
    return false;
}

pub fn validateImportPath(path: []const u8) error{InvalidFileName}!void {
    if (isAbsoluteImportPath(path)) return error.InvalidFileName;
    if (path.len == 0) return error.InvalidFileName;
    var fwd = std.mem.splitScalar(u8, path, '/');
    while (fwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) return error.InvalidFileName;
    }
    var bwd = std.mem.splitScalar(u8, path, '\\');
    while (bwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) return error.InvalidFileName;
    }
    if (std.mem.eql(u8, importBasename(path), "..")) return error.InvalidFileName;
}
