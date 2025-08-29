const std = @import("std");
const json = std.json;
const Operation = @import("operation.zig").Operation;
const Server = @import("server.zig").Server;
const ParameterOrReference = @import("parameter.zig").ParameterOrReference;

pub const PathItem = struct {
    ref: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    get: ?Operation = null,
    put: ?Operation = null,
    post: ?Operation = null,
    delete: ?Operation = null,
    options: ?Operation = null,
    head: ?Operation = null,
    patch: ?Operation = null,
    trace: ?Operation = null,
    servers: ?[]const Server = null,
    parameters: ?[]const ParameterOrReference = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!PathItem {
        const obj = value.object;
        var parameters_list = std.ArrayList(ParameterOrReference){};
        errdefer parameters_list.deinit(allocator);
        if (obj.get("parameters")) |params_val| {
            for (params_val.array.items) |item| {
                try parameters_list.append(allocator, try ParameterOrReference.parseFromJson(allocator, item));
            }
        }
        var servers_list = std.ArrayList(Server){};
        errdefer servers_list.deinit(allocator);
        if (obj.get("servers")) |servers_val| {
            for (servers_val.array.items) |item| {
                try servers_list.append(allocator, try Server.parseFromJson(allocator, item));
            }
        }
        return PathItem{
            .ref = if (obj.get("$ref")) |val| try allocator.dupe(u8, val.string) else null,
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .get = if (obj.get("get")) |val| try Operation.parseFromJson(allocator, val) else null,
            .put = if (obj.get("put")) |val| try Operation.parseFromJson(allocator, val) else null,
            .post = if (obj.get("post")) |val| try Operation.parseFromJson(allocator, val) else null,
            .delete = if (obj.get("delete")) |val| try Operation.parseFromJson(allocator, val) else null,
            .options = if (obj.get("options")) |val| try Operation.parseFromJson(allocator, val) else null,
            .head = if (obj.get("head")) |val| try Operation.parseFromJson(allocator, val) else null,
            .patch = if (obj.get("patch")) |val| try Operation.parseFromJson(allocator, val) else null,
            .trace = if (obj.get("trace")) |val| try Operation.parseFromJson(allocator, val) else null,
            .servers = if (servers_list.items.len > 0) try servers_list.toOwnedSlice(allocator) else null,
            .parameters = if (parameters_list.items.len > 0) try parameters_list.toOwnedSlice(allocator) else null,
        };
    }

    pub fn deinit(self: *PathItem, allocator: std.mem.Allocator) void {
        if (self.ref) |ref| allocator.free(ref);
        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |description| allocator.free(description);
        if (self.get) |*get| get.deinit(allocator);
        if (self.put) |*put| put.deinit(allocator);
        if (self.post) |*post| post.deinit(allocator);
        if (self.delete) |*delete| delete.deinit(allocator);
        if (self.options) |*options| options.deinit(allocator);
        if (self.head) |*head| head.deinit(allocator);
        if (self.patch) |*patch| patch.deinit(allocator);
        if (self.trace) |*trace| trace.deinit(allocator);
        if (self.servers) |servers| {
            for (servers) |*server| {
                var mutable_server = @constCast(server);
                mutable_server.deinit(allocator);
            }
            allocator.free(servers);
        }
        if (self.parameters) |parameters| {
            for (parameters) |*param| {
                var mutable_param = @constCast(param);
                mutable_param.deinit(allocator);
            }
            allocator.free(parameters);
        }
    }
};

pub const Paths = struct {
    path_items: std.StringHashMap(PathItem),

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Paths {
        var path_items_map = std.StringHashMap(PathItem).init(allocator);
        errdefer path_items_map.deinit();
        const obj = value.object;
        for (obj.keys()) |key| {
            if (key[0] == '/') { // Path items start with '/'
                try path_items_map.put(try allocator.dupe(u8, key), try PathItem.parseFromJson(allocator, obj.get(key).?));
            }
        }
        return Paths{ .path_items = path_items_map };
    }

    pub fn deinit(self: *Paths, allocator: std.mem.Allocator) void {
        var iterator = self.path_items.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.path_items.deinit();
    }
};
