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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        const responses = try parseResponses(allocator, obj.get("responses") orelse return error.MissingResponses);
        const tags = if (obj.get("tags")) |val| try parseStringArray(allocator, val) else null;
        
        const summary = if (obj.get("summary")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const description = if (obj.get("description")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const externalDocs = if (obj.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null;
        
        const operationId = if (obj.get("operationId")) |val| switch (val) {
            .string => |str| try allocator.dupe(u8, str),
            else => null,
        } else null;
        
        const consumes = if (obj.get("consumes")) |val| try parseStringArray(allocator, val) else null;
        const produces = if (obj.get("produces")) |val| try parseStringArray(allocator, val) else null;
        const parameters = if (obj.get("parameters")) |val| try parseParameters(allocator, val) else null;
        const schemes = if (obj.get("schemes")) |val| try parseStringArray(allocator, val) else null;
        
        const deprecated = if (obj.get("deprecated")) |val| switch (val) {
            .bool => |b| b,
            else => null,
        } else null;
        
        const security = if (obj.get("security")) |val| try parseSecurityRequirements(allocator, val) else null;
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
        const arr = switch (value) {
            .array => |a| a,
            else => return error.ExpectedArray,
        };

        var array_list = std.ArrayList([]const u8).init(allocator);
        errdefer array_list.deinit();
        for (arr.items) |item| {
            const str = switch (item) {
                .string => |s| s,
                else => return error.ExpectedString,
            };
            try array_list.append(try allocator.dupe(u8, str));
        }
        return array_list.toOwnedSlice();
    }
    
    fn parseResponses(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Response) {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var map = std.StringHashMap(Response).init(allocator);
        errdefer map.deinit();
        var iterator = obj.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const response = try Response.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, response);
        }
        return map;
    }
    fn parseParameters(allocator: std.mem.Allocator, value: json.Value) anyerror![]Parameter {
        const arr = switch (value) {
            .array => |a| a,
            else => return error.ExpectedArray,
        };

        var array_list = std.ArrayList(Parameter).init(allocator);
        errdefer array_list.deinit();
        for (arr.items) |item| {
            try array_list.append(try Parameter.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }
    
    fn parseSecurityRequirements(allocator: std.mem.Allocator, value: json.Value) anyerror![]SecurityRequirement {
        const arr = switch (value) {
            .array => |a| a,
            else => return error.ExpectedArray,
        };

        var array_list = std.ArrayList(SecurityRequirement).init(allocator);
        errdefer array_list.deinit();
        for (arr.items) |item| {
            try array_list.append(try SecurityRequirement.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }
};
