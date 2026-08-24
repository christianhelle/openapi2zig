const std = @import("std");

const v2 = @import("generated_v2.zig");
const v2_yaml = @import("generated_v2_yaml.zig");
const v3 = @import("generated_v3.zig");
const v3_yaml = @import("generated_v3_yaml.zig");
const v31 = @import("generated_v31.zig");
const v31_yaml = @import("generated_v31_yaml.zig");
const v32 = @import("generated_v32.zig");
const v3_multiclient_tag = @import("generated_v3_multiclient_tag.zig");
const v3_multiclient_endpoint = @import("generated_v3_multiclient_endpoint.zig");
const v3_params_struct = @import("generated_v3_params_struct.zig");
const openai = @import("openai.zig");
const anthropic = @import("anthropic.zig");
const lmstudio = @import("lmstudio.zig");

fn refAllDeclsMany(comptime T: type) void {
    @setEvalBranchQuota(10_000_000);
    std.testing.refAllDecls(T);
}

test "generated clients compile" {
    std.testing.refAllDecls(v2);
    std.testing.refAllDecls(v2_yaml);
    std.testing.refAllDecls(v3);
    std.testing.refAllDecls(v3_yaml);
    std.testing.refAllDecls(v31);
    std.testing.refAllDecls(v31_yaml);
    std.testing.refAllDecls(v32);
    std.testing.refAllDecls(v3_multiclient_tag);
    std.testing.refAllDecls(v3_multiclient_endpoint);
    std.testing.refAllDecls(v3_params_struct);
    refAllDeclsMany(openai);
    refAllDeclsMany(anthropic);
    refAllDeclsMany(lmstudio);
}

const SseCallback = struct {
    count: usize = 0,

    pub fn event(self: *SseCallback, data: []const u8) !void {
        switch (self.count) {
            0 => try std.testing.expectEqualStrings("{\"x\":1}", data),
            1 => try std.testing.expectEqualStrings("a", data),
            2 => try std.testing.expectEqualStrings("a\nb", data),
            else => return error.UnexpectedEvent,
        }
        self.count += 1;
    }
};

test "generated SSE parser handles comments CRLF multiline and done" {
    var callback: SseCallback = .{};
    try v3.parseSseBytes(
        std.testing.allocator,
        "data: {\"x\":1}\n\n" ++
            "data: [DONE]\n\n" ++
            "data: should-not-dispatch\n\n",
        &callback,
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), callback.count);

    callback = .{};
    try v3.parseSseBytes(
        std.testing.allocator,
        ": keepalive\n\n" ++
            "data: {\"x\":1}\n\n" ++
            ": ignored\r\n" ++
            "data: a\r\n" ++
            "\r\n" ++
            "data: a\n" ++
            "data: b\n" ++
            "\n",
        &callback,
        null,
    );
    try std.testing.expectEqual(@as(usize, 3), callback.count);
}

test "generated SSE parser bounds line and event size" {
    const max_sse_line_size = 256 * 1024;
    const max_sse_event_size = 1024 * 1024;

    var callback: SseCallback = .{};

    const long_line = try std.testing.allocator.alloc(u8, max_sse_line_size + 1);
    defer std.testing.allocator.free(long_line);
    @memset(long_line, 'x');
    try std.testing.expectError(error.SseLineTooLong, v3.parseSseBytes(std.testing.allocator, long_line, &callback, null));

    var input: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer input.deinit();
    const chunk = try std.testing.allocator.alloc(u8, 4 * 1024);
    defer std.testing.allocator.free(chunk);
    @memset(chunk, 'a');

    var written: usize = 0;
    while (written <= max_sse_event_size) : (written += chunk.len + 1) {
        try input.writer.writeAll("data: ");
        try input.writer.writeAll(chunk);
        try input.writer.writeAll("\n");
    }
    try input.writer.writeAll("\n");

    try std.testing.expectError(error.SseEventTooLong, v3.parseSseBytes(std.testing.allocator, input.written(), &callback, null));
}

const TypedEvent = struct {
    x: i64,
};

const TypedSseTestCallback = struct {
    seen: i64 = 0,

    pub fn event(self: *TypedSseTestCallback, value: *TypedEvent) !void {
        self.seen += value.x;
    }
};

test "generated SSE parser can parse typed events" {
    var callback: TypedSseTestCallback = .{};
    try v3.parseSseBytesTyped(
        TypedEvent,
        std.testing.allocator,
        "data: {\"x\":1,\"ignored\":true}\n\n" ++
            "data: {\"x\":2}\n\n" ++
            "data: [DONE]\n\n",
        &callback,
        null,
    );
    try std.testing.expectEqual(@as(i64, 3), callback.seen);
}

test "generated ApiResult parses success and keeps error body" {
    const ok_body = try std.testing.allocator.dupe(u8, "{\"x\":42,\"ignored\":true}");
    var ok_result = try v3.parseRawResponse(TypedEvent, .{
        .allocator = std.testing.allocator,
        .status = .ok,
        .body = ok_body,
    });
    defer ok_result.deinit();
    switch (ok_result) {
        .ok => |*owned| try std.testing.expectEqual(@as(i64, 42), owned.value().x),
        .api_error, .parse_error => return error.ExpectedOk,
    }

    const error_body = try std.testing.allocator.dupe(u8, "{\"error\":\"bad\"}");
    var error_result = try v3.parseRawResponse(TypedEvent, .{
        .allocator = std.testing.allocator,
        .status = .bad_request,
        .body = error_body,
    });
    defer error_result.deinit();
    switch (error_result) {
        .ok, .parse_error => return error.ExpectedApiError,
        .api_error => |raw| try std.testing.expectEqualStrings("{\"error\":\"bad\"}", raw.body),
    }

    const invalid_body = try std.testing.allocator.dupe(u8, "{\"x\":\"not-an-int\"}");
    var parse_result = try v3.parseRawResponse(TypedEvent, .{
        .allocator = std.testing.allocator,
        .status = .ok,
        .body = invalid_body,
    });
    defer parse_result.deinit();
    switch (parse_result) {
        .ok, .api_error => return error.ExpectedParseError,
        .parse_error => |parse_error| {
            try std.testing.expectEqualStrings("{\"x\":\"not-an-int\"}", parse_error.raw.body);
            try std.testing.expect(parse_error.error_name.len > 0);
        },
    }
}

test "generated CancellationToken cancels SSE parsing" {
    var token = v3.CancellationToken.init();
    token.cancel();

    var callback: SseCallback = .{};
    try std.testing.expectError(
        error.Cancelled,
        v3.parseSseBytes(std.testing.allocator, "data: {\"x\":1}\n\n", &callback, &token),
    );
}

test "generated CancellationToken cancels typed SSE parsing" {
    var token = v3.CancellationToken.init();
    token.cancel();

    var callback: TypedSseTestCallback = .{};
    try std.testing.expectError(
        error.Cancelled,
        v3.parseSseBytesTyped(TypedEvent, std.testing.allocator, "data: {\"x\":1}\n\n", &callback, &token),
    );
}

test "generated CancelableReader passes through when cancel check is null" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    var fixed = std.Io.Reader.fixed("hello");
    var buffer: [1]u8 = undefined;
    var reader = v3.CancelableReader.init(&fixed, &buffer, null);
    _ = try reader.reader.streamRemaining(&out.writer);
    try std.testing.expectEqualStrings("hello", out.written());
}

test "generated CancelableReader fails with ReadFailed when cancel check returns true" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    const always_cancel = struct {
        fn check() bool {
            return true;
        }
    }.check;
    var fixed = std.Io.Reader.fixed("hello");
    var buffer: [1]u8 = undefined;
    var reader = v3.CancelableReader.init(&fixed, &buffer, &always_cancel);
    try std.testing.expectError(error.ReadFailed, reader.reader.streamRemaining(&out.writer));
}

test "generated CancelableReader passes through when cancel check returns false" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    const never_cancel = struct {
        fn check() bool {
            return false;
        }
    }.check;
    var fixed = std.Io.Reader.fixed("hello");
    var buffer: [1]u8 = undefined;
    var reader = v3.CancelableReader.init(&fixed, &buffer, &never_cancel);
    _ = try reader.reader.streamRemaining(&out.writer);
    try std.testing.expectEqualStrings("hello", out.written());
}

test "generated endpoint parsing is loose" {
    const source = @embedFile("generated_v3.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, ", allocator, body, .{})") == null);
    try std.testing.expect(std.mem.indexOf(u8, source, ".ignore_unknown_fields = true") != null);
}

test "options struct parameters accept partial literals with null defaults" {
    const Options = @typeInfo(@TypeOf(v3_params_struct.findPetsByStatus)).@"fn".params[1].type.?;

    const all_defaults: Options = .{};
    try std.testing.expect(all_defaults.status == null);

    const partial: Options = .{ .status = "available" };
    try std.testing.expectEqualStrings("available", partial.status.?);
}

test "options struct parameters require required fields" {
    const Options = @typeInfo(@TypeOf(v3_params_struct.getPetById)).@"fn".params[1].type.?;

    const required: Options = .{ .petId = 1 };
    try std.testing.expectEqual(@as(i64, 1), required.petId);
}
