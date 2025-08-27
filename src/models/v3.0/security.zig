const std = @import("std");
const json = std.json;

pub const SecurityRequirement = struct {
    schemes: std.StringHashMap([]const []const u8),

    pub fn parseFromJson(allocator: std.mem.Allocator, value: json.Value) anyerror!SecurityRequirement {
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var schemes_map = std.StringHashMap([]const []const u8).init(allocator);
        errdefer schemes_map.deinit();
        
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            const scopes_val = entry.value_ptr.*;
            const scopes_arr = switch (scopes_val) {
                .array => |a| a,
                else => return error.ExpectedArray,
            };

            var scopes_list = std.ArrayList([]const u8).init(allocator);
            errdefer scopes_list.deinit();
            
            for (scopes_arr.items) |item| {
                const scope_str = switch (item) {
                    .string => |str| str,
                    else => return error.ExpectedString,
                };
                try scopes_list.append(try allocator.dupe(u8, scope_str));
            }
            try schemes_map.put(try allocator.dupe(u8, entry.key_ptr.*), try scopes_list.toOwnedSlice());
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            const scopes_obj = switch (scopes_val) {
                .object => |o| o,
                else => return error.ExpectedObject,
            };

            var iter = scopes_obj.iterator();
            while (iter.next()) |entry| {
                const scope_desc = switch (entry.value_ptr.*) {
                    .string => |str| str,
                    else => return error.ExpectedString,
                };
                try scopes_map.put(try allocator.dupe(u8, entry.key_ptr.*), try allocator.dupe(u8, scope_desc));
            }
        }

        const auth_url_str = switch (obj.get("authorizationUrl") orelse return error.MissingAuthorizationUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return ImplicitOAuthFlow{
            .authorizationUrl = try allocator.dupe(u8, auth_url_str),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            const scopes_obj = switch (scopes_val) {
                .object => |o| o,
                else => return error.ExpectedObject,
            };

            var iter = scopes_obj.iterator();
            while (iter.next()) |entry| {
                const scope_desc = switch (entry.value_ptr.*) {
                    .string => |str| str,
                    else => return error.ExpectedString,
                };
                try scopes_map.put(try allocator.dupe(u8, entry.key_ptr.*), try allocator.dupe(u8, scope_desc));
            }
        }

        const token_url_str = switch (obj.get("tokenUrl") orelse return error.MissingTokenUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return PasswordOAuthFlow{
            .tokenUrl = try allocator.dupe(u8, token_url_str),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            const scopes_obj = switch (scopes_val) {
                .object => |o| o,
                else => return error.ExpectedObject,
            };

            var iter = scopes_obj.iterator();
            while (iter.next()) |entry| {
                const scope_desc = switch (entry.value_ptr.*) {
                    .string => |str| str,
                    else => return error.ExpectedString,
                };
                try scopes_map.put(try allocator.dupe(u8, entry.key_ptr.*), try allocator.dupe(u8, scope_desc));
            }
        }

        const token_url_str = switch (obj.get("tokenUrl") orelse return error.MissingTokenUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return ClientCredentialsFlow{
            .tokenUrl = try allocator.dupe(u8, token_url_str),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        var scopes_map = std.StringHashMap([]const u8).init(allocator);
        if (obj.get("scopes")) |scopes_val| {
            const scopes_obj = switch (scopes_val) {
                .object => |o| o,
                else => return error.ExpectedObject,
            };

            var iter = scopes_obj.iterator();
            while (iter.next()) |entry| {
                const scope_desc = switch (entry.value_ptr.*) {
                    .string => |str| str,
                    else => return error.ExpectedString,
                };
                try scopes_map.put(try allocator.dupe(u8, entry.key_ptr.*), try allocator.dupe(u8, scope_desc));
            }
        }

        const auth_url_str = switch (obj.get("authorizationUrl") orelse return error.MissingAuthorizationUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        const token_url_str = switch (obj.get("tokenUrl") orelse return error.MissingTokenUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return AuthorizationCodeOAuthFlow{
            .authorizationUrl = try allocator.dupe(u8, auth_url_str),
            .tokenUrl = try allocator.dupe(u8, token_url_str),
            .scopes = scopes_map,
            .refreshUrl = if (obj.get("refreshUrl")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        const type_str = switch (obj.get("type") orelse return error.MissingType) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        const name_str = switch (obj.get("name") orelse return error.MissingName) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        const in_str = switch (obj.get("in") orelse return error.MissingIn) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return APIKeySecurityScheme{
            .type = try allocator.dupe(u8, type_str),
            .name = try allocator.dupe(u8, name_str),
            .in_field = try allocator.dupe(u8, in_str),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) { .object => |o| o, else => return error.ExpectedObject, };
        const scheme_str = switch (obj.get("scheme") orelse return error.MissingScheme) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        const type_str = switch (obj.get("type") orelse return error.MissingType) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return HTTPSecurityScheme{
            .scheme = try allocator.dupe(u8, scheme_str),
            .type = try allocator.dupe(u8, type_str),
            .bearerFormat = if (obj.get("bearerFormat")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) { .object => |o| o, else => return error.ExpectedObject, };
        const type_str = switch (obj.get("type") orelse return error.MissingType) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return OAuth2SecurityScheme{
            .type = try allocator.dupe(u8, type_str),
            .flows = try OAuthFlows.parseFromJson(allocator, obj.get("flows") orelse return error.MissingFlows),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) { .object => |o| o, else => return error.ExpectedObject, };
        const type_str = switch (obj.get("type") orelse return error.MissingType) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        const connect_url_str = switch (obj.get("openIdConnectUrl") orelse return error.MissingOpenIdConnectUrl) {
            .string => |str| str,
            else => return error.ExpectedString,
        };

        return OpenIdConnectSecurityScheme{
            .type = try allocator.dupe(u8, type_str),
            .openIdConnectUrl = try allocator.dupe(u8, connect_url_str),
            .description = if (obj.get("description")) |val| switch (val) {
                .string => |str| try allocator.dupe(u8, str),
                else => null,
            } else null,
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
        const obj = switch (value) { .object => |o| o, else => return error.ExpectedObject, };
        const type_str = switch (obj.get("type") orelse return error.MissingType) {
            .string => |str| str,
            else => return error.ExpectedString,
        };
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
        const obj = switch (value) {
            .object => |o| o,
            else => return error.ExpectedObject,
        };

        if (obj.get("$ref") != null) {
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
