const std = @import("std");
const json = std.json;
const Info = @import("info.zig").Info;
const Paths = @import("paths.zig").Paths;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;
const SecurityRequirement = @import("security.zig").SecurityRequirement;
const SecurityDefinitions = @import("security.zig").SecurityDefinitions;
const Tag = @import("tag.zig").Tag;
const Schema = @import("schema.zig").Schema;
const Parameter = @import("parameter.zig").Parameter;
const Response = @import("response.zig").Response;

pub const SwaggerDocument = struct {
    swagger: []const u8,
    info: Info,
    paths: Paths,
    host: ?[]const u8 = null,
    basePath: ?[]const u8 = null,
    schemes: ?[][]const u8 = null,
    consumes: ?[][]const u8 = null,
    produces: ?[][]const u8 = null,
    definitions: ?std.StringHashMap(Schema) = null,
    parameters: ?std.StringHashMap(Parameter) = null,
    responses: ?std.StringHashMap(Response) = null,
    security: ?[]SecurityRequirement = null,
    securityDefinitions: ?SecurityDefinitions = null,
    tags: ?[]Tag = null,
    externalDocs: ?ExternalDocumentation = null,

    pub fn deinit(self: *SwaggerDocument, allocator: std.mem.Allocator) void {
        allocator.free(self.swagger);
        self.info.deinit(allocator);
        self.paths.deinit(allocator);

        if (self.host) |host| {
            allocator.free(host);
        }

        if (self.basePath) |basePath| {
            allocator.free(basePath);
        }

        if (self.schemes) |schemes| {
            for (schemes) |scheme| {
                allocator.free(scheme);
            }
            allocator.free(schemes);
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

        if (self.definitions) |*definitions| {
            var iterator = definitions.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            definitions.deinit();
        }

        if (self.parameters) |*parameters| {
            var iterator = parameters.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            parameters.deinit();
        }

        if (self.responses) |*responses| {
            var iterator = responses.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            responses.deinit();
        }

        if (self.security) |security| {
            for (security) |*security_req| {
                security_req.deinit(allocator);
            }
            allocator.free(security);
        }

        if (self.securityDefinitions) |*securityDefinitions| {
            securityDefinitions.deinit(allocator);
        }

        if (self.tags) |tags| {
            for (tags) |*tag| {
                tag.deinit(allocator);
            }
            allocator.free(tags);
        }

        if (self.externalDocs) |*external_docs| {
            external_docs.deinit(allocator);
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, json_string: []const u8) anyerror!SwaggerDocument {
        var parsed = try json.parseFromSlice(json.Value, allocator, json_string, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const root = parsed.value;

        // Allocate persistent copies of strings
        const swagger_str = try allocator.dupe(u8, root.object.get("swagger").?.string);

        const info = try Info.parseFromJson(allocator, root.object.get("info").?);
        const paths = try Paths.parseFromJson(allocator, root.object.get("paths").?);

        const host = if (root.object.get("host")) |val| try allocator.dupe(u8, val.string) else null;
        const basePath = if (root.object.get("basePath")) |val| try allocator.dupe(u8, val.string) else null;
        const schemes = if (root.object.get("schemes")) |val| try parseStringArray(allocator, val) else null;
        const consumes = if (root.object.get("consumes")) |val| try parseStringArray(allocator, val) else null;
        const produces = if (root.object.get("produces")) |val| try parseStringArray(allocator, val) else null;
        const definitions = if (root.object.get("definitions")) |val| try parseDefinitions(allocator, val) else null;
        const parameters = if (root.object.get("parameters")) |val| try parseParameters(allocator, val) else null;
        const responses = if (root.object.get("responses")) |val| try parseResponses(allocator, val) else null;
        const security = if (root.object.get("security")) |val| try parseSecurityRequirements(allocator, val) else null;
        const securityDefinitions = if (root.object.get("securityDefinitions")) |val| try SecurityDefinitions.parseFromJson(allocator, val) else null;
        const tags = if (root.object.get("tags")) |val| try parseTags(allocator, val) else null;
        const externalDocs = if (root.object.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null;

        return SwaggerDocument{
            .swagger = swagger_str,
            .info = info,
            .paths = paths,
            .host = host,
            .basePath = basePath,
            .schemes = schemes,
            .consumes = consumes,
            .produces = produces,
            .definitions = definitions,
            .parameters = parameters,
            .responses = responses,
            .security = security,
            .securityDefinitions = securityDefinitions,
            .tags = tags,
            .externalDocs = externalDocs,
        };
    }

    fn parseStringArray(allocator: std.mem.Allocator, value: json.Value) anyerror![][]const u8 {
        var array_list = std.ArrayList([]const u8).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try allocator.dupe(u8, item.string));
        }
        return array_list.toOwnedSlice();
    }

    fn parseDefinitions(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Schema) {
        var map = std.StringHashMap(Schema).init(allocator);
        errdefer map.deinit();

        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const schema = try Schema.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, schema);
        }
        return map;
    }

    fn parseParameters(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(Parameter) {
        var map = std.StringHashMap(Parameter).init(allocator);
        errdefer map.deinit();

        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const parameter = try Parameter.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, parameter);
        }
        return map;
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

    fn parseSecurityRequirements(allocator: std.mem.Allocator, value: json.Value) anyerror![]SecurityRequirement {
        var array_list = std.ArrayList(SecurityRequirement).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try SecurityRequirement.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }

    fn parseTags(allocator: std.mem.Allocator, value: json.Value) anyerror![]Tag {
        var array_list = std.ArrayList(Tag).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try Tag.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice();
    }
};
