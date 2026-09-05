const std = @import("std");
const input_loader = @import("../input_loader.zig");

// The remaining loadFromUrl paths (reading a body, and mapping HTTP status
// codes onto LoadError) need a real server on the other end, so these tests
// serve one canned response from an ephemeral loopback port.

const TestServer = struct {
    io: std.Io,
    server: std.Io.net.Server,
    status: std.http.Status,
    body: []const u8,
    thread: std.Thread = undefined,

    fn serve(self: *TestServer) void {
        var stream = self.server.accept(self.io) catch return;
        defer stream.close(self.io);

        var in_buffer: [4096]u8 = undefined;
        var out_buffer: [4096]u8 = undefined;
        var reader = stream.reader(self.io, &in_buffer);
        var writer = stream.writer(self.io, &out_buffer);

        var http_server = std.http.Server.init(&reader.interface, &writer.interface);
        var request = http_server.receiveHead() catch return;
        request.respond(self.body, .{ .status = self.status }) catch return;
    }

    fn start(status: std.http.Status, body: []const u8) !*TestServer {
        const address: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.loopback(0) };
        const server = try std.Io.net.IpAddress.listen(&address, std.testing.io, .{});
        const context = try std.testing.allocator.create(TestServer);
        errdefer std.testing.allocator.destroy(context);
        context.* = .{ .io = std.testing.io, .server = server, .status = status, .body = body };
        errdefer context.server.deinit(std.testing.io);
        context.thread = try std.Thread.spawn(.{}, TestServer.serve, .{context});
        return context;
    }

    fn url(self: *TestServer, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/spec.json", .{self.server.socket.address.getPort()});
    }

    fn stop(self: *TestServer) void {
        self.server.deinit(self.io);
        self.thread.join();
        std.testing.allocator.destroy(self);
    }
};

test "loadFromUrl returns the response body on success" {
    const allocator = std.testing.allocator;
    const spec =
        \\{"openapi": "3.0.3", "info": {"title": "Served", "version": "1.0.0"}, "paths": {}}
    ;
    const server = try TestServer.start(.ok, spec);
    defer server.stop();

    const url = try server.url(allocator);
    defer allocator.free(url);

    const body = try input_loader.loadFromUrl(allocator, std.testing.io, url);
    defer allocator.free(body);

    try std.testing.expectEqualStrings(spec, body);
}

test "loadInput follows a url source" {
    const allocator = std.testing.allocator;
    const spec =
        \\{"swagger": "2.0", "info": {"title": "Served", "version": "1.0.0"}, "paths": {}}
    ;
    const server = try TestServer.start(.ok, spec);
    defer server.stop();

    const url = try server.url(allocator);
    defer allocator.free(url);

    const body = try input_loader.loadInput(allocator, std.testing.io, .{ .url = url });
    defer allocator.free(body);

    try std.testing.expectEqualStrings(spec, body);
}

test "loadFromUrl maps 404 onto HttpNotFound" {
    const allocator = std.testing.allocator;
    const server = try TestServer.start(.not_found, "missing");
    defer server.stop();

    const url = try server.url(allocator);
    defer allocator.free(url);

    try std.testing.expectError(
        input_loader.LoadError.HttpNotFound,
        input_loader.loadFromUrl(allocator, std.testing.io, url),
    );
}

test "loadFromUrl maps other error statuses onto HttpRequestFailed" {
    const allocator = std.testing.allocator;
    const server = try TestServer.start(.internal_server_error, "boom");
    defer server.stop();

    const url = try server.url(allocator);
    defer allocator.free(url);

    try std.testing.expectError(
        input_loader.LoadError.HttpRequestFailed,
        input_loader.loadFromUrl(allocator, std.testing.io, url),
    );
}
