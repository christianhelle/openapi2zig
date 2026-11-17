const std = @import("std");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{\"/pets\":{\"get\":{\"operationId\":\"listPets\",\"responses\":{\"200\":{\"description\":\"ok\"}}}}}}";

fn generateClient(allocator: std.mem.Allocator) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    return generator.generate(unified);
}

test "generated clients accept a token provider and a retry policy" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub const TokenProvider = struct {") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pub const RetryPolicy = struct {") != null);
    try testing.expect(std.mem.indexOf(u8, code, "token_provider: ?TokenProvider = null,") != null);
    try testing.expect(std.mem.indexOf(u8, code, "retry: RetryPolicy = .{},") != null);
    try testing.expect(std.mem.indexOf(u8, code, "if (client.token_provider) |provider| try provider.getToken(allocator, client.io) else client.api_key") != null);
}

test "generated transport retries throttled responses" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "fn isRetryableStatus(status: std.http.Status) bool {") != null);
    try testing.expect(std.mem.indexOf(u8, code, "status == .too_many_requests or status == .service_unavailable or status == .gateway_timeout") != null);
    try testing.expect(std.mem.indexOf(u8, code, "client.retry.delayMilliseconds(attempt, result.retry_after_seconds)") != null);
}
