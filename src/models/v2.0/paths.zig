const std = @import("std");
const json = std.json;
const Operation = @import("operation.zig").Operation;
const Parameter = @import("parameter.zig").Parameter;

pub const PathItem = struct {
    ref: ?[]const u8 = null, // $ref
    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    parameters: ?[]Parameter = null,

    pub fn deinit(self: *PathItem, allocator: std.mem.Allocator) void {
        if (self.ref) |ref| {
            allocator.free(ref);
        }
        if (self.get) |*operation| {
            operation.deinit(allocator);
        }
        if (self.put) |*operation| {
            operation.deinit(allocator);
        }
        if (self.post) |*operation| {
            operation.deinit(allocator);
        }
        if (self.delete) |*operation| {
            operation.deinit(allocator);
        }
        if (self.options) |*operation| {
            operation.deinit(allocator);
        }
        if (self.head) |*operation| {
            operation.deinit(allocator);
        }
        if (self.patch) |*operation| {
            operation.deinit(allocator);
        }
        if (self.parameters) |parameters| {
            for (parameters) |*parameter| {
                parameter.deinit(allocator);
            }
            allocator.free(parameters);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!PathItem {
        const ref = if (value.object.get("$ref")) |val| try allocator.dupe(u8, val.string) else null;
        const get = if (value.object.get("get")) |val| try Operation.parseFromJson(allocator, val) else null;
        const put = if (value.object.get("put")) |val| try Operation.parseFromJson(allocator, val) else null;
        const post = if (value.object.get("post")) |val| try Operation.parseFromJson(allocator, val) else null;
        const delete = if (value.object.get("delete")) |val| try Operation.parseFromJson(allocator, val) else null;
        const options = if (value.object.get("options")) |val| try Operation.parseFromJson(allocator, val) else null;
        const head = if (value.object.get("head")) |val| try Operation.parseFromJson(allocator, val) else null;
        const patch = if (value.object.get("patch")) |val| try Operation.parseFromJson(allocator, val) else null;
        const parameters = if (value.object.get("parameters")) |val| try parseParameters(allocator, val) else null;

        return PathItem{
            .ref = ref,
            .get = get,
            .put = put,
            .post = post,
            .delete = delete,
            .options = options,
            .head = head,
            .patch = patch,
            .parameters = parameters,
        };
    }

    fn parseParameters(allocator: std.mem.Allocator, value: json.Value) anyerror![]Parameter {
        var array_list = std.ArrayList(Parameter).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try Parameter.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }
};

pub const Paths = struct {
    path_items: std.StringHashMap(PathItem),

    pub fn deinit(self: *Paths, allocator: std.mem.Allocator) void {
        var iterator = self.path_items.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.path_items.deinit();
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Paths {
        var map = std.StringHashMap(PathItem).init(allocator);
        errdefer map.deinit();

        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            // Skip vendor extensions (keys starting with "x-")
            if (std.mem.startsWith(u8, entry.key_ptr.*, "x-")) {
                continue;
            }

            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const path_item = try PathItem.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, path_item);
        }

        return Paths{
            .path_items = map,
        };
    }
};
