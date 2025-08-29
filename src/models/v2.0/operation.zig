const std = @import("std");
const json = std.json;
const Parameter = @import("parameter.zig").Parameter;
const Response = @import("response.zig").Response;
const SecurityRequirement = @import("security.zig").SecurityRequirement;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Operation = struct {
    responses: std.StringHashMap(Response),
    tags: ?[][]const u8 = null,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    externalDocs: ?ExternalDocumentation = null,
    operationId: ?[]const u8 = null,
    consumes: ?[][]const u8 = null,
    produces: ?[][]const u8 = null,
    parameters: ?[]Parameter = null,
    schemes: ?[][]const u8 = null,
    deprecated: ?bool = null,
    security: ?[]SecurityRequirement = null,

    pub fn deinit(self: *Operation, allocator: std.mem.Allocator) void {
        var response_iterator = self.responses.iterator();
        while (response_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.responses.deinit();
        if (self.tags) |tags| {
            for (tags) |tag| {
                allocator.free(tag);
            }
            allocator.free(tags);
        }
        if (self.summary) |summary| {
            allocator.free(summary);
        }
        if (self.description) |description| {
            allocator.free(description);
        }
        if (self.externalDocs) |*external_docs| {
            external_docs.deinit(allocator);
        }
        if (self.operationId) |operationId| {
            allocator.free(operationId);
        }
        if (self.consumes) |consumes| {
            for (consumes) |consume| {
                allocator.free(consume);
            }
            allocator.free(consumes);
        }
        if (self.produces) |produces| {
            for (produces) |produce| {
                allocator.free(produce);
            }
            allocator.free(produces);
        }
        if (self.parameters) |parameters| {
            for (parameters) |*parameter| {
                parameter.deinit(allocator);
            }
            allocator.free(parameters);
        }
        if (self.schemes) |schemes| {
            for (schemes) |scheme| {
                allocator.free(scheme);
            }
            allocator.free(schemes);
        }
        if (self.security) |security| {
            for (security) |*security_req| {
                security_req.deinit(allocator);
            }
            allocator.free(security);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Operation {
        const responses = try parseResponses(allocator, value.object.get("responses").?);
        const tags = if (value.object.get("tags")) |val| try parseStringArray(allocator, val) else null;
        const summary = if (value.object.get("summary")) |val| try allocator.dupe(u8, val.string) else null;
        const description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null;
        const externalDocs = if (value.object.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null;
        const operationId = if (value.object.get("operationId")) |val| try allocator.dupe(u8, val.string) else null;
        const consumes = if (value.object.get("consumes")) |val| try parseStringArray(allocator, val) else null;
        const produces = if (value.object.get("produces")) |val| try parseStringArray(allocator, val) else null;
        const parameters = if (value.object.get("parameters")) |val| try parseParameters(allocator, val) else null;
        const schemes = if (value.object.get("schemes")) |val| try parseStringArray(allocator, val) else null;
        const deprecated = if (value.object.get("deprecated")) |val| val.bool else null;
        const security = if (value.object.get("security")) |val| try parseSecurityRequirements(allocator, val) else null;
        return Operation{
            .responses = responses,
            .tags = tags,
            .summary = summary,
            .description = description,
            .externalDocs = externalDocs,
            .operationId = operationId,
            .consumes = consumes,
            .produces = produces,
            .parameters = parameters,
            .schemes = schemes,
            .deprecated = deprecated,
            .security = security,
        };
    }
    fn parseStringArray(allocator: std.mem.Allocator, value: json.Value) anyerror![][]const u8 {
        var array_list = std.ArrayList([]const u8){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, try allocator.dupe(u8, item.string));
        }
        return array_list.toOwnedSlice(allocator);
    }
    fn parseResponses(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Response) {
        var map = std.StringHashMap(Response).init(allocator);
        errdefer map.deinit();
        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const response = try Response.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, response);
        }
        return map;
    }
    fn parseParameters(allocator: std.mem.Allocator, value: json.Value) anyerror![]Parameter {
        var array_list = std.ArrayList(Parameter){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, try Parameter.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice(allocator);
    }
    fn parseSecurityRequirements(allocator: std.mem.Allocator, value: json.Value) anyerror![]SecurityRequirement {
        var array_list = std.ArrayList(SecurityRequirement){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, try SecurityRequirement.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice(allocator);
    }
};
