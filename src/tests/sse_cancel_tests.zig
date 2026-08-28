const std = @import("std");
const test_utils = @import("test_utils.zig");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const RuntimeGenerator = @import("../generators/unified/runtime_generator.zig").RuntimeGenerator;
const common = @import("../models/common/document.zig");

fn buildStreamingDocument(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer {
        var iterator = paths.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        paths.deinit();
    }

    var stream_op = blk: {
        var responses = std.StringHashMap(common.Response).init(allocator);
        errdefer {
            var iterator = responses.iterator();
            while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
            responses.deinit();
        }

        const response_key = try allocator.dupe(u8, "200");
        if (responses.put(response_key, .{ .description = "ok" })) |_| {} else |err| {
            allocator.free(response_key);
            return err;
        }

        var params = std.ArrayList(common.Parameter).empty;
        errdefer params.deinit(allocator);
        try params.append(allocator, .{
            .name = "body",
            .location = .body,
            .required = true,
            .type = .object,
        });

        break :blk common.Operation{
            .operationId = "chatCompletion",
            .parameters = try params.toOwnedSlice(allocator),
            .responses = responses,
            .streaming = true,
        };
    };
    errdefer stream_op.deinit(allocator);

    const path_key = try allocator.dupe(u8, "/chat");
    if (paths.put(path_key, .{ .post = stream_op })) |_| {} else |err| {
        allocator.free(path_key);
        return err;
    }

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

fn buildNonStreamingDocument(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var document = try buildStreamingDocument(allocator);
    document.paths.getPtr("/chat").?.post.?.streaming = false;
    return document;
}

fn buildWatcherNameCollisionDocument(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var document = try buildStreamingDocument(allocator);
    errdefer document.deinit(allocator);

    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    const response_key = try allocator.dupe(u8, "204");
    errdefer allocator.free(response_key);
    try responses.put(response_key, .{ .description = "ok" });

    const path_key = try allocator.dupe(u8, "/cancel-watcher");
    errdefer allocator.free(path_key);
    try document.paths.put(path_key, .{
        .get = .{
            .operationId = "cancel-watcher",
            .responses = responses,
        },
    });
    return document;
}

test "generated single-file client exposes a cancel_check field" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "cancel_check: ?*const fn () bool = null,") != null);
}

test "generated client documents interruptible cancellation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "successfully started background watcher interrupts") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "If watcher startup fails, cancellation remains read-boundary only.") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "When null (default), no watcher thread is spawned.") != null);
}

test "generated runtime emits CancelableReader" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();

    const code = try runtime_gen.generate();
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const CancelableReader = struct {") != null);
}

test "generated runtime documents the companion cancellation watcher" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();

    const code = try runtime_gen.generate();
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "companion watcher thread in the generated client") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "blocked socket reads are interrupted within about 10 ms") != null);
}

test "generated single-file client emits CancelableReader" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const CancelableReader = struct {") != null);
}

test "generated streamJson wraps streaming reads with cancel_check" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "if (client.cancel_check) |pred| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "CancelableReader.init(response_reader, &cancelable_buffer, pred)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "if (pred()) return error.Cancelled;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "error.ReadFailed => return response.bodyErr() orelse err,") != null);
}

test "generated cancellation watcher owns Windows cleanup without racing connection state" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "Windows.CancelIoEx") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "    const CancelWatcher = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "Client.CancelWatcher.run") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "Windows.CreateEventW") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "self.replacement_handle = replacement;") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "conn.stream_reader.stream.socket.handle = handle;") != null);
    const join_index = std.mem.indexOf(u8, code, "thread.join();").?;
    const closing_index = std.mem.indexOf(u8, code, "conn.closing = true;").?;
    try std.testing.expect(closing_index > join_index);
    try std.testing.expect(std.mem.indexOf(u8, code, ".awake) catch return;") != null);
}

test "generated non-streaming client omits interruptible streaming helpers" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildNonStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "const CancelWatcher = struct {") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "fn streamJson(") == null);
}

test "nested cancellation watcher does not reserve top-level client names" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var document = try buildWatcherNameCollisionDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .multiple_clients = .per_endpoint,
    });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "    const CancelWatcher = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const CancelWatcher = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub const CancelWatcher_ = struct {") == null);
}
