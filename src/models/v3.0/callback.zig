const std = @import("std");
const json = std.json;
const PathItem = @import("paths.zig").PathItem;
const Reference = @import("reference.zig").Reference;
pub const Callback = struct {
    path_items: std.StringHashMap(PathItem),
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Callback {
        var path_items_map = std.StringHashMap(PathItem).init(allocator);
        const obj = value.object;
        for (obj.keys()) |key| {
            try path_items_map.put(try allocator.dupe(u8, key), try PathItem.parseFromJson(allocator, obj.get(key).?));
        }
        return Callback{ .path_items = path_items_map };
    }
    pub fn deinit(self: *Callback, allocator: std.mem.Allocator) void {
        var iterator = self.path_items.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.path_items.deinit();
    }
};
pub const CallbackOrReference = union(enum) {
    callback: Callback,
    reference: Reference,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!CallbackOrReference {
        if (value.object.get("$ref") != null) {
            return CallbackOrReference{ .reference = try Reference.parseFromJson(allocator, value) };
        } else {
            return CallbackOrReference{ .callback = try Callback.parseFromJson(allocator, value) };
        }
    }
    pub fn deinit(self: *CallbackOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .callback => |*callback| callback.deinit(allocator),
            .reference => |*reference| reference.deinit(allocator),
        }
    }
};
