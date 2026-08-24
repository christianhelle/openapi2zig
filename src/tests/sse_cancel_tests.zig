const std = @import("std");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const RuntimeGenerator = @import("../generators/unified/runtime_generator.zig").RuntimeGenerator;
const common = @import("../models/common/document.zig");

fn buildStreamingDocument(allocator: std.mem.Allocator) !common.UnifiedDocument {
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();

    var responses = std.StringHashMap(common.Response).init(allocator);
    try responses.put(try allocator.dupe(u8, "200"), .{ .description = "ok" });

    var params = std.ArrayList(common.Parameter).empty;
    try params.append(allocator, .{
        .name = "body",
        .location = .body,
        .required = true,
        .type = .object,
    });

    var stream_op = common.Operation{
        .operationId = "chatCompletion",
        .parameters = try params.toOwnedSlice(allocator),
        .responses = responses,
        .streaming = true,
    };
    errdefer stream_op.deinit(allocator);

    try paths.put(try allocator.dupe(u8, "/chat"), .{ .post = stream_op });

    return .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
}

test "generated single-file client exposes a cancel_check field" {
    const allocator = std.testing.allocator;
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "cancel_check: ?*const fn () bool = null,") != null);
}

test "generated runtime emits CancelableReader" {
    const allocator = std.testing.allocator;
    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();

    const code = try runtime_gen.generate();
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const CancelableReader = struct {") != null);
}

test "generated single-file client emits CancelableReader" {
    const allocator = std.testing.allocator;
    var document = try buildStreamingDocument(allocator);
    defer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();

    const code = try generator.generate(document);
    defer allocator.free(code);

    try std.testing.expect(std.mem.indexOf(u8, code, "pub const CancelableReader = struct {") != null);
}

test "generated streamJson wraps streaming reads with cancel_check" {
    const allocator = std.testing.allocator;
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
