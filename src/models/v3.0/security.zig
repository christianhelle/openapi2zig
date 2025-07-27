const std = @import("std");
const json = std.json;
pub const SecurityRequirement = struct {
    schemes: std.StringHashMap([]const []const u8),
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityRequirement {
        var schemes_map = std.StringHashMap([]const []const u8).init(allocator);
        errdefer schemes_map.deinit();
        const obj = value.object;
        for (obj.keys()) |key| {
            var scopes_list = std.ArrayList([]const u8).init(allocator);
            errdefer scopes_list.deinit();
            for (obj.get(key).?.array.items) |item| {
                try scopes_list.append(try allocator.dupe(u8, item.string));
            }
            try schemes_map.put(try allocator.dupe(u8, key), try scopes_list.toOwnedSlice());
        }
        return SecurityRequirement{ .schemes = schemes_map };
    }
    pub fn deinit(self: *SecurityRequirement, allocator: std.mem.Allocator) void {
        var iterator = self.schemes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |scope| {
                allocator.free(scope);
            }
            allocator.free(entry.value_ptr.*);
        }
        self.schemes.deinit();
    }
};
pub const OAuthFlows = struct {
    implicit: ?ImplicitOAuthFlow = null,
    password: ?PasswordOAuthFlow = null,
    clientCredentials: ?ClientCredentialsFlow = null,
    authorizationCode: ?AuthorizationCodeOAuthFlow = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!OAuthFlows {
        const obj = value.object;
        return OAuthFlows{
            .implicit = if (obj.get("implicit")) |val| try ImplicitOAuthFlow.parseFromJson(allocator, val) else null,
            .password = if (obj.get("password")) |val| try PasswordOAuthFlow.parseFromJson(allocator, val) else null,
            .clientCredentials = if (obj.get("clientCredentials")) |val| try ClientCredentialsFlow.parseFromJson(allocator, val) else null,
            .authorizationCode = if (obj.get("authorizationCode")) |val| try AuthorizationCodeOAuthFlow.parseFromJson(allocator, val) else null,
        };
    }
    pub fn deinit(self: *OAuthFlows, allocator: std.mem.Allocator) void {
        if (self.implicit) |*flow| {
            flow.deinit(allocator);
        }
        if (self.password) |*flow| {
            flow.deinit(allocator);
        }
        if (self.clientCredentials) |*flow| {
            flow.deinit(allocator);
        }
        if (self.authorizationCode) |*flow| {
            flow.deinit(allocator);
        }
    }
};
pub const ImplicitOAuthFlow = struct {
    authorizationUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ImplicitOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return ImplicitOAuthFlow{
            .authorizationUrl = try allocator.dupe(u8, obj.get("authorizationUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *ImplicitOAuthFlow, allocator: std.mem.Allocator) void {
        allocator.free(self.authorizationUrl);
        var iterator = self.scopes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.scopes.deinit();
        if (self.refreshUrl) |url| {
            allocator.free(url);
        }
    }
};
pub const PasswordOAuthFlow = struct {
    tokenUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!PasswordOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return PasswordOAuthFlow{
            .tokenUrl = try allocator.dupe(u8, obj.get("tokenUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *PasswordOAuthFlow, allocator: std.mem.Allocator) void {
        allocator.free(self.tokenUrl);
        var iterator = self.scopes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.scopes.deinit();
        if (self.refreshUrl) |url| {
            allocator.free(url);
        }
    }
};
pub const ClientCredentialsFlow = struct {
    tokenUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!ClientCredentialsFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return ClientCredentialsFlow{
            .tokenUrl = try allocator.dupe(u8, obj.get("tokenUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *ClientCredentialsFlow, allocator: std.mem.Allocator) void {
        allocator.free(self.tokenUrl);
        var iterator = self.scopes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.scopes.deinit();
        if (self.refreshUrl) |url| {
            allocator.free(url);
        }
    }
};
pub const AuthorizationCodeOAuthFlow = struct {
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    scopes: std.StringHashMap([]const u8),
    refreshUrl: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!AuthorizationCodeOAuthFlow {
        const obj = value.object;
        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            for (scopes_val.object.keys()) |key| {
                try scopes_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, scopes_val.object.get(key).?.string));
            }
        }
        return AuthorizationCodeOAuthFlow{
            .authorizationUrl = try allocator.dupe(u8, obj.get("authorizationUrl").?.string),
            .tokenUrl = try allocator.dupe(u8, obj.get("tokenUrl").?.string),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *AuthorizationCodeOAuthFlow, allocator: std.mem.Allocator) void {
        allocator.free(self.authorizationUrl);
        allocator.free(self.tokenUrl);
        var iterator = self.scopes.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.scopes.deinit();
        if (self.refreshUrl) |url| {
            allocator.free(url);
        }
    }
};
pub const APIKeySecurityScheme = struct {
    type: []const u8, // "apiKey"
    name: []const u8,
    in_field: []const u8, // "header", "query", "cookie"
    description: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!APIKeySecurityScheme {
        const obj = value.object;
        return APIKeySecurityScheme{
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .name = try allocator.dupe(u8, obj.get("name").?.string),
            .in_field = try allocator.dupe(u8, obj.get("in").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *APIKeySecurityScheme, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.name);
        allocator.free(self.in_field);
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};
pub const HTTPSecurityScheme = struct {
    scheme: []const u8,
    type: []const u8, // "http"
    bearerFormat: ?[]const u8 = null,
    description: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!HTTPSecurityScheme {
        const obj = value.object;
        return HTTPSecurityScheme{
            .scheme = try allocator.dupe(u8, obj.get("scheme").?.string),
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .bearerFormat = if (obj.get("bearerFormat")) |val| try allocator.dupe(u8, val.string) else null,
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *HTTPSecurityScheme, allocator: std.mem.Allocator) void {
        allocator.free(self.scheme);
        allocator.free(self.type);
        if (self.bearerFormat) |bf| {
            allocator.free(bf);
        }
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};
pub const OAuth2SecurityScheme = struct {
    type: []const u8, // "oauth2"
    flows: OAuthFlows,
    description: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!OAuth2SecurityScheme {
        const obj = value.object;
        return OAuth2SecurityScheme{
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .flows = try OAuthFlows.parseFromJson(allocator, obj.get("flows").?),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *OAuth2SecurityScheme, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        self.flows.deinit(allocator);
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};
pub const OpenIdConnectSecurityScheme = struct {
    type: []const u8, // "openIdConnect"
    openIdConnectUrl: []const u8,
    description: ?[]const u8 = null,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!OpenIdConnectSecurityScheme {
        const obj = value.object;
        return OpenIdConnectSecurityScheme{
            .type = try allocator.dupe(u8, obj.get("type").?.string),
            .openIdConnectUrl = try allocator.dupe(u8, obj.get("openIdConnectUrl").?.string),
            .description = if (obj.get("description")) |val| try allocator.dupe(u8, val.string) else null,
        };
    }
    pub fn deinit(self: *OpenIdConnectSecurityScheme, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.openIdConnectUrl);
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};
pub const SecurityScheme = union(enum) {
    api_key: APIKeySecurityScheme,
    http: HTTPSecurityScheme,
    oauth2: OAuth2SecurityScheme,
    openIdConnect: OpenIdConnectSecurityScheme,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityScheme {
        const obj = value.object;
        const type_str = obj.get("type").?.string;
        if (std.mem.eql(u8, type_str, "apiKey")) {
            return SecurityScheme{ .api_key = try APIKeySecurityScheme.parseFromJson(allocator, value) };
        } else if (std.mem.eql(u8, type_str, "http")) {
            return SecurityScheme{ .http = try HTTPSecurityScheme.parseFromJson(allocator, value) };
        } else if (std.mem.eql(u8, type_str, "oauth2")) {
            return SecurityScheme{ .oauth2 = try OAuth2SecurityScheme.parseFromJson(allocator, value) };
        } else if (std.mem.eql(u8, type_str, "openIdConnect")) {
            return SecurityScheme{ .openIdConnect = try OpenIdConnectSecurityScheme.parseFromJson(allocator, value) };
        } else {
            return error.UnknownSecuritySchemeType;
        }
    }
    pub fn deinit(self: *SecurityScheme, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .api_key => |*api_key| api_key.deinit(allocator),
            .http => |*http| http.deinit(allocator),
            .oauth2 => |*oauth2| oauth2.deinit(allocator),
            .openIdConnect => |*openIdConnect| openIdConnect.deinit(allocator),
        }
    }
};
pub const SecuritySchemeOrReference = union(enum) {
    security_scheme: SecurityScheme,
    reference: @import("reference.zig").Reference,
    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecuritySchemeOrReference {
        if (value.object.get("$ref") != null) {
            return SecuritySchemeOrReference{ .reference = try @import("reference.zig").Reference.parseFromJson(allocator, value) };
        } else {
            return SecuritySchemeOrReference{ .security_scheme = try SecurityScheme.parseFromJson(allocator, value) };
        }
    }
    pub fn deinit(self: *SecuritySchemeOrReference, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .security_scheme => |*security_scheme| security_scheme.deinit(allocator),
            .reference => |*reference| reference.deinit(allocator),
        }
    }
};
