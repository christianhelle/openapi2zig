const std = @import("std");
const json = std.json;

fn deinitVariablesMap(map: *std.StringHashMap(ServerVariable), allocator: std.mem.Allocator) void {
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(allocator);
    }
    map.deinit();
}

pub const ServerVariable = struct {
    default: []const u8,
    enum_values: ?[]const []const u8 = null,
    description: ?[]const u8 = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ServerVariable {
        const obj = value.object;
        var enum_list = std.ArrayList([]const u8){};
        errdefer {
            for (enum_list.items) |item| {
                allocator.free(item);
            }
            enum_list.deinit(allocator);
        }

        if (obj.get("enum")) |enum_val| {
            for (enum_val.array.items) |item| {
                try enum_list.append(allocator, try allocator.dupe(u8, item.string));
            }
        }

        return ServerVariable{
            .default = try allocator.dupe(u8, obj.get("default").?.string),
            .enum_values = if (enum_list.items.len > 0) try enum_list.toOwnedSlice(allocator) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }

    pub fn deinit(self: ServerVariable, allocator: std.mem.Allocator) void {
        allocator.free(self.default);
        if (self.description) |desc| allocator.free(desc);
        if (self.enum_values) |enum_vals| {
            for (enum_vals) |val| {
                allocator.free(val);
            }
            allocator.free(enum_vals);
        }
    }
};

pub const Server = struct {
    url: []const u8,
    description: ?[]const u8 = null,
    variables: ?std.StringHashMap(ServerVariable) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Server {
        const obj = value.object;
        var variables_map: ?std.StringHashMap(ServerVariable) = null;

        if (obj.get("variables")) |vars_val| {
            var map = std.StringHashMap(ServerVariable).init(allocator);
            errdefer deinitVariablesMap(&map, allocator);
            for (vars_val.object.keys()) |key| {
                try map.put(try allocator.dupe(u8, key), try ServerVariable.parseFromJson(allocator, vars_val.object.get(key).?));
            }
            if (map.count() > 0) {
                variables_map = map;
            } else {
                map.deinit();
            }
        }

        return Server{
            .url = try allocator.dupe(u8, obj.get("url").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .variables = variables_map,
        };
    }

    pub fn deinit(self: *Server, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.description) |desc| allocator.free(desc);
        if (self.variables) |*vars| {
            deinitVariablesMap(vars, allocator);
        }
    }
};
