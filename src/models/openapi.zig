const std = @import("std");
const json = std.json;
const Info = @import("info.zig").Info;
const Paths = @import("paths.zig").Paths;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;
const Server = @import("server.zig").Server;
const SecurityRequirement = @import("security.zig").SecurityRequirement;
const Tag = @import("tag.zig").Tag;
const Components = @import("components.zig").Components;

pub const OpenApiDocument = struct {
    openapi: []const u8,
    info: Info,
    paths: Paths,
    externalDocs: ?ExternalDocumentation = null,
    servers: ?[]Server = null,
    security: ?[]SecurityRequirement = null,
    tags: ?[]const Tag = null,
    components: ?Components = null,

    pub fn deinit(self: *OpenApiDocument, allocator: std.mem.Allocator) void {
        // Free the openapi string
        allocator.free(self.openapi);

        // Free the info struct
        self.info.deinit(allocator);

        // Free the paths
        self.paths.deinit(allocator);

        // Free external docs if present
        if (self.externalDocs) |external_docs| {
            external_docs.deinit(allocator);
        }

        // Free servers if present
        if (self.servers) |servers| {
            for (servers) |*server| {
                server.deinit(allocator);
            }
            allocator.free(servers);
        }

        // Free security requirements if present
        if (self.security) |security| {
            for (security) |*security_req| {
                security_req.deinit(allocator);
            }
            allocator.free(security);
        }

        // Free tags if present
        if (self.tags) |tags| {
            for (tags) |tag| {
                tag.deinit(allocator);
            }
            allocator.free(tags);
        }

        // Free components if present
        if (self.components) |*components| {
            components.deinit(allocator);
        }
    }

    pub fn parse(allocator: std.mem.Allocator, json_string: []const u8) anyerror!OpenApiDocument {
        var parsed = try json.parseFromSlice(json.Value, allocator, json_string, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const root = parsed.value;

        // Allocate persistent copies of strings
        const openapi_str = try allocator.dupe(u8, root.object.get("openapi").?.string);

        const info = try Info.parse(allocator, root.object.get("info").?);
        const paths = try Paths.parse(allocator, root.object.get("paths").?);
        const externalDocs = if (root.object.get("externalDocs")) |val| try ExternalDocumentation.parse(allocator, val) else null;
        const servers = if (root.object.get("servers")) |val| try parseServers(allocator, val) else null;
        const security = if (root.object.get("security")) |val| try parseSecurityRequirements(allocator, val) else null;
        const tags = if (root.object.get("tags")) |val| try parseTags(allocator, val) else null;
        const components = if (root.object.get("components")) |val| try Components.parse(allocator, val) else null;

        return OpenApiDocument{
            .openapi = openapi_str,
            .info = info,
            .paths = paths,
            .externalDocs = externalDocs,
            .servers = servers,
            .security = security,
            .tags = tags,
            .components = components,
        };
    }

    fn parseServers(allocator: std.mem.Allocator, value: json.Value) anyerror![]Server {
        var array_list = std.ArrayList(Server).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try Server.parse(allocator, item));
        }
        return array_list.toOwnedSlice();
    }

    fn parseSecurityRequirements(allocator: std.mem.Allocator, value: json.Value) anyerror![]SecurityRequirement {
        var array_list = std.ArrayList(SecurityRequirement).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try SecurityRequirement.parse(allocator, item));
        }
        return array_list.toOwnedSlice();
    }

    fn parseTags(allocator: std.mem.Allocator, value: json.Value) anyerror![]const Tag {
        var array_list = std.ArrayList(Tag).init(allocator);
        errdefer array_list.deinit();
        for (value.array.items) |item| {
            try array_list.append(try Tag.parse(allocator, item));
        }
        return array_list.toOwnedSlice();
    }
};
