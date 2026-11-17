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
    try testing.expect(std.mem.indexOf(u8, code, "try provider.getToken(allocator, client.io), .owned = true") != null);
}

test "generated transport retries throttled responses" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateClient(allocator);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "fn isRetryableStatus(status: std.http.Status, method: std.http.Method) bool {") != null);
    try testing.expect(std.mem.indexOf(u8, code, "status == .gateway_timeout and method != .POST and method != .PATCH") != null);
    try testing.expect(std.mem.indexOf(u8, code, "client.retry.delayMilliseconds(attempt, result.retry_after_seconds)") != null);
}

const pageable_spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{" ++
    "\"/users\":{\"get\":{\"operationId\":\"listUsers\",\"parameters\":[{\"name\":\"$top\",\"in\":\"query\",\"schema\":{\"type\":\"integer\"}}]," ++
    "\"responses\":{\"200\":{\"description\":\"ok\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/UserPage\"}}}}}," ++
    "\"x-ms-pageable\":{\"nextLinkName\":\"@odata.nextLink\",\"operationName\":\"listMore\"}}}," ++
    "\"/other\":{\"get\":{\"operationId\":\"listOther\",\"responses\":{\"200\":{\"description\":\"ok\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/Other\"}}}}}," ++
    "\"x-ms-pageable\":{\"nextLinkName\":\"@odata.nextLink\"}}}}," ++
    "\"components\":{\"schemas\":{" ++
    "\"UserPage\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"@odata.nextLink\":{\"type\":\"string\",\"nullable\":true}}}," ++
    "\"Other\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}}}}";

fn generatePageable(allocator: std.mem.Allocator, pagination: bool) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, pageable_spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    const item = unified.paths.get("/users").?.get.?;
    try testing.expectEqualStrings("@odata.nextLink", item.next_link_name.?);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .pagination = pagination });
    defer generator.deinit();
    return generator.generate(unified);
}

test "pagination adds a pager for operations that declare x-ms-pageable" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generatePageable(allocator, true);
    defer allocator.free(code);

    // The page type has no such property, so no pager is generated for it.
    try testing.expect(std.mem.indexOf(u8, code, "listOtherPages") == null);
}

test "pagination is off unless requested" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generatePageable(allocator, false);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "Pager") == null);
}

const error_spec =
    "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{" ++
    "\"/a\":{\"get\":{\"operationId\":\"getA\",\"responses\":{\"200\":{\"description\":\"ok\"},\"4XX\":{\"$ref\":\"#/components/responses/failure\"},\"5XX\":{\"$ref\":\"#/components/responses/failure\"}}}}," ++
    "\"/b\":{\"get\":{\"operationId\":\"getB\",\"responses\":{\"200\":{\"description\":\"ok\"},\"default\":{\"$ref\":\"#/components/responses/failure\"}}}}}," ++
    "\"components\":{\"schemas\":{\"Failure\":{\"type\":\"object\",\"properties\":{\"message\":{\"type\":\"string\"}}},\"Other\":{\"type\":\"object\"}}," ++
    "\"responses\":{\"failure\":{\"description\":\"error\",\"content\":{\"application/json\":{\"schema\":{\"$ref\":\"#/components/schemas/Failure\"}}}}}}}";

fn generateErrors(allocator: std.mem.Allocator, typed_errors: bool) ![]const u8 {
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, error_spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .typed_errors = typed_errors });
    defer generator.deinit();
    return generator.generate(unified);
}

test "typed errors expose the most common error model" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateErrors(allocator, true);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub const ApiError = Failure;") != null);
    try testing.expect(std.mem.indexOf(u8, code, "pub fn parseApiError(allocator: std.mem.Allocator, raw: RawResponse) !std.json.Parsed(ApiError) {") != null);
}

test "typed errors are off unless requested" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generateErrors(allocator, false);
    defer allocator.free(code);
    try testing.expect(std.mem.indexOf(u8, code, "ApiError") == null);
}

test "typed errors fall back to a json value without an error model" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);
    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .typed_errors = true });
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    try testing.expect(std.mem.indexOf(u8, code, "pub const ApiError = std.json.Value;") != null);
    try testing.expect(std.mem.indexOf(u8, code, ".allocate = .alloc_always") != null);
}

test "pagination reserves the Pages names and escapes the link property" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const code = try generatePageable(allocator, true);
    defer allocator.free(code);
    // `listUsersPages` is taken by the pager function, so an operation that
    // is called that gets a suffix instead of colliding.
    try testing.expect(std.mem.indexOf(u8, code, "pub fn listUsersPages(") != null);
}
