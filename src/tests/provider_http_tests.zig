const std = @import("std");
const sdk = @import("provider_fixture");

const Server = struct {
    listener: std.Io.net.Server,
    streaming: bool,
    redirect: bool = false,
    failure: ?anyerror = null,

    fn serve(self: *Server) void {
        self.handle() catch |err| {
            self.failure = err;
        };
    }

    fn handle(self: *Server) !void {
        const io = std.testing.io;
        var connection = try self.listener.accept(io);
        defer connection.close(io);
        var in_buffer: [8192]u8 = undefined;
        var out_buffer: [8192]u8 = undefined;
        var input = connection.reader(io, &in_buffer);
        var output = connection.writer(io, &out_buffer);
        var server = std.http.Server.init(&input.interface, &output.interface);
        var request = try server.receiveHead();
        try std.testing.expectEqualStrings("/v1/messages", request.head.target);
        var headers = request.iterateHeaders();
        var version = false;
        var profile = false;
        var workspace = false;
        var authorization = false;
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "anthropic-version")) {
                try std.testing.expect(!version);
                version = true;
                try std.testing.expectEqualStrings("fixture-version", header.value);
            }
            if (std.ascii.eqlIgnoreCase(header.name, "anthropic-user-profile-id")) {
                profile = true;
                try std.testing.expectEqualStrings("profile", header.value);
            }
            if (std.ascii.eqlIgnoreCase(header.name, "anthropic-workspace-id")) {
                workspace = true;
                try std.testing.expectEqualStrings("workspace", header.value);
            }
            if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
                authorization = true;
                try std.testing.expectEqualStrings("Bearer fixture-key", header.value);
            }
        }
        try std.testing.expect(version and profile and workspace and authorization);
        var body_buffer: [4096]u8 = undefined;
        const body_reader = request.readerExpectNone(&body_buffer);
        const body = try body_reader.allocRemaining(std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(self.streaming, parsed.value.object.get("stream").?.bool);
        if (self.redirect) {
            try request.respond("redirect body", .{
                .status = .found,
                .keep_alive = false,
                .extra_headers = &.{.{ .name = "Location", .value = "http://127.0.0.1:1/credentials-must-not-arrive" }},
            });
            return;
        }
        try request.respond(if (self.streaming) "data: {\"text\":\"hello\"}\n\ndata: [DONE]\n\n" else "{}", .{
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Type", .value = if (self.streaming) "text/event-stream" else "application/json" }},
        });
    }
};

const Callback = struct {
    count: usize = 0,
    pub fn event(self: *@This(), data: []const u8) !void {
        try std.testing.expectEqualStrings("{\"text\":\"hello\"}", data);
        self.count += 1;
    }
};

const Event = struct { text: []const u8 };
const TypedCallback = struct {
    count: usize = 0,
    pub fn event(self: *@This(), data: *const Event) !void {
        try std.testing.expectEqualStrings("hello", data.text);
        self.count += 1;
    }
};

test "generated requests and streams forward optional headers over HTTP" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    for (0..6) |mode| {
        const address: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.loopback(0) };
        var context: Server = .{ .listener = try address.listen(io, .{}), .streaming = mode != 0 and mode != 4, .redirect = mode >= 4 };
        defer context.listener.deinit(io);
        const thread = try std.Thread.spawn(.{}, Server.serve, .{&context});
        var joined = false;
        defer if (!joined) thread.join();
        const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{context.listener.socket.address.getPort()});
        defer allocator.free(url);
        var client = sdk.Client.init(allocator, io, "fixture-key");
        defer client.deinit();
        client.withBaseUrl(url);
        client.default_headers = if (mode == 3) &.{
            .{ .name = "Anthropic-Version", .value = "fixture-version" },
            .{ .name = "anthropic-user-profile-id", .value = "profile" },
            .{ .name = "anthropic-workspace-id", .value = "workspace" },
        } else &.{.{ .name = "Anthropic-Version", .value = "default-version" }};
        if (mode == 0) {
            var result = if (comptime @hasDecl(sdk, "messages_postOptions"))
                try sdk.resources.messages.create(&client, .{ .@"anthropic-version" = "fixture-version", .@"anthropic-user-profile-id" = "profile", .@"anthropic-workspace-id" = "workspace" }, .{ .stream = false })
            else
                try sdk.resources.messages.create(&client, "fixture-version", "profile", "workspace", .{ .stream = false });
            defer result.deinit();
        } else if (mode == 1) {
            var callback: Callback = .{};
            if (comptime @hasDecl(sdk, "messages_postOptions")) {
                try sdk.messages_postStreaming(&client, .{ .@"anthropic-version" = "fixture-version", .@"anthropic-user-profile-id" = "profile", .@"anthropic-workspace-id" = "workspace" }, .{ .stream = false }, &callback, null);
            } else {
                try sdk.messages_postStreaming(&client, "fixture-version", "profile", "workspace", .{ .stream = false }, &callback, null);
            }
            try std.testing.expectEqual(@as(usize, 1), callback.count);
        } else if (mode == 2) {
            var callback: TypedCallback = .{};
            if (comptime @hasDecl(sdk, "messages_postOptions")) {
                try sdk.resources.messages.createStreamEvents(Event, &client, .{ .@"anthropic-version" = "fixture-version", .@"anthropic-user-profile-id" = "profile", .@"anthropic-workspace-id" = "workspace" }, .{ .stream = false }, &callback, null);
            } else {
                try sdk.resources.messages.createStreamEvents(Event, &client, "fixture-version", "profile", "workspace", .{ .stream = false }, &callback, null);
            }
            try std.testing.expectEqual(@as(usize, 1), callback.count);
        } else if (mode == 3) {
            var callback: Callback = .{};
            if (comptime @hasDecl(sdk, "messages_postOptions")) {
                try sdk.messages_postStreaming(&client, .{}, .{ .stream = false }, &callback, null);
            } else {
                try sdk.messages_postStreaming(&client, null, null, null, .{ .stream = false }, &callback, null);
            }
            try std.testing.expectEqual(@as(usize, 1), callback.count);
        } else if (mode == 4) {
            var result = if (comptime @hasDecl(sdk, "messages_postOptions"))
                try sdk.messages_postRaw(&client, .{ .@"anthropic-version" = "fixture-version", .@"anthropic-user-profile-id" = "profile", .@"anthropic-workspace-id" = "workspace" }, .{ .stream = false })
            else
                try sdk.messages_postRaw(&client, "fixture-version", "profile", "workspace", .{ .stream = false });
            defer result.deinit();
            try std.testing.expectEqual(std.http.Status.found, result.status);
            try std.testing.expectEqualStrings("redirect body", result.body);
        } else {
            var callback: Callback = .{};
            const result = if (comptime @hasDecl(sdk, "messages_postOptions"))
                sdk.messages_postStreaming(&client, .{ .@"anthropic-version" = "fixture-version", .@"anthropic-user-profile-id" = "profile", .@"anthropic-workspace-id" = "workspace" }, .{ .stream = false }, &callback, null)
            else
                sdk.messages_postStreaming(&client, "fixture-version", "profile", "workspace", .{ .stream = false }, &callback, null);
            try std.testing.expectError(error.ResponseError, result);
            try std.testing.expectEqual(@as(usize, 0), callback.count);
        }
        thread.join();
        joined = true;
        if (context.failure) |err| return err;
    }
}

const RedirectHop = struct {
    listener: std.Io.net.Server,
    location: ?[]const u8 = null,
    /// Per-redirect targets, used instead of `location` for a chain of redirects.
    locations: ?[]const []const u8 = null,
    /// Requests answered with `location` before a final 200 response.
    redirects: usize = 0,
    redirect_status: std.http.Status = .moved_permanently,
    requests: usize = 1,
    saw_method: [8]?std.http.Method = @splat(null),
    saw_authorization: [8]bool = @splat(false),
    saw_default_header: [8]bool = @splat(false),
    failure: ?anyerror = null,

    fn serve(self: *RedirectHop) void {
        for (0..self.requests) |index| {
            self.handle(index) catch |err| {
                self.failure = err;
                return;
            };
        }
    }

    fn handle(self: *RedirectHop, index: usize) !void {
        const io = std.testing.io;
        var connection = try self.listener.accept(io);
        defer connection.close(io);
        var in_buffer: [8192]u8 = undefined;
        var out_buffer: [8192]u8 = undefined;
        var input = connection.reader(io, &in_buffer);
        var output = connection.writer(io, &out_buffer);
        var server = std.http.Server.init(&input.interface, &output.interface);
        var request = try server.receiveHead();
        self.saw_method[index] = request.head.method;
        var headers = request.iterateHeaders();
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "authorization")) self.saw_authorization[index] = true;
            if (std.ascii.eqlIgnoreCase(header.name, "x-provider-key")) self.saw_default_header[index] = true;
        }
        if (index < self.redirects) {
            try request.respond("", .{
                .status = self.redirect_status,
                .keep_alive = false,
                .extra_headers = &.{.{ .name = "Location", .value = if (self.locations) |locations| locations[index] else self.location.? }},
            });
            return;
        }
        try request.respond("{}", .{
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
        });
    }
};

fn unblockAccept(hop: *RedirectHop) void {
    const stream = hop.listener.socket.address.connect(std.testing.io, .{ .mode = .stream }) catch return;
    stream.close(std.testing.io);
}

fn listenLoopback() !std.Io.net.Server {
    const address: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.loopback(0) };
    return address.listen(std.testing.io, .{});
}

fn initRedirectClient(hop: *RedirectHop, url_buffer: []u8) !sdk.Client {
    var client = sdk.Client.init(std.testing.allocator, std.testing.io, "fixture-key");
    client.withBaseUrl(try std.fmt.bufPrint(url_buffer, "http://127.0.0.1:{d}", .{hop.listener.socket.address.getPort()}));
    client.default_headers = &.{.{ .name = "X-Provider-Key", .value = "fixture-secret" }};
    return client;
}

fn expectRedirectKeepsCredentials(call: *const fn (*sdk.Client) anyerror!void, require_authorization: bool) !void {
    var origin: RedirectHop = .{ .listener = try listenLoopback(), .location = "/moved", .redirects = 1, .requests = 2 };
    defer origin.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    var client = try initRedirectClient(&origin, &url_buffer);
    defer client.deinit();
    const thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&origin});
    defer thread.join();
    call(&client) catch |err| {
        unblockAccept(&origin);
        return err;
    };
    try std.testing.expect(origin.saw_default_header[0] and origin.saw_default_header[1]);
    try std.testing.expectEqual(origin.saw_authorization[0], origin.saw_authorization[1]);
    if (require_authorization) try std.testing.expect(origin.saw_authorization[0]);
}

fn expectRedirectDropsCredentials(target_host: []const u8, call: *const fn (*sdk.Client) anyerror!void) !void {
    var target: RedirectHop = .{ .listener = try listenLoopback() };
    defer target.listener.deinit(std.testing.io);
    var location_buffer: [64]u8 = undefined;
    const location = try std.fmt.bufPrint(&location_buffer, "http://{s}:{d}/moved", .{ target_host, target.listener.socket.address.getPort() });
    var origin: RedirectHop = .{ .listener = try listenLoopback(), .location = location, .redirects = 1 };
    defer origin.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    var client = try initRedirectClient(&origin, &url_buffer);
    defer client.deinit();
    const origin_thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&origin});
    defer origin_thread.join();
    const target_thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&target});
    defer target_thread.join();
    call(&client) catch |err| {
        unblockAccept(&target);
        return err;
    };
    try std.testing.expect(origin.saw_default_header[0]);
    try std.testing.expect(!target.saw_authorization[0] and !target.saw_default_header[0]);
}

fn expectRawOk(raw: anytype) !void {
    var response = raw;
    defer response.deinit();
    try std.testing.expectEqual(std.http.Status.ok, response.status);
}

fn requestRawCall(client: *sdk.Client) anyerror!void {
    const url = try std.fmt.allocPrint(client.allocator, "{s}/v1/models", .{client.base_url});
    defer client.allocator.free(url);
    try expectRawOk(try sdk.requestRaw(client, .GET, url, null));
}

const redirect_calls = [_]*const fn (*sdk.Client) anyerror!void{
    struct {
        fn call(client: *sdk.Client) anyerror!void {
            try expectRawOk(try sdk.models_listRaw(client));
        }
    }.call,
    struct {
        fn call(client: *sdk.Client) anyerror!void {
            try sdk.@"operationv1/direct-empty"(client);
        }
    }.call,
    struct {
        fn call(client: *sdk.Client) anyerror!void {
            var response = try sdk.@"operationv1/direct-body"(client);
            response.deinit();
        }
    }.call,
};

test "generated GET calls follow redirects and keep credentials on the same origin" {
    for (redirect_calls) |call| try expectRedirectKeepsCredentials(call, true);
    // A raw request carries no operation security, so only the default header is sent.
    try expectRedirectKeepsCredentials(requestRawCall, false);
}

test "generated GET calls drop credentials when a redirect changes host" {
    for (redirect_calls) |call| try expectRedirectDropsCredentials("localhost", call);
    try expectRedirectDropsCredentials("localhost", requestRawCall);
}

test "generated GET calls drop credentials when a redirect changes port" {
    for (redirect_calls) |call| try expectRedirectDropsCredentials("127.0.0.1", call);
    try expectRedirectDropsCredentials("127.0.0.1", requestRawCall);
}

test "generated GET calls drop credentials when a later redirect changes origin" {
    var target: RedirectHop = .{ .listener = try listenLoopback() };
    defer target.listener.deinit(std.testing.io);
    var location_buffer: [64]u8 = undefined;
    const cross_origin = try std.fmt.bufPrint(&location_buffer, "http://127.0.0.1:{d}/moved", .{target.listener.socket.address.getPort()});
    const locations = [_][]const u8{ "/same-origin", cross_origin };
    var origin: RedirectHop = .{ .listener = try listenLoopback(), .locations = &locations, .redirects = 2, .requests = 2 };
    defer origin.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    var client = try initRedirectClient(&origin, &url_buffer);
    defer client.deinit();
    const origin_thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&origin});
    defer origin_thread.join();
    defer unblockAccept(&origin);
    const target_thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&target});
    defer target_thread.join();
    defer unblockAccept(&target);
    try expectRawOk(try sdk.models_listRaw(&client));
    try std.testing.expect(origin.saw_authorization[0] and origin.saw_authorization[1]);
    try std.testing.expect(origin.saw_default_header[0] and origin.saw_default_header[1]);
    try std.testing.expectEqual(std.http.Method.GET, target.saw_method[0].?);
    try std.testing.expect(!target.saw_authorization[0] and !target.saw_default_header[0]);
}

test "origins compare effective ports, schemes and hosts" {
    const same = [_][2][]const u8{
        .{ "https://api.example/a", "https://api.example:443/b" },
        .{ "http://api.example:80/a", "http://api.example/b" },
        .{ "https://api.example:8443/a", "https://API.example:8443/b" },
    };
    for (same) |pair| {
        try std.testing.expect(sdk.isSameOrigin(try std.Uri.parse(pair[0]), try std.Uri.parse(pair[1])));
    }
    const different = [_][2][]const u8{
        .{ "https://api.example/a", "http://api.example/a" },
        .{ "https://api.example/a", "http://api.example:443/a" },
        .{ "https://api.example/a", "https://api.example:8443/a" },
        .{ "http://api.example/a", "http://api.example:443/a" },
        .{ "https://api.example/a", "https://other.example/a" },
    };
    for (different) |pair| {
        try std.testing.expect(!sdk.isSameOrigin(try std.Uri.parse(pair[0]), try std.Uri.parse(pair[1])));
    }
}

test "a 303 redirect keeps a HEAD request as HEAD" {
    var origin: RedirectHop = .{ .listener = try listenLoopback(), .location = "/moved", .redirects = 1, .redirect_status = .see_other, .requests = 2 };
    defer origin.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    var client = try initRedirectClient(&origin, &url_buffer);
    defer client.deinit();
    const thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&origin});
    defer thread.join();
    defer unblockAccept(&origin);
    const url = try std.fmt.allocPrint(client.allocator, "{s}/v1/models", .{client.base_url});
    defer client.allocator.free(url);
    try expectRawOk(try sdk.requestRaw(&client, .HEAD, url, null));
    try std.testing.expectEqual(std.http.Method.HEAD, origin.saw_method[1].?);
}

test "a 303 redirect turns other bodiless methods into GET" {
    var origin: RedirectHop = .{ .listener = try listenLoopback(), .location = "/moved", .redirects = 1, .redirect_status = .see_other, .requests = 2 };
    defer origin.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    var client = try initRedirectClient(&origin, &url_buffer);
    defer client.deinit();
    const thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&origin});
    defer thread.join();
    defer unblockAccept(&origin);
    const url = try std.fmt.allocPrint(client.allocator, "{s}/v1/models", .{client.base_url});
    defer client.allocator.free(url);
    try expectRawOk(try sdk.requestRaw(&client, .DELETE, url, null));
    try std.testing.expectEqual(std.http.Method.GET, origin.saw_method[1].?);
}

test "generated GET calls give up after three redirects" {
    var origin: RedirectHop = .{ .listener = try listenLoopback(), .location = "/moved", .redirects = 4, .requests = 4 };
    defer origin.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    var client = try initRedirectClient(&origin, &url_buffer);
    defer client.deinit();
    const thread = try std.Thread.spawn(.{}, RedirectHop.serve, .{&origin});
    defer thread.join();
    try std.testing.expectError(error.TooManyHttpRedirects, sdk.models_listRaw(&client));
}

/// Answers without a Content-Length, then holds the connection open, which is
/// how GitHub behaves. A client that reads to the end of the connection stalls.
const BodilessResponseServer = struct {
    listener: std.Io.net.Server,
    response: []const u8,
    requests: usize = 1,
    served: usize = 0,
    failure: ?anyerror = null,

    const hold_open: std.Io.Duration = .fromSeconds(2);

    fn serve(self: *BodilessResponseServer) void {
        self.handle() catch |err| {
            self.failure = err;
        };
    }

    fn handle(self: *BodilessResponseServer) !void {
        const io = std.testing.io;
        var connection = try self.listener.accept(io);
        defer connection.close(io);
        var in_buffer: [8192]u8 = undefined;
        var out_buffer: [8192]u8 = undefined;
        var input = connection.reader(io, &in_buffer);
        var output = connection.writer(io, &out_buffer);
        var server = std.http.Server.init(&input.interface, &output.interface);
        while (self.served < self.requests) {
            var request = try server.receiveHead();
            if (request.head.content_length) |length| {
                _ = try (try request.readerExpectContinue(&.{})).discard(.limited64(length));
            }
            // Count before answering, because the client returns as soon as it has the head.
            self.served += 1;
            try output.interface.writeAll(self.response);
            try output.interface.flush();
        }
        try io.sleep(hold_open, .awake);
    }
};

fn expectBodilessResponseReturnsPromptly(
    response: []const u8,
    expected: std.http.Status,
    method: std.http.Method,
    payload: ?[]const u8,
) !void {
    const io = std.testing.io;
    var server: BodilessResponseServer = .{ .listener = try listenLoopback(), .response = response };
    defer server.listener.deinit(io);
    const thread = try std.Thread.spawn(.{}, BodilessResponseServer.serve, .{&server});
    defer thread.join();

    var client = sdk.Client.init(std.testing.allocator, io, "fixture-key");
    defer client.deinit();
    var url_buffer: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buffer, "http://127.0.0.1:{d}/item", .{server.listener.socket.address.getPort()});

    const start = std.Io.Clock.awake.now(io);
    var raw = try sdk.requestRaw(&client, method, url, payload);
    defer raw.deinit();
    const elapsed = start.untilNow(io, .awake);

    try std.testing.expectEqual(expected, raw.status);
    try std.testing.expectEqualStrings("", raw.body);
    try std.testing.expect(elapsed.nanoseconds < BodilessResponseServer.hold_open.nanoseconds / 2);
}

test "a 204 response to a request without a body returns without waiting for the connection to close" {
    try expectBodilessResponseReturnsPromptly("HTTP/1.1 204 No Content\r\n\r\n", .no_content, .GET, null);
    try expectBodilessResponseReturnsPromptly("HTTP/1.1 204 No Content\r\n\r\n", .no_content, .DELETE, null);
}

test "a 204 response to a request with a body returns without waiting for the connection to close" {
    try expectBodilessResponseReturnsPromptly("HTTP/1.1 204 No Content\r\n\r\n", .no_content, .PUT, "{}");
}

test "a 304 response returns without waiting for the connection to close" {
    try expectBodilessResponseReturnsPromptly("HTTP/1.1 304 Not Modified\r\n\r\n", .not_modified, .GET, null);
}

test "the connection is reused after a 204 response" {
    const io = std.testing.io;
    var server: BodilessResponseServer = .{ .listener = try listenLoopback(), .response = "HTTP/1.1 204 No Content\r\n\r\n", .requests = 2 };
    defer server.listener.deinit(io);
    const thread = try std.Thread.spawn(.{}, BodilessResponseServer.serve, .{&server});
    defer thread.join();

    var client = sdk.Client.init(std.testing.allocator, io, "fixture-key");
    defer client.deinit();
    var url_buffer: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buffer, "http://127.0.0.1:{d}/item", .{server.listener.socket.address.getPort()});

    for (0..2) |_| {
        var raw = try sdk.requestRaw(&client, .GET, url, null);
        defer raw.deinit();
        try std.testing.expectEqual(std.http.Status.no_content, raw.status);
    }
    try std.testing.expectEqual(@as(usize, 2), server.served);
}

const CorruptGzipServer = struct {
    listener: std.Io.net.Server,
    failure: ?anyerror = null,

    fn serve(self: *CorruptGzipServer) void {
        self.handle() catch |err| {
            self.failure = err;
        };
    }

    fn handle(self: *CorruptGzipServer) !void {
        const io = std.testing.io;
        var connection = try self.listener.accept(io);
        defer connection.close(io);
        var in_buffer: [8192]u8 = undefined;
        var out_buffer: [8192]u8 = undefined;
        var input = connection.reader(io, &in_buffer);
        var output = connection.writer(io, &out_buffer);
        var server = std.http.Server.init(&input.interface, &output.interface);
        var request = try server.receiveHead();
        // A valid gzip header followed by a deflate block of the reserved type.
        try request.respond("\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\xff\xff\xff\xff", .{
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Encoding", .value = "gzip" }},
        });
    }
};

test "generated GET calls return an error for a corrupt gzip response" {
    var context: CorruptGzipServer = .{ .listener = try listenLoopback() };
    defer context.listener.deinit(std.testing.io);
    var url_buffer: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buffer, "http://127.0.0.1:{d}", .{context.listener.socket.address.getPort()});
    var client = sdk.Client.init(std.testing.allocator, std.testing.io, "");
    defer client.deinit();
    const thread = try std.Thread.spawn(.{}, CorruptGzipServer.serve, .{&context});
    const result = sdk.requestRaw(&client, .GET, url, null);
    thread.join();
    if (context.failure) |err| return err;
    try std.testing.expectError(error.ReadFailed, result);
}
