const std = @import("std");
const json = std.json;
const Info = @import("info.zig").Info;
const Paths = @import("paths.zig").Paths;
const PathItem = @import("paths.zig").PathItem;
const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;
const Server = @import("server.zig").Server;
const SecurityRequirement = @import("security.zig").SecurityRequirement;
const Tag = @import("tag.zig").Tag;
const Components = @import("components.zig").Components;
const PathItemOrReference = @import("components.zig").PathItemOrReference;

pub const OpenApi32Document = struct {
    openapi: []const u8,
    info: Info,
    paths: ?Paths = null,
    externalDocs: ?ExternalDocumentation = null,
    servers: ?[]Server = null,
    security: ?[]SecurityRequirement = null,
    tags: ?[]const Tag = null,
    components: ?Components = null,
    jsonSchemaDialect: ?[]const u8 = null,
    webhooks: ?std.StringHashMap(PathItemOrReference) = null,

    pub fn deinit(self: *OpenApi32Document, allocator: std.mem.Allocator) void {
        allocator.free(self.openapi);
        self.info.deinit(allocator);
        if (self.paths) |*paths| {
            paths.deinit(allocator);
        }
        if (self.externalDocs) |external_docs| {
            external_docs.deinit(allocator);
        }
        if (self.servers) |servers| {
            for (servers) |*server| {
                server.deinit(allocator);
            }
            allocator.free(servers);
        }
        if (self.security) |security| {
            for (security) |*security_req| {
                security_req.deinit(allocator);
            }
            allocator.free(security);
        }
        if (self.tags) |tags| {
            for (tags) |tag| {
                tag.deinit(allocator);
            }
            allocator.free(tags);
        }
        if (self.components) |*components| {
            components.deinit(allocator);
        }
        if (self.jsonSchemaDialect) |dialect| {
            allocator.free(dialect);
        }
        if (self.webhooks) |*webhooks| {
            var iterator = webhooks.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            webhooks.deinit();
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, json_string: []const u8) anyerror!OpenApi32Document {
        var parsed = try json.parseFromSlice(json.Value, allocator, json_string, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        const root = parsed.value;
        const openapi_str = try allocator.dupe(u8, root.object.get("openapi").?.string);
        const info = try Info.parseFromJson(allocator, root.object.get("info").?);
        const paths = if (root.object.get("paths")) |val| try Paths.parseFromJson(allocator, val) else null;
        const externalDocs = if (root.object.get("externalDocs")) |val| try ExternalDocumentation.parseFromJson(allocator, val) else null;
        const servers = if (root.object.get("servers")) |val| try parseServers(allocator, val) else null;
        const security = if (root.object.get("security")) |val| try parseSecurityRequirements(allocator, val) else null;
        const tags = if (root.object.get("tags")) |val| try parseTags(allocator, val) else null;
        const components = if (root.object.get("components")) |val| try Components.parseFromJson(allocator, val) else null;
        const jsonSchemaDialect = if (root.object.get("jsonSchemaDialect")) |val| try allocator.dupe(u8, val.string) else null;
        const webhooks = if (root.object.get("webhooks")) |val| try parseWebhooks(allocator, val) else null;
        return OpenApi32Document{
            .openapi = openapi_str,
            .info = info,
            .paths = paths,
            .externalDocs = externalDocs,
            .servers = servers,
            .security = security,
            .tags = tags,
            .components = components,
            .jsonSchemaDialect = jsonSchemaDialect,
            .webhooks = webhooks,
        };
    }

    fn parseServers(allocator: std.mem.Allocator, value: json.Value) anyerror![]Server {
        var array_list = std.ArrayList(Server){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, try Server.parseFromJson(allocator, item));
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

    fn parseTags(allocator: std.mem.Allocator, value: json.Value) anyerror![]const Tag {
        var array_list = std.ArrayList(Tag){};
        errdefer array_list.deinit(allocator);
        for (value.array.items) |item| {
            try array_list.append(allocator, try Tag.parseFromJson(allocator, item));
        }
        return array_list.toOwnedSlice(allocator);
    }

    fn parseWebhooks(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap(PathItemOrReference) {
        var webhooks_map = std.StringHashMap(PathItemOrReference).init(allocator);
        errdefer webhooks_map.deinit();
        for (value.object.keys()) |key| {
            try webhooks_map.put(try allocator.dupe(u8, key), try PathItemOrReference.parseFromJson(allocator, value.object.get(key).?));
        }
        return webhooks_map;
    }
};
