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
                try sdk.resources.messages.messages_postStreamEvents(Event, &client, .{ .@"anthropic-version" = "fixture-version", .@"anthropic-user-profile-id" = "profile", .@"anthropic-workspace-id" = "workspace" }, .{ .stream = false }, &callback, null);
            } else {
                try sdk.resources.messages.messages_postStreamEvents(Event, &client, "fixture-version", "profile", "workspace", .{ .stream = false }, &callback, null);
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
