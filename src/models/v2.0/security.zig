const std = @import("std");
const json = std.json;

pub const SecuritySchemeType = enum {
    basic,
    apiKey,
    oauth2,

    pub fn fromString(str: []const u8) ?SecuritySchemeType {
        if (std.mem.eql(u8, str, "basic")) return .basic;
        if (std.mem.eql(u8, str, "apiKey")) return .apiKey;
        if (std.mem.eql(u8, str, "oauth2")) return .oauth2;
        return null;
    }
};

pub const ApiKeyLocation = enum {
    query,
    header,

    pub fn fromString(str: []const u8) ?ApiKeyLocation {
        if (std.mem.eql(u8, str, "query")) return .query;
        if (std.mem.eql(u8, str, "header")) return .header;
        return null;
    }
};

pub const OAuth2Flow = enum {
    implicit,
    password,
    application,
    accessCode,

    pub fn fromString(str: []const u8) ?OAuth2Flow {
        if (std.mem.eql(u8, str, "implicit")) return .implicit;
        if (std.mem.eql(u8, str, "password")) return .password;
        if (std.mem.eql(u8, str, "application")) return .application;
        if (std.mem.eql(u8, str, "accessCode")) return .accessCode;
        return null;
    }
};

pub const SecurityScheme = struct {
    type: SecuritySchemeType,
    description: ?[]const u8 = null,
    name: ?[]const u8 = null,
    in: ?ApiKeyLocation = null,
    flow: ?OAuth2Flow = null,
    authorizationUrl: ?[]const u8 = null,
    tokenUrl: ?[]const u8 = null,
    scopes: ?std.StringHashMap([]const u8) = null,

    pub fn deinit(self: *SecurityScheme, allocator: std.mem.Allocator) void {
        if (self.description) |description| {
            allocator.free(description);
        }
        if (self.name) |name| {
            allocator.free(name);
        }
        if (self.authorizationUrl) |url| {
            allocator.free(url);
        }
        if (self.tokenUrl) |url| {
            allocator.free(url);
        }
        if (self.scopes) |*scopes| {
            var iterator = scopes.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            scopes.deinit();
        }
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityScheme {
        const type_str = value.object.get("type").?.string;
        const scheme_type = SecuritySchemeType.fromString(type_str) orelse return error.InvalidSecuritySchemeType;
        const description = if (value.object.get("description")) |val| try allocator.dupe(u8, val.string) else null;
        const name = if (value.object.get("name")) |val| try allocator.dupe(u8, val.string) else null;
        const in_location = if (value.object.get("in")) |val| blk: {
            const in_str = val.string;
            break :blk ApiKeyLocation.fromString(in_str);
        } else null;
        const flow = if (value.object.get("flow")) |val| blk: {
            const flow_str = val.string;
            break :blk OAuth2Flow.fromString(flow_str);
        } else null;
        const authorizationUrl = if (value.object.get("authorizationUrl")) |val| try allocator.dupe(u8, val.string) else null;
        const tokenUrl = if (value.object.get("tokenUrl")) |val| try allocator.dupe(u8, val.string) else null;
        const scopes = if (value.object.get("scopes")) |val| try parseScopes(allocator, val) else null;
        return SecurityScheme{
            .type = scheme_type,
            .description = description,
            .name = name,
            .in = in_location,
            .flow = flow,
            .authorizationUrl = authorizationUrl,
            .tokenUrl = tokenUrl,
            .scopes = scopes,
        };
    }
    fn parseScopes(allocator: std.mem.Allocator, value: json.Value) anyerror!std.StringHashMap([]const u8) {
        var map = std.StringHashMap([]const u8).init(allocator);
        errdefer map.deinit();
        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const scope_desc = try allocator.dupe(u8, entry.value_ptr.string);
            try map.put(key, scope_desc);
        }
        return map;
    }
};

pub const SecurityDefinitions = struct {
    definitions: std.StringHashMap(SecurityScheme),

    pub fn deinit(self: *SecurityDefinitions, allocator: std.mem.Allocator) void {
        var iterator = self.definitions.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.definitions.deinit();
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityDefinitions {
        var map = std.StringHashMap(SecurityScheme).init(allocator);
        errdefer map.deinit();
        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const scheme = try SecurityScheme.parseFromJson(allocator, entry.value_ptr.*);
            try map.put(key, scheme);
        }
        return SecurityDefinitions{
            .definitions = map,
        };
    }
};

pub const SecurityRequirement = struct {
    requirements: std.StringHashMap([][]const u8),

    pub fn deinit(self: *SecurityRequirement, allocator: std.mem.Allocator) void {
        var iterator = self.requirements.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |scope| {
                allocator.free(scope);
            }
            allocator.free(entry.value_ptr.*);
        }
        self.requirements.deinit();
    }

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityRequirement {
        var map = std.StringHashMap([][]const u8).init(allocator);
        errdefer map.deinit();
        var iterator = value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const scopes = try parseStringArray(allocator, entry.value_ptr.*);
            try map.put(key, scopes);
        }
        return SecurityRequirement{
            .requirements = map,
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
};
