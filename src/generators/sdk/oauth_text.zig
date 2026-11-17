//! Text for the OAuth parts of an SDK: the helpers in `root.zig` and the
//! variables the OAuth examples are built from.

const std = @import("std");
const config_mod = @import("config.zig");

/// The `{name}` placeholders of a URL template, in order of first use. Names
/// that are not valid Zig identifiers are left out.
pub fn placeholders(arena: std.mem.Allocator, template_url: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, template_url, i, '{')) |open| {
        const close = std.mem.indexOfScalarPos(u8, template_url, open, '}') orelse break;
        const name = template_url[open + 1 .. close];
        i = close + 1;
        var valid = name.len > 0 and !std.ascii.isDigit(name[0]);
        for (name) |c| valid = valid and (std.ascii.isAlphanumeric(c) or c == '_');
        if (!valid) continue;
        var seen = false;
        for (names.items) |existing| seen = seen or std.mem.eql(u8, existing, name);
        if (!seen) try names.append(arena, name);
    }
    return names.items;
}

fn escapeZigString(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text) |c| {
        if (c == '"' or c == '\\') try out.append(arena, '\\');
        try out.append(arena, c);
    }
    return out.items;
}

/// One `const tenant = init.environ_map.get("TENANT") orelse ...` per URL placeholder.
pub fn envLines(arena: std.mem.Allocator, oauth2: ?config_mod.OAuth2) ![]const u8 {
    const settings = oauth2 orelse return "";
    var out: std.ArrayList(u8) = .empty;
    for (try placeholders(arena, settings.token_url)) |name| {
        const upper = try std.ascii.allocUpperString(arena, name);
        try out.print(arena, "    const {s} = init.environ_map.get(\"{s}\") orelse {{\n", .{ name, upper });
        try out.print(arena, "        std.debug.print(\"Set the {s} environment variable\\n\", .{{}});\n", .{upper});
        try out.appendSlice(arena, "        return error.MissingEnvironmentVariable;\n    };\n");
    }
    return out.items;
}

/// The entries of the `[]const auth.UrlParam` literal passed to the helpers.
pub fn paramsLiteral(arena: std.mem.Allocator, oauth2: ?config_mod.OAuth2) ![]const u8 {
    const settings = oauth2 orelse return "";
    var out: std.ArrayList(u8) = .empty;
    for (try placeholders(arena, settings.token_url)) |name| {
        try out.print(arena, "        .{{ .name = \"{s}\", .value = {s} }},\n", .{ name, name });
    }
    return out.items;
}

/// The part of `root.zig` that exposes the OAuth helpers.
pub fn rootBlock(arena: std.mem.Allocator, oauth2: ?config_mod.OAuth2) ![]const u8 {
    const settings = oauth2 orelse return "";
    var out: std.ArrayList(u8) = .empty;
    const scope = try std.mem.join(arena, " ", settings.scopes);

    try out.appendSlice(arena,
        \\
        \\/// OAuth 2.0 token acquisition: `auth.ClientCredentials` and `auth.DeviceCode`.
        \\pub const auth = @import("auth.zig");
        \\
        \\/// The OAuth endpoints of this API. URLs may contain `{name}` placeholders
        \\/// that you fill in through `auth.UrlParam`.
        \\pub const oauth = struct {
        \\
    );
    try out.print(arena, "    pub const token_url = \"{s}\";\n", .{try escapeZigString(arena, settings.token_url)});
    if (settings.device_authorization_url) |url| {
        try out.print(arena, "    pub const device_authorization_url = \"{s}\";\n", .{try escapeZigString(arena, url)});
    }
    try out.print(arena, "    pub const scope = \"{s}\";\n}};\n", .{try escapeZigString(arena, scope)});

    try out.appendSlice(arena,
        \\
        \\/// Gets app-only tokens with a client secret. Use `credentials.tokenProvider(TokenProvider)`.
        \\pub fn clientCredentials(allocator: std.mem.Allocator, io: std.Io, url_params: []const auth.UrlParam, client_id: []const u8, client_secret: []const u8) !auth.ClientCredentials {
        \\    return auth.ClientCredentials.init(allocator, io, .{
        \\        .token_url = oauth.token_url,
        \\        .url_params = url_params,
        \\        .client_id = client_id,
        \\        .client_secret = client_secret,
        \\        .scope = oauth.scope,
        \\    });
        \\}
        \\
    );
    if (settings.device_authorization_url != null) {
        try out.appendSlice(arena,
            \\
            \\/// Signs a user in on another device. `on_prompt` shows them the code to enter.
            \\pub fn deviceCode(allocator: std.mem.Allocator, io: std.Io, url_params: []const auth.UrlParam, client_id: []const u8, on_prompt: *const fn (ctx: ?*anyopaque, prompt: auth.DevicePrompt) void) !auth.DeviceCode {
            \\    return auth.DeviceCode.init(allocator, io, .{
            \\        .token_url = oauth.token_url,
            \\        .device_authorization_url = oauth.device_authorization_url,
            \\        .url_params = url_params,
            \\        .client_id = client_id,
            \\        .scope = oauth.scope,
            \\        .on_prompt = on_prompt,
            \\    });
            \\}
            \\
        );
    }
    return out.items;
}
