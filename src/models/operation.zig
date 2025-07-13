const std = @import("std");
const json = std.json;
const Server = @import("server.zig").Server;
const ParameterOrReference = @import("parameter.zig").ParameterOrReference;
const Responses = @import("response.zig").Responses;
const RequestBodyOrReference = @import("request_body.zig").RequestBodyOrReference;
const CallbackOrReference = @import("callback.zig").CallbackOrReference;
const SecurityRequirement = @import("security.zig").SecurityRequirement;
const ExternalDocumentation = @import("documentation.zig").ExternalDocumentation;

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

    pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!Operation {
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
                try parameters_list.append(try ParameterOrReference.parse(allocator, item));
            }
        }
        var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
        errdefer callbacks_map.deinit();
        if (obj.get("callbacks")) |callbacks_val| {
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(key, try CallbackOrReference.parse(allocator, callbacks_val.object.get(key).?));
            }
        }
        var security_list = std.ArrayList(SecurityRequirement).init(allocator);
        errdefer security_list.deinit();
        if (obj.get("security")) |security_val| {
            for (security_val.array.items) |item| {
                try security_list.append(try SecurityRequirement.parse(allocator, item));
            }
        }
        var servers_list = std.ArrayList(Server).init(allocator);
        errdefer servers_list.deinit();
        if (obj.get("servers")) |servers_val| {
            for (servers_val.array.items) |item| {
                try servers_list.append(try Server.parse(allocator, item));
            }
        }

        return Operation{
            .responses = try Responses.parse(allocator, obj.get("responses").?),
            .tags = if (tags_list.items.len > 0) try tags_list.toOwnedSlice() else null,
            .summary = if (obj.get("summary")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
            .externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null,
            .operationId = if (obj.get("operationId")) |val| try allocator.dupe(u8, val.string) else null,
            .parameters = if (parameters_list.items.len > 0) try parameters_list.toOwnedSlice() else null,
            .requestBody = if (obj.get("requestBody")) |val| try RequestBodyOrReference.parse(allocator, val) else null,
            .callbacks = if (callbacks_map.count() > 0) callbacks_map else null,
            .deprecated = if (obj.get("deprecated")) |val| val.bool else null,
            .security = if (security_list.items.len > 0) try security_list.toOwnedSlice() else null,
            .servers = if (servers_list.items.len > 0) try servers_list.toOwnedSlice() else null,
        };
    }
};
