const std = @import("std");
const json = std.json;
const Server = @import("server.zig").Server;
const ParameterOrReference = @import("parameter.zig").ParameterOrReference;
const Responses = @import("response.zig").Responses;
const RequestBodyOrReference = @import("requestbody.zig").RequestBodyOrReference;
const CallbackOrReference = @import("callback.zig").CallbackOrReference;
const SecurityRequirement = @import("security.zig").SecurityRequirement;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Operation = struct {
    responses: Responses,
    tags: ?[]const []const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
    operationId: ?[]const u8 = null,
    parameters: ?[]const ParameterOrReference = null,
    requestBody: ?RequestBodyOrReference = null,
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,
    deprecated: ?bool = null,
    security: ?[]const SecurityRequirement = null,
    servers: ?[]const Server = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Operation {
        const obj = value.object;
        var tags_list = std.ArrayList([]const u8).init(allocator);
        errdefer tags_list.deinit();
        if (obj.get("tags")) |tags_val| {
            for (tags_val.array.items) |item| {
                try tags_list.append(try allocator.dupe(u8, item.string));
            }
        }
        var parameters_list = std.ArrayList(ParameterOrReference).init(allocator);
        errdefer parameters_list.deinit();
        if (obj.get("parameters")) |params_val| {
            for (params_val.array.items) |item| {
                try parameters_list.append(try ParameterOrReference.parseFromJson(allocator, item));
            }
        }
        var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
        errdefer callbacks_map.deinit();
        if (obj.get("callbacks")) |callbacks_val| {
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(try allocator.dupe(u8, key), try CallbackOrReference.parseFromJson(allocator, callbacks_val.object.get(key).?));
            }
        }
        var security_list = std.ArrayList(SecurityRequirement).init(allocator);
        errdefer security_list.deinit();
        if (obj.get("security")) |security_val| {
            for (security_val.array.items) |item| {
                try security_list.append(try SecurityRequirement.parseFromJson(allocator, item));
            }
        }
        var servers_list = std.ArrayList(Server).init(allocator);
        errdefer servers_list.deinit();
        if (obj.get("servers")) |servers_val| {
            for (servers_val.array.items) |item| {
                try servers_list.append(try Server.parseFromJson(allocator, item));
            }
        }

        return Operation{
            .responses = try Responses.parseFromJson(allocator, obj.get("responses").?),
            .tags = if (tags_list.items.len > 0) try tags_list.toOwnedSlice() else null,
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null,
            .operationId = if (obj.get("operationId")) |val| try allocator.dupe(u8, val.string) else null,
            .parameters = if (parameters_list.items.len > 0) try parameters_list.toOwnedSlice() else null,
            .requestBody = if (obj.get("requestBody")) |val| try RequestBodyOrReference.parseFromJson(allocator, val) else null,
            .callbacks = if (callbacks_map.count() > 0) callbacks_map else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .security = if (security_list.items.len > 0) try security_list.toOwnedSlice() else null,
            .servers = if (servers_list.items.len > 0) try servers_list.toOwnedSlice() else null,
        };
    }

    pub fn deinit(self: *Operation, allocator: std.mem.Allocator) void {
        self.responses.deinit(allocator);

        if (self.tags) |tags| {
            for (tags) |tag| {
                allocator.free(tag);
            }
            allocator.free(tags);
        }

        if (self.summary) |summary| allocator.free(summary);
        if (self.description) |description| allocator.free(description);
        if (self.operationId) |operationId| allocator.free(operationId);

        if (self.externalDocs) |*externalDocs| {
            externalDocs.deinit(allocator);
        }

        if (self.parameters) |params| {
            for (params) |*param| {
                var mutable_param = @constCast(param);
                mutable_param.deinit(allocator);
            }
            allocator.free(params);
        }

        if (self.requestBody) |*requestBody| {
            requestBody.deinit(allocator);
        }

        if (self.callbacks) |*callbacks| {
            var iterator = callbacks.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            callbacks.deinit();
        }

        if (self.security) |security| {
            for (security) |*sec| {
                var mutable_sec = @constCast(sec);
                mutable_sec.deinit(allocator);
            }
            allocator.free(security);
        }

        if (self.servers) |servers| {
            for (servers) |*server| {
                var mutable_server = @constCast(server);
                mutable_server.deinit(allocator);
            }
            allocator.free(servers);
        }
    }
};
