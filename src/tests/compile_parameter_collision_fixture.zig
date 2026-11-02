const std = @import("std");
const sdk = @import("collision_fixture");

const parameter_names = [_][]const u8{
    "client", "callback", "callback_param", "callback_param1", "cancellation_token", "Event", "self", "allocator", "requestBody", "uri_buf", "first_query", "auth_header", "header_value", "value", "create", "create_param", "widgets", "widgets_param", "Widget", "Widget_param", "helper", "createWidget", "execute", "operation_headers", "operation_headers_", "operation_header_values__", "payload", "result", "WidgetsClient", "CreateWidget", "std",
};
const parameter_types: [parameter_names.len]type = @splat([]const u8);
const FlatArgs = @Tuple(&parameter_types);
const flat_arguments: FlatArgs = args: {
    var result: FlatArgs = undefined;
    for (parameter_names, 0..) |name, i| result[i] = name ++ "-wire";
    break :args result;
};

fn parameterArguments() if (@hasDecl(sdk, "createWidgetOptions")) @Tuple(&.{sdk.createWidgetOptions}) else FlatArgs {
    if (comptime @hasDecl(sdk, "createWidgetOptions")) {
        var options: sdk.createWidgetOptions = undefined;
        inline for (parameter_names) |name| @field(options, name) = name ++ "-wire";
        return .{options};
    }
    return flat_arguments;
}

const Event = struct { text: []const u8 };
const Callback = struct {
    count: usize = 0,
    pub fn event(self: *@This(), data: anytype) !void {
        if (comptime @TypeOf(data) == []const u8 or @TypeOf(data) == []u8) {
            try std.testing.expectEqualStrings("{\"text\":\"hello\"}", data);
        } else {
            try std.testing.expectEqualStrings("hello", data.text);
        }
        self.count += 1;
    }
};

const Server = struct {
    listener: std.Io.net.Server,
    streaming: bool,
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
        var in_buffer: [16384]u8 = undefined;
        var out_buffer: [8192]u8 = undefined;
        var input = connection.reader(io, &in_buffer);
        var output = connection.writer(io, &out_buffer);
        var server = std.http.Server.init(&input.interface, &output.interface);
        var request = try server.receiveHead();
        var expected: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer expected.deinit();
        try expected.writer.writeAll("/widgets/client-wire");
        inline for (parameter_names, 0..) |name, i| {
            if (i != 0 and !std.mem.eql(u8, name, "auth_header") and !std.mem.eql(u8, name, "header_value")) {
                try expected.writer.print("{s}{s}={s}-wire", .{ if (i == 1) "?" else "&", name, name });
            }
        }
        try std.testing.expectEqualStrings(expected.written(), request.head.target);
        var headers = request.iterateHeaders();
        var auth_header = false;
        var header_value = false;
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "auth_header")) {
                try std.testing.expectEqualStrings("auth_header-wire", header.value);
                auth_header = true;
            }
            if (std.ascii.eqlIgnoreCase(header.name, "header_value")) {
                try std.testing.expectEqualStrings("header_value-wire", header.value);
                header_value = true;
            }
        }
        try std.testing.expect(auth_header and header_value);
        var body_buffer: [4096]u8 = undefined;
        const reader = request.readerExpectNone(&body_buffer);
        const body = try reader.allocRemaining(std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(body);
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(self.streaming, parsed.value.object.get("stream").?.bool);
        try request.respond(if (self.streaming) "data: {\"text\":\"hello\"}\n\ndata: [DONE]\n\n" else "{\"text\":\"hello\"}", .{
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Type", .value = if (self.streaming) "text/event-stream" else "application/json" }},
        });
    }
};

test "flat and named collision parameters preserve wire names through every forwarding layer" {
    std.testing.refAllDecls(sdk);
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const has_clients = @hasDecl(sdk, "WidgetsClient") or @hasDecl(sdk, "CreateWidget");
    inline for (0..15) |mode| {
        if ((mode == 3 or mode == 4 or mode == 11 or mode == 12) and !@hasDecl(sdk, "resources")) continue;
        if (((mode >= 5 and mode <= 8) or mode >= 13) and !has_clients) continue;
        const address: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.loopback(0) };
        var server: Server = .{ .listener = try address.listen(io, .{}), .streaming = mode >= 9 };
        defer server.listener.deinit(io);
        const thread = try std.Thread.spawn(.{}, Server.serve, .{&server});
        var joined = false;
        defer if (!joined) thread.join();
        const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{server.listener.socket.address.getPort()});
        defer allocator.free(url);
        var client = sdk.Client.init(allocator, io, "");
        defer client.deinit();
        client.withBaseUrl(url);
        const Client = if (@hasDecl(sdk, "WidgetsClient")) sdk.WidgetsClient else if (@hasDecl(sdk, "CreateWidget")) sdk.CreateWidget else sdk.Client;
        var wrapper = if (has_clients) Client.init(&client) else client;
        const parameters = parameterArguments();
        const body: sdk.Request = .{ .stream = false };
        const args = .{&client} ++ parameters ++ .{body};
        const wrapper_args = .{&wrapper} ++ parameters ++ .{body};
        if (mode < 9) {
            var result = switch (mode) {
                0 => try @call(.auto, sdk.createWidget, args),
                1 => try @call(.auto, sdk.createWidgetRaw, args),
                2 => try @call(.auto, sdk.createWidgetResult, args),
                3 => try @call(.auto, sdk.resources.widgets.create, args),
                4 => try @call(.auto, sdk.resources.widgets.createResult, args),
                5, 6 => if (@hasDecl(sdk, "WidgetsClient"))
                    try @call(.auto, sdk.WidgetsClient.createWidget, wrapper_args)
                else
                    try @call(.auto, sdk.CreateWidget.execute, wrapper_args),
                7 => if (@hasDecl(sdk, "WidgetsClient"))
                    try @call(.auto, sdk.WidgetsClient.createWidgetRaw, wrapper_args)
                else
                    try @call(.auto, sdk.CreateWidget.executeRaw, wrapper_args),
                8 => if (@hasDecl(sdk, "WidgetsClient"))
                    try @call(.auto, sdk.WidgetsClient.createWidgetResult, wrapper_args)
                else
                    try @call(.auto, sdk.CreateWidget.executeResult, wrapper_args),
                else => unreachable,
            };
            defer result.deinit();
        } else {
            var callback: Callback = .{};
            const stream_args = args ++ .{ &callback, null };
            const wrapper_stream_args = wrapper_args ++ .{ &callback, null };
            switch (mode) {
                9 => try @call(.auto, sdk.createWidgetStreaming, stream_args),
                10 => try @call(.auto, sdk.createWidgetStreamingEvents, .{Event} ++ stream_args),
                11 => try @call(.auto, sdk.resources.widgets.createWidgetStream, stream_args),
                12 => try @call(.auto, sdk.resources.widgets.createWidgetStreamEvents, .{Event} ++ stream_args),
                13 => if (@hasDecl(sdk, "WidgetsClient")) {
                    try @call(.auto, sdk.WidgetsClient.createWidgetStreaming, wrapper_stream_args);
                } else {
                    try @call(.auto, sdk.CreateWidget.executeStreaming, wrapper_stream_args);
                },
                14 => if (@hasDecl(sdk, "WidgetsClient")) {
                    try @call(.auto, sdk.WidgetsClient.createWidgetStreamEvents, .{Event} ++ wrapper_stream_args);
                } else {
                    try @call(.auto, sdk.CreateWidget.executeStreamingEvents, .{Event} ++ wrapper_stream_args);
                },
                else => unreachable,
            }
            try std.testing.expectEqual(@as(usize, 1), callback.count);
        }
        thread.join();
        joined = true;
        if (server.failure) |err| return err;
    }
}
