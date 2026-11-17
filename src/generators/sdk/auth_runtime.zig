//! OAuth 2.0 token acquisition for generated SDKs.
//!
//! `ClientCredentials` gets app-only tokens with a client secret. `DeviceCode`
//! signs a user in on another device. Both cache the access token, refresh it
//! shortly before it expires and plug into a client as a token provider:
//!
//!     var credentials = try auth.ClientCredentials.init(gpa, io, .{ ... });
//!     defer credentials.deinit();
//!     client.token_provider = credentials.tokenProvider(sdk.TokenProvider);
//!
//! This file is copied into each SDK by openapi2zig and is not specific to any
//! API.

const std = @import("std");

/// A `{name}` placeholder of a URL template and the text that replaces it.
pub const UrlParam = struct {
    name: []const u8,
    value: []const u8,
};

pub const AuthError = error{
    /// The authorization server answered with an OAuth error. Read `last_error`.
    OAuthError,
    /// The response was not the JSON the OAuth specification describes.
    InvalidTokenResponse,
    /// The user did not approve the sign-in in time.
    DeviceCodeExpired,
    UnknownUrlParameter,
};

/// Seconds before expiry at which a cached token is replaced.
const refresh_margin_seconds: i64 = 60;

/// Replaces every `{name}` in `template` with the matching entry of `params`.
/// The caller frees the result.
pub fn expandUrl(allocator: std.mem.Allocator, template: []const u8, params: []const UrlParam) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{') {
            const end = std.mem.indexOfScalarPos(u8, template, i, '}') orelse return error.UnknownUrlParameter;
            const name = template[i + 1 .. end];
            const value = for (params) |param| {
                if (std.mem.eql(u8, param.name, name)) break param.value;
            } else return error.UnknownUrlParameter;
            try out.appendSlice(allocator, value);
            i = end + 1;
            continue;
        }
        try out.append(allocator, template[i]);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or switch (c) {
        '-', '.', '_', '~' => true,
        else => false,
    };
}

/// Appends `name=value` to an `application/x-www-form-urlencoded` body.
pub fn appendFormField(allocator: std.mem.Allocator, body: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    if (body.items.len > 0) try body.append(allocator, '&');
    try appendEncoded(allocator, body, name);
    try body.append(allocator, '=');
    try appendEncoded(allocator, body, value);
}

fn appendEncoded(allocator: std.mem.Allocator, body: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |c| {
        if (isUnreserved(c)) {
            try body.append(allocator, c);
        } else {
            try body.print(allocator, "%{X:0>2}", .{c});
        }
    }
}

const TokenBody = struct {
    access_token: []const u8,
    expires_in: ?i64 = null,
    refresh_token: ?[]const u8 = null,
};

const ErrorBody = struct {
    @"error": []const u8,
    error_description: ?[]const u8 = null,
};

/// A parsed token endpoint success response.
pub const Token = struct {
    access_token: []u8,
    refresh_token: ?[]u8,
    /// Seconds until the access token expires, when the server said so.
    expires_in: ?i64,

    pub fn deinit(self: *Token, allocator: std.mem.Allocator) void {
        std.crypto.secureZero(u8, self.access_token);
        allocator.free(self.access_token);
        if (self.refresh_token) |value| {
            std.crypto.secureZero(u8, value);
            allocator.free(value);
        }
    }
};

pub fn parseTokenResponse(allocator: std.mem.Allocator, body: []const u8) !Token {
    const parsed = std.json.parseFromSlice(TokenBody, allocator, body, .{ .ignore_unknown_fields = true }) catch return error.InvalidTokenResponse;
    defer parsed.deinit();
    const access = try allocator.dupe(u8, parsed.value.access_token);
    errdefer allocator.free(access);
    const refresh = if (parsed.value.refresh_token) |value| try allocator.dupe(u8, value) else null;
    return .{ .access_token = access, .refresh_token = refresh, .expires_in = parsed.value.expires_in };
}

/// The OAuth error code and description of an error response, or null when the
/// body is not an OAuth error. The caller frees the result.
pub fn parseOAuthError(allocator: std.mem.Allocator, body: []const u8) !?[]u8 {
    const parsed = std.json.parseFromSlice(ErrorBody, allocator, body, .{ .ignore_unknown_fields = true }) catch return null;
    defer parsed.deinit();
    if (parsed.value.error_description) |description| {
        return try std.fmt.allocPrint(allocator, "{s}: {s}", .{ parsed.value.@"error", description });
    }
    return try allocator.dupe(u8, parsed.value.@"error");
}

const Response = struct {
    status: std.http.Status,
    body: []u8,
};

fn postForm(allocator: std.mem.Allocator, io: std.Io, url: []const u8, form: []const u8) !Response {
    var http: std.http.Client = .{ .allocator = allocator, .io = io };
    defer http.deinit();
    var body: std.Io.Writer.Allocating = .init(allocator);
    errdefer body.deinit();
    const result = try http.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = form,
        .headers = .{ .content_type = .{ .override = "application/x-www-form-urlencoded" } },
        .extra_headers = &.{.{ .name = "Accept", .value = "application/json" }},
        .response_writer = &body.writer,
    });
    return .{ .status = result.status, .body = try body.toOwnedSlice() };
}

fn nowSeconds(io: std.Io) i64 {
    return std.Io.Clock.awake.now(io).toSeconds();
}

/// The state shared by every flow: the cached access token and when to replace it.
const TokenCache = struct {
    access_token: ?[]u8 = null,
    refresh_token: ?[]u8 = null,
    expires_at: i64 = 0,

    fn isFresh(self: TokenCache, now: i64) bool {
        return self.access_token != null and now + refresh_margin_seconds < self.expires_at;
    }

    fn replace(self: *TokenCache, allocator: std.mem.Allocator, token: Token, now: i64) void {
        self.clear(allocator);
        self.access_token = token.access_token;
        self.refresh_token = token.refresh_token;
        self.expires_at = now + (token.expires_in orelse 3600);
    }

    fn clear(self: *TokenCache, allocator: std.mem.Allocator) void {
        if (self.access_token) |value| {
            std.crypto.secureZero(u8, value);
            allocator.free(value);
        }
        if (self.refresh_token) |value| {
            std.crypto.secureZero(u8, value);
            allocator.free(value);
        }
        self.access_token = null;
        self.refresh_token = null;
    }
};

fn adapter(comptime Provider: type, comptime Self: type, self: *Self) Provider {
    const Thunk = struct {
        fn get(ctx: *anyopaque, allocator: std.mem.Allocator, io: std.Io) anyerror![]const u8 {
            const credentials: *Self = @ptrCast(@alignCast(ctx));
            return credentials.getToken(allocator, io);
        }
    };
    return .{ .ctx = self, .getTokenFn = Thunk.get };
}

/// App-only access: the client authenticates with its own secret.
pub const ClientCredentials = struct {
    pub const Options = struct {
        /// May contain `{name}` placeholders filled from `url_params`.
        token_url: []const u8,
        url_params: []const UrlParam = &.{},
        client_id: []const u8,
        client_secret: []const u8,
        /// Space separated scopes.
        scope: []const u8,
    };

    allocator: std.mem.Allocator,
    token_url: []u8,
    client_id: []u8,
    client_secret: []u8,
    scope: []u8,
    mutex: std.Io.Mutex = .init,
    cache: TokenCache = .{},
    /// The last OAuth error, for example `invalid_client: ...`.
    last_error: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) !ClientCredentials {
        _ = io;
        const token_url = try expandUrl(allocator, options.token_url, options.url_params);
        errdefer allocator.free(token_url);
        const client_id = try allocator.dupe(u8, options.client_id);
        errdefer allocator.free(client_id);
        const client_secret = try allocator.dupe(u8, options.client_secret);
        errdefer allocator.free(client_secret);
        const scope = try allocator.dupe(u8, options.scope);
        return .{
            .allocator = allocator,
            .token_url = token_url,
            .client_id = client_id,
            .client_secret = client_secret,
            .scope = scope,
        };
    }

    pub fn deinit(self: *ClientCredentials) void {
        self.cache.clear(self.allocator);
        if (self.last_error) |value| self.allocator.free(value);
        std.crypto.secureZero(u8, self.client_secret);
        self.allocator.free(self.client_secret);
        self.allocator.free(self.client_id);
        self.allocator.free(self.token_url);
        self.allocator.free(self.scope);
    }

    /// The current access token, fetched or refreshed when needed. The slice is
    /// allocated with `allocator` and belongs to the caller, so concurrent refreshes
    /// by other threads cannot invalidate it.
    pub fn getToken(self: *ClientCredentials, allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return allocator.dupe(u8, try self.tokenLocked(io));
    }

    fn tokenLocked(self: *ClientCredentials, io: std.Io) ![]const u8 {
        const now = nowSeconds(io);
        if (self.cache.isFresh(now)) return self.cache.access_token.?;

        var form: std.ArrayList(u8) = .empty;
        defer form.deinit(self.allocator);
        try appendFormField(self.allocator, &form, "grant_type", "client_credentials");
        try appendFormField(self.allocator, &form, "client_id", self.client_id);
        try appendFormField(self.allocator, &form, "client_secret", self.client_secret);
        try appendFormField(self.allocator, &form, "scope", self.scope);

        const response = try postForm(self.allocator, io, self.token_url, form.items);
        defer self.allocator.free(response.body);
        if (response.status != .ok) {
            try self.recordError(response.body);
            return error.OAuthError;
        }
        const token = try parseTokenResponse(self.allocator, response.body);
        self.cache.replace(self.allocator, token, now);
        return self.cache.access_token.?;
    }

    fn recordError(self: *ClientCredentials, body: []const u8) !void {
        if (self.last_error) |value| self.allocator.free(value);
        self.last_error = try parseOAuthError(self.allocator, body);
    }

    /// Adapts this object to a client's `TokenProvider`. It must outlive the client.
    pub fn tokenProvider(self: *ClientCredentials, comptime Provider: type) Provider {
        return adapter(Provider, ClientCredentials, self);
    }
};

/// What a user needs to do to approve a device sign-in.
pub const DevicePrompt = struct {
    user_code: []const u8,
    verification_uri: []const u8,
    /// A ready to show instruction from the server, when it sent one.
    message: ?[]const u8,
};

const DeviceCodeBody = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    expires_in: i64 = 900,
    interval: i64 = 5,
    message: ?[]const u8 = null,
};

/// Signs a user in on another device: show them a code, then wait while they
/// approve it. Later calls reuse the refresh token instead of asking again.
pub const DeviceCode = struct {
    pub const Options = struct {
        token_url: []const u8,
        device_authorization_url: []const u8,
        url_params: []const UrlParam = &.{},
        client_id: []const u8,
        scope: []const u8,
        /// Called with the code the user has to enter. Print it or open a browser.
        on_prompt: *const fn (ctx: ?*anyopaque, prompt: DevicePrompt) void,
        prompt_ctx: ?*anyopaque = null,
    };

    allocator: std.mem.Allocator,
    token_url: []u8,
    device_authorization_url: []u8,
    client_id: []u8,
    scope: []u8,
    on_prompt: *const fn (ctx: ?*anyopaque, prompt: DevicePrompt) void,
    prompt_ctx: ?*anyopaque,
    mutex: std.Io.Mutex = .init,
    cache: TokenCache = .{},
    last_error: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) !DeviceCode {
        _ = io;
        const token_url = try expandUrl(allocator, options.token_url, options.url_params);
        errdefer allocator.free(token_url);
        const device_url = try expandUrl(allocator, options.device_authorization_url, options.url_params);
        errdefer allocator.free(device_url);
        const client_id = try allocator.dupe(u8, options.client_id);
        errdefer allocator.free(client_id);
        const scope = try allocator.dupe(u8, options.scope);
        return .{
            .allocator = allocator,
            .token_url = token_url,
            .device_authorization_url = device_url,
            .client_id = client_id,
            .scope = scope,
            .on_prompt = options.on_prompt,
            .prompt_ctx = options.prompt_ctx,
        };
    }

    pub fn deinit(self: *DeviceCode) void {
        self.cache.clear(self.allocator);
        if (self.last_error) |value| self.allocator.free(value);
        self.allocator.free(self.token_url);
        self.allocator.free(self.device_authorization_url);
        self.allocator.free(self.client_id);
        self.allocator.free(self.scope);
    }

    pub fn getToken(self: *DeviceCode, allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return allocator.dupe(u8, try self.tokenLocked(io));
    }

    fn tokenLocked(self: *DeviceCode, io: std.Io) ![]const u8 {
        const now = nowSeconds(io);
        if (self.cache.isFresh(now)) return self.cache.access_token.?;

        if (self.cache.refresh_token != null) {
            if (self.refresh(io, now)) |_| return self.cache.access_token.? else |err| {
                // Only a rejected grant means the user has to sign in again; a
                // network error or a 503 must not start a new sign in.
                if (err != error.OAuthError or !self.refreshNeedsSignIn()) return err;
            }
        }
        try self.signIn(io);
        return self.cache.access_token.?;
    }

    fn refresh(self: *DeviceCode, io: std.Io, now: i64) !void {
        var form: std.ArrayList(u8) = .empty;
        defer form.deinit(self.allocator);
        try appendFormField(self.allocator, &form, "grant_type", "refresh_token");
        try appendFormField(self.allocator, &form, "client_id", self.client_id);
        try appendFormField(self.allocator, &form, "refresh_token", self.cache.refresh_token.?);
        try appendFormField(self.allocator, &form, "scope", self.scope);

        const response = try postForm(self.allocator, io, self.token_url, form.items);
        defer self.allocator.free(response.body);
        if (response.status != .ok) {
            try self.recordError(response.body);
            return error.OAuthError;
        }
        var token = try parseTokenResponse(self.allocator, response.body);
        // Servers may omit a new refresh token; keep using the old one then.
        if (token.refresh_token == null and self.cache.refresh_token != null) {
            token.refresh_token = try self.allocator.dupe(u8, self.cache.refresh_token.?);
        }
        self.cache.replace(self.allocator, token, now);
    }

    fn signIn(self: *DeviceCode, io: std.Io) !void {
        var start_form: std.ArrayList(u8) = .empty;
        defer start_form.deinit(self.allocator);
        try appendFormField(self.allocator, &start_form, "client_id", self.client_id);
        try appendFormField(self.allocator, &start_form, "scope", self.scope);

        const started = try postForm(self.allocator, io, self.device_authorization_url, start_form.items);
        defer self.allocator.free(started.body);
        if (started.status != .ok) {
            try self.recordError(started.body);
            return error.OAuthError;
        }
        const code = std.json.parseFromSlice(DeviceCodeBody, self.allocator, started.body, .{ .ignore_unknown_fields = true }) catch return error.InvalidTokenResponse;
        defer code.deinit();

        self.on_prompt(self.prompt_ctx, .{
            .user_code = code.value.user_code,
            .verification_uri = code.value.verification_uri,
            .message = code.value.message,
        });

        var interval = @max(code.value.interval, 1);
        const deadline = nowSeconds(io) + code.value.expires_in;
        while (nowSeconds(io) < deadline) {
            try io.sleep(.fromSeconds(interval), .awake);

            var form: std.ArrayList(u8) = .empty;
            defer form.deinit(self.allocator);
            try appendFormField(self.allocator, &form, "grant_type", "urn:ietf:params:oauth:grant-type:device_code");
            try appendFormField(self.allocator, &form, "client_id", self.client_id);
            try appendFormField(self.allocator, &form, "device_code", code.value.device_code);

            const response = try postForm(self.allocator, io, self.token_url, form.items);
            defer self.allocator.free(response.body);
            if (response.status == .ok) {
                const token = try parseTokenResponse(self.allocator, response.body);
                self.cache.replace(self.allocator, token, nowSeconds(io));
                return;
            }
            const failure = (try parseOAuthError(self.allocator, response.body)) orelse return error.OAuthError;
            defer self.allocator.free(failure);
            if (std.mem.startsWith(u8, failure, "authorization_pending")) continue;
            if (std.mem.startsWith(u8, failure, "slow_down")) {
                interval += 5;
                continue;
            }
            if (std.mem.startsWith(u8, failure, "expired_token")) return error.DeviceCodeExpired;
            try self.recordError(response.body);
            return error.OAuthError;
        }
        return error.DeviceCodeExpired;
    }

    fn refreshNeedsSignIn(self: *const DeviceCode) bool {
        return errorNeedsSignIn(self.last_error);
    }

    fn recordError(self: *DeviceCode, body: []const u8) !void {
        if (self.last_error) |value| self.allocator.free(value);
        self.last_error = try parseOAuthError(self.allocator, body);
    }

    /// Adapts this object to a client's `TokenProvider`. It must outlive the client.
    pub fn tokenProvider(self: *DeviceCode, comptime Provider: type) Provider {
        return adapter(Provider, DeviceCode, self);
    }
};

test "expandUrl fills placeholders" {
    const url = try expandUrl(std.testing.allocator, "https://login.example.com/{tenant}/oauth2/{tenant}/token", &.{.{ .name = "tenant", .value = "contoso" }});
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("https://login.example.com/contoso/oauth2/contoso/token", url);
}

test "expandUrl rejects unknown placeholders" {
    try std.testing.expectError(error.UnknownUrlParameter, expandUrl(std.testing.allocator, "https://x/{tenant}", &.{}));
    try std.testing.expectError(error.UnknownUrlParameter, expandUrl(std.testing.allocator, "https://x/{open", &.{}));
}

test "form fields are percent encoded" {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    try appendFormField(std.testing.allocator, &body, "scope", "https://graph.example.com/.default offline_access");
    try appendFormField(std.testing.allocator, &body, "client_secret", "a+b&c=d~e");
    try std.testing.expectEqualStrings("scope=https%3A%2F%2Fgraph.example.com%2F.default%20offline_access&client_secret=a%2Bb%26c%3Dd~e", body.items);
}

test "token responses are parsed with and without optional fields" {
    var full = try parseTokenResponse(std.testing.allocator, "{\"token_type\":\"Bearer\",\"access_token\":\"abc\",\"expires_in\":3599,\"refresh_token\":\"ref\"}");
    defer full.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("abc", full.access_token);
    try std.testing.expectEqualStrings("ref", full.refresh_token.?);
    try std.testing.expectEqual(@as(i64, 3599), full.expires_in.?);

    var minimal = try parseTokenResponse(std.testing.allocator, "{\"access_token\":\"abc\"}");
    defer minimal.deinit(std.testing.allocator);
    try std.testing.expect(minimal.refresh_token == null);
    try std.testing.expect(minimal.expires_in == null);

    try std.testing.expectError(error.InvalidTokenResponse, parseTokenResponse(std.testing.allocator, "{\"nope\":1}"));
    try std.testing.expectError(error.InvalidTokenResponse, parseTokenResponse(std.testing.allocator, "not json"));
}

test "oauth errors are summarized" {
    const with_description = (try parseOAuthError(std.testing.allocator, "{\"error\":\"invalid_client\",\"error_description\":\"Bad secret\"}")).?;
    defer std.testing.allocator.free(with_description);
    try std.testing.expectEqualStrings("invalid_client: Bad secret", with_description);

    const code_only = (try parseOAuthError(std.testing.allocator, "{\"error\":\"authorization_pending\"}")).?;
    defer std.testing.allocator.free(code_only);
    try std.testing.expectEqualStrings("authorization_pending", code_only);

    try std.testing.expect((try parseOAuthError(std.testing.allocator, "<html>")) == null);
}

test "cached tokens are replaced a minute before they expire" {
    var cache: TokenCache = .{};
    defer cache.clear(std.testing.allocator);
    try std.testing.expect(!cache.isFresh(0));

    const access = try std.testing.allocator.dupe(u8, "abc");
    cache.replace(std.testing.allocator, .{ .access_token = access, .refresh_token = null, .expires_in = 3600 }, 1000);
    try std.testing.expect(cache.isFresh(1000));
    try std.testing.expect(cache.isFresh(1000 + 3600 - refresh_margin_seconds - 1));
    try std.testing.expect(!cache.isFresh(1000 + 3600 - refresh_margin_seconds));
}

test "client credentials expand the token url and keep their settings" {
    var credentials = try ClientCredentials.init(std.testing.allocator, std.testing.io, .{
        .token_url = "https://login.example.com/{tenant}/token",
        .url_params = &.{.{ .name = "tenant", .value = "contoso" }},
        .client_id = "id",
        .client_secret = "secret",
        .scope = "api://x/.default",
    });
    defer credentials.deinit();
    try std.testing.expectEqualStrings("https://login.example.com/contoso/token", credentials.token_url);
    try std.testing.expectEqualStrings("api://x/.default", credentials.scope);
}

const TestProvider = struct {
    ctx: *anyopaque,
    getTokenFn: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, io: std.Io) anyerror![]const u8,
};

test "credentials adapt to a token provider and serve a cached token" {
    var credentials = try ClientCredentials.init(std.testing.allocator, std.testing.io, .{
        .token_url = "https://login.example.com/token",
        .client_id = "id",
        .client_secret = "secret",
        .scope = "s",
    });
    defer credentials.deinit();
    // A fresh token in the cache means no request is made.
    const access = try std.testing.allocator.dupe(u8, "cached-token");
    credentials.cache.replace(std.testing.allocator, .{ .access_token = access, .refresh_token = null, .expires_in = 3600 }, nowSeconds(std.testing.io));

    const provider = credentials.tokenProvider(TestProvider);
    const token = try provider.getTokenFn(provider.ctx, std.testing.allocator, std.testing.io);
    defer std.testing.allocator.free(token);
    try std.testing.expectEqualStrings("cached-token", token);
}

fn ignorePrompt(_: ?*anyopaque, _: DevicePrompt) void {}

test "device code serves a cached token and compiles its sign in flow" {
    var device = try DeviceCode.init(std.testing.allocator, std.testing.io, .{
        .token_url = "https://login.example.com/{tenant}/token",
        .device_authorization_url = "https://login.example.com/{tenant}/devicecode",
        .url_params = &.{.{ .name = "tenant", .value = "contoso" }},
        .client_id = "id",
        .scope = "s",
        .on_prompt = ignorePrompt,
    });
    defer device.deinit();
    try std.testing.expectEqualStrings("https://login.example.com/contoso/devicecode", device.device_authorization_url);

    const access = try std.testing.allocator.dupe(u8, "device-token");
    device.cache.replace(std.testing.allocator, .{ .access_token = access, .refresh_token = null, .expires_in = 3600 }, nowSeconds(std.testing.io));
    const provider = device.tokenProvider(TestProvider);
    const token = try provider.getTokenFn(provider.ctx, std.testing.allocator, std.testing.io);
    defer std.testing.allocator.free(token);
    try std.testing.expectEqualStrings("device-token", token);
}

/// Whether the last OAuth error says the refresh token is no longer usable.
fn errorNeedsSignIn(message: ?[]const u8) bool {
    const text = message orelse return false;
    return std.mem.startsWith(u8, text, "invalid_grant") or std.mem.startsWith(u8, text, "interaction_required");
}

test "only rejected grants send the user back to sign in" {
    try std.testing.expect(errorNeedsSignIn("invalid_grant: expired"));
    try std.testing.expect(errorNeedsSignIn("interaction_required"));
    try std.testing.expect(!errorNeedsSignIn("temporarily_unavailable"));
    try std.testing.expect(!errorNeedsSignIn(null));
}
