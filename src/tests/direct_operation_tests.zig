const std = @import("std");
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const common = @import("../models/common/document.zig");
const test_utils = @import("test_utils.zig");

// An operation without an operationId gets no `…Raw`/`…Result` pair; the
// generator emits a single self-contained function instead. These tests cover
// that path: URI building, each request body media type, and the return type
// derived from the success response schema.

const Fixture = struct {
    document: common.UnifiedDocument,
    code: []const u8,

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        self.document.deinit(allocator);
    }
};

const Options = struct {
    path: []const u8 = "/items",
    body_content_type: ?[]const u8 = null,
    header_param: bool = false,
    query_param: bool = false,
    form_param: bool = false,
    response_schema: ?common.Schema = null,
};

fn responseMap(allocator: std.mem.Allocator, schema: ?common.Schema) !std.StringHashMap(common.Response) {
    var responses = std.StringHashMap(common.Response).init(allocator);
    errdefer responses.deinit();
    try responses.put(try allocator.dupe(u8, "200"), .{ .description = "ok", .schema = schema });
    return responses;
}

fn generate(allocator: std.mem.Allocator, options: Options) !Fixture {
    var parameters = std.ArrayList(common.Parameter).empty;
    errdefer parameters.deinit(allocator);
    if (options.body_content_type) |content_type| {
        try parameters.append(allocator, .{
            .name = "body",
            .location = .body,
            .required = true,
            .schema = .{ .type = .object },
            .content_type = try allocator.dupe(u8, content_type),
        });
    }
    if (options.header_param) {
        try parameters.append(allocator, .{
            .name = "x-trace-id",
            .location = .header,
            .required = true,
            .schema = .{ .type = .string },
        });
    }
    if (options.query_param) {
        try parameters.append(allocator, .{
            .name = "page",
            .location = .query,
            .required = true,
            .schema = .{ .type = .integer },
        });
        try parameters.append(allocator, .{
            .name = "ratio",
            .location = .query,
            .required = true,
            .schema = .{ .type = .number },
        });
        try parameters.append(allocator, .{
            .name = "untyped",
            .location = .query,
            .required = true,
        });
    }
    if (options.form_param) {
        try parameters.append(allocator, .{
            .name = "formField",
            .location = .form,
            .schema = .{ .type = .string },
        });
    }

    var paths = std.StringHashMap(common.PathItem).init(allocator);
    errdefer paths.deinit();
    try paths.put(try allocator.dupe(u8, options.path), .{
        .post = .{
            // No operationId: this is what selects the direct code path.
            .parameters = if (parameters.items.len > 0) try parameters.toOwnedSlice(allocator) else null,
            .responses = try responseMap(allocator, options.response_schema),
        },
    });

    var document: common.UnifiedDocument = .{
        .version = "3.0.0",
        .info = .{ .title = "fixture", .version = "1.0.0" },
        .paths = paths,
    };
    errdefer document.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{
        .input_path = "fixture.json",
        .resource_wrappers = .none,
    });
    defer generator.deinit();

    return .{ .document = document, .code = try generator.generate(document) };
}

fn expectContains(code: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, code, needle) != null);
}

test "an operation without an operationId sends a JSON body directly" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "application/json", .header_param = true });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "try std.json.Stringify.value(requestBody");
    try expectContains(fixture.code, "const payload = str.written();");
    try expectContains(fixture.code, "\"application/json\", \"application/json\");");
    try expectContains(fixture.code, "        .payload = payload,");
    try expectContains(fixture.code, "\"x-trace-id\"");
}

test "an operation without an operationId sends a binary body verbatim" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "application/octet-stream" });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "const payload: []const u8 = requestBody;");
    try expectContains(fixture.code, "\"application/octet-stream\", \"application/json\");");
}

test "an operation without an operationId falls back to JSON for form bodies" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .body_content_type = "multipart/form-data" });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "multipart/form-data and x-www-form-urlencoded request bodies are not yet supported");
    // The declared Content-Type must describe the JSON payload actually sent.
    try expectContains(fixture.code, "\"application/json\", \"application/json\");");
}

test "an operation without an operationId appends its query parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .query_param = true });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "try appendQueryParam(&uri_buf.writer, &first_query, \"page\", page);");
    try expectContains(fixture.code, "try appendQueryParam(&uri_buf.writer, &first_query, \"ratio\", ratio);");
    // Query parameter types come from the schema, defaulting to a string.
    try expectContains(fixture.code, "page: i64");
    try expectContains(fixture.code, "ratio: f64");
    try expectContains(fixture.code, "untyped: []const u8");
}

test "an operation without an operationId keeps a path fragment after the query" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .path = "/items#section", .query_param = true });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "try uri_buf.writer.writeAll(\"#section\");");
}

test "an operation without an operationId discards unsupported parameter locations" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    var fixture = try generate(allocator, .{ .form_param = true });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, "_ = formField;");
}

test "the return type comes from the success response schema" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    var void_result = try generate(allocator, .{});
    defer void_result.deinit(allocator);
    try expectContains(void_result.code, ") !void {");

    var string_result = try generate(allocator, .{ .response_schema = .{ .type = .string } });
    defer string_result.deinit(allocator);
    try expectContains(string_result.code, ") !Owned([]const u8) {");

    var untyped_result = try generate(allocator, .{ .response_schema = .{} });
    defer untyped_result.deinit(allocator);
    try expectContains(untyped_result.code, ") !Owned(std.json.Value) {");
}

test "a success response of one type or null becomes an optional return type" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const variants = try allocator.dupe(common.Schema, &.{
        .{ .type = .number },
        .{ .type = .null },
    });
    var fixture = try generate(allocator, .{ .response_schema = .{ .one_of = variants } });
    defer fixture.deinit(allocator);

    try expectContains(fixture.code, ") !Owned(?f64) {");
}
