const std = @import("std");
const json = std.json;
const SchemaOrReference = @import("schema.zig").SchemaOrReference;
const ResponseOrReference = @import("response.zig").ResponseOrReference;
const ParameterOrReference = @import("parameter.zig").ParameterOrReference;
const ExampleOrReference = @import("media.zig").ExampleOrReference;
const RequestBodyOrReference = @import("requestbody.zig").RequestBodyOrReference;
const HeaderOrReference = @import("media.zig").HeaderOrReference;
const SecuritySchemeOrReference = @import("security.zig").SecuritySchemeOrReference;
const LinkOrReference = @import("link.zig").LinkOrReference;
const CallbackOrReference = @import("callback.zig").CallbackOrReference;

pub const Components = struct {
    schemas: ?std.StringHashMap(SchemaOrReference) = null,
    responses: ?std.StringHashMap(ResponseOrReference) = null,
    parameters: ?std.StringHashMap(ParameterOrReference) = null,
    examples: ?std.StringHashMap(ExampleOrReference) = null,
    requestBodies: ?std.StringHashMap(RequestBodyOrReference) = null,
    headers: ?std.StringHashMap(HeaderOrReference) = null,
    securitySchemes: ?std.StringHashMap(SecuritySchemeOrReference) = null,
    links: ?std.StringHashMap(LinkOrReference) = null,
    callbacks: ?std.StringHashMap(CallbackOrReference) = null,

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!Components {
        const obj = value.object;
        var schemas_map = std.StringHashMap(SchemaOrReference).init(allocator);
        errdefer schemas_map.deinit();
        if (obj.get("schemas")) |schemas_val| {
            for (schemas_val.object.keys()) |key| {
                try schemas_map.put(try allocator.dupe(u8, key), try SchemaOrReference.parseFromJson(allocator, schemas_val.object.get(key).?));
            }
        }
        var responses_map = std.StringHashMap(ResponseOrReference).init(allocator);
        errdefer responses_map.deinit();
        if (obj.get("responses")) |responses_val| {
            for (responses_val.object.keys()) |key| {
                try responses_map.put(try allocator.dupe(u8, key), try ResponseOrReference.parseFromJson(allocator, responses_val.object.get(key).?));
            }
        }
        var parameters_map = std.StringHashMap(ParameterOrReference).init(allocator);
        errdefer parameters_map.deinit();
        if (obj.get("parameters")) |parameters_val| {
            for (parameters_val.object.keys()) |key| {
                try parameters_map.put(try allocator.dupe(u8, key), try ParameterOrReference.parseFromJson(allocator, parameters_val.object.get(key).?));
            }
        }
        var examples_map = std.StringHashMap(ExampleOrReference).init(allocator);
        errdefer examples_map.deinit();
        if (obj.get("examples")) |examples_val| {
            for (examples_val.object.keys()) |key| {
                try examples_map.put(key, try ExampleOrReference.parseFromJson(allocator, examples_val.object.get(key).?));
            }
        }
        var request_bodies_map = std.StringHashMap(RequestBodyOrReference).init(allocator);
        errdefer request_bodies_map.deinit();
        if (obj.get("requestBodies")) |request_bodies_val| {
            for (request_bodies_val.object.keys()) |key| {
                try request_bodies_map.put(try allocator.dupe(u8, key), try RequestBodyOrReference.parseFromJson(allocator, request_bodies_val.object.get(key).?));
            }
        }
        var headers_map = std.StringHashMap(HeaderOrReference).init(allocator);
        errdefer headers_map.deinit();
        if (obj.get("headers")) |headers_val| {
            for (headers_val.object.keys()) |key| {
                try headers_map.put(key, try HeaderOrReference.parseFromJson(allocator, headers_val.object.get(key).?));
            }
        }
        var security_schemes_map = std.StringHashMap(SecuritySchemeOrReference).init(allocator);
        errdefer security_schemes_map.deinit();
        if (obj.get("securitySchemes")) |security_schemes_val| {
            for (security_schemes_val.object.keys()) |key| {
                try security_schemes_map.put(try allocator.dupe(u8, key), try SecuritySchemeOrReference.parseFromJson(allocator, security_schemes_val.object.get(key).?));
            }
        }
        var links_map = std.StringHashMap(LinkOrReference).init(allocator);
        errdefer links_map.deinit();
        if (obj.get("links")) |links_val| {
            for (links_val.object.keys()) |key| {
                try links_map.put(key, try LinkOrReference.parseFromJson(allocator, links_val.object.get(key).?));
            }
        }
        var callbacks_map = std.StringHashMap(CallbackOrReference).init(allocator);
        errdefer callbacks_map.deinit();
        if (obj.get("callbacks")) |callbacks_val| {
            for (callbacks_val.object.keys()) |key| {
                try callbacks_map.put(key, try CallbackOrReference.parseFromJson(allocator, callbacks_val.object.get(key).?));
            }
        }

        return Components{
            .schemas = if (schemas_map.count() > 0) schemas_map else null,
            .responses = if (responses_map.count() > 0) responses_map else null,
            .parameters = if (parameters_map.count() > 0) parameters_map else null,
            .examples = if (examples_map.count() > 0) examples_map else null,
            .requestBodies = if (request_bodies_map.count() > 0) request_bodies_map else null,
            .headers = if (headers_map.count() > 0) headers_map else null,
            .securitySchemes = if (security_schemes_map.count() > 0) security_schemes_map else null,
            .links = if (links_map.count() > 0) links_map else null,
            .callbacks = if (callbacks_map.count() > 0) callbacks_map else null,
        };
    }

    pub fn deinit(self: *Components, allocator: std.mem.Allocator) void {
        // For now, just basic cleanup of HashMaps - proper cleanup would need to deinit each value
        if (self.schemas) |*schemas| {
            var iterator = schemas.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            schemas.deinit();
        }
        if (self.responses) |*responses| responses.deinit();
        if (self.parameters) |*parameters| parameters.deinit();
        if (self.examples) |*examples| examples.deinit();
        if (self.requestBodies) |*request_bodies| {
            var iterator = request_bodies.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            request_bodies.deinit();
        }
        if (self.headers) |*headers| headers.deinit();
        if (self.securitySchemes) |*security_schemes| {
            var iterator = security_schemes.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            security_schemes.deinit();
        }
        if (self.links) |*links| links.deinit();
        if (self.callbacks) |*callbacks| callbacks.deinit();
    }
};
