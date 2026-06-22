const std = @import("std");

/// Returns the base media type with any parameters (e.g. "; charset=utf-8")
/// and surrounding whitespace removed. The casing is preserved; callers should
/// compare case-insensitively.
pub fn baseMediaType(ct: []const u8) []const u8 {
    var base = ct;
    if (std.mem.indexOfScalar(u8, base, ';')) |i| base = base[0..i];
    return std.mem.trim(u8, base, " \t");
}

/// True when the media type (ignoring parameters, case-insensitive) is
/// exactly application/json.
pub fn isJson(ct: []const u8) bool {
    return std.ascii.eqlIgnoreCase(baseMediaType(ct), "application/json");
}

/// True when the media type base ends with a structured "+json" suffix
/// (case-insensitive), e.g. application/vnd.api+json.
pub fn isJsonSuffix(ct: []const u8) bool {
    const base = baseMediaType(ct);
    if (base.len <= 5) return false;
    return std.ascii.eqlIgnoreCase(base[base.len - 5 ..], "+json");
}

/// Selects the most appropriate content-type key from a media-type map,
/// preferring exact JSON, then a "+json" suffix, then any entry. Comparisons
/// ignore media-type parameters and casing, while the original key string is
/// returned. Ties within a tier are broken lexicographically so selection is
/// deterministic regardless of hash-map iteration order.
pub fn selectBestJsonKey(comptime MapType: type, content: MapType) ?[]const u8 {
    var exact: ?[]const u8 = null;
    var suffix: ?[]const u8 = null;
    var fallback: ?[]const u8 = null;
    var it = content.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (fallback == null or std.mem.lessThan(u8, key, fallback.?)) fallback = key;
        if (isJson(key)) {
            if (exact == null or std.mem.lessThan(u8, key, exact.?)) exact = key;
        } else if (isJsonSuffix(key)) {
            if (suffix == null or std.mem.lessThan(u8, key, suffix.?)) suffix = key;
        }
    }
    return exact orelse suffix orelse fallback;
}

test "baseMediaType strips parameters and whitespace" {
    const t = std.testing;
    try t.expectEqualStrings("application/json", baseMediaType("application/json"));
    try t.expectEqualStrings("application/json", baseMediaType("application/json; charset=utf-8"));
    try t.expectEqualStrings("application/json", baseMediaType("  application/json ; charset=utf-8"));
    try t.expectEqualStrings("application/octet-stream", baseMediaType("application/octet-stream"));
}

test "isJson and isJsonSuffix ignore parameters and casing" {
    const t = std.testing;
    try t.expect(isJson("application/json"));
    try t.expect(isJson("Application/JSON; charset=utf-8"));
    try t.expect(!isJson("application/octet-stream"));
    try t.expect(isJsonSuffix("application/vnd.api+json"));
    try t.expect(isJsonSuffix("application/vnd.api+JSON; charset=utf-8"));
    try t.expect(!isJsonSuffix("+json"));
    try t.expect(!isJsonSuffix("application/json"));
}

test "selectBestJsonKey prefers exact then suffix then deterministic fallback" {
    const t = std.testing;
    const Map = std.StringHashMap(void);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    {
        var m = Map.init(a);
        try m.put("application/octet-stream", {});
        try m.put("application/json; charset=utf-8", {});
        try m.put("application/vnd.api+json", {});
        try t.expectEqualStrings("application/json; charset=utf-8", selectBestJsonKey(Map, m).?);
    }
    {
        var m = Map.init(a);
        try m.put("application/octet-stream", {});
        try m.put("application/vnd.api+json", {});
        try t.expectEqualStrings("application/vnd.api+json", selectBestJsonKey(Map, m).?);
    }
    {
        var m = Map.init(a);
        try m.put("image/png", {});
        try m.put("application/octet-stream", {});
        try t.expectEqualStrings("application/octet-stream", selectBestJsonKey(Map, m).?);
    }
}
