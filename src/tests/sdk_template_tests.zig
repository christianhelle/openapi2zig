const std = @import("std");
const template = @import("../generators/sdk/template.zig");
const templates = @import("../generators/sdk/templates.zig");
const test_utils = @import("test_utils.zig");

const testing = std.testing;

test "template expands placeholders" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try template.expand(allocator, "hello {{ name }}, {{name}}!", &.{.{ .name = "name", .value = "world" }});
    defer allocator.free(out);
    try testing.expectEqualStrings("hello world, world!", out);
}

test "template keeps single braces untouched" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try template.expand(allocator, "fn f() void { return; }", &.{});
    defer allocator.free(out);
    try testing.expectEqualStrings("fn f() void { return; }", out);
}

test "template rejects unknown variables" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    try testing.expectError(error.UnknownVariable, template.expand(allocator, "{{missing}}", &.{}));
    try testing.expectError(error.UnterminatedPlaceholder, template.expand(allocator, "{{oops", &.{}));
}

test "template drops carriage returns" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try template.expand(allocator, "a\r\nb\r\n", &.{});
    defer allocator.free(out);
    try testing.expectEqualStrings("a\nb\n", out);
}

fn testContext() templates.SdkContext {
    return .{
        .config = .{ .name = "petstore", .version = "1.2.3", .description = "Petstore SDK", .repository = "https://github.com/example/petstore-sdk-for-zig", .author = "Jane Doe" },
        .generator_version = "9.9.9",
        .base_url = "https://petstore.example.com/v1",
        .path_count = 3,
        .operation_count = 5,
        .schema_count = 7,
        .fingerprint = 0xabcdef0123456789,
    };
}

fn renderOwned(allocator: std.mem.Allocator, kind: templates.Kind) ![]u8 {
    return templates.render(allocator, kind, testContext());
}

test "root.zig template re-exports the generated modules" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try renderOwned(allocator, .root_zig);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "pub const client = @import(\"client.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const models = @import(\"models.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const runtime = @import(\"runtime.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const Owned = runtime.Owned;") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const api_base_url = \"https://petstore.example.com/v1\";") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub fn init(allocator: std.mem.Allocator, io: std.Io, token: []const u8) Client") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Petstore SDK") != null);
    try testing.expect(std.mem.indexOf(u8, out, "{{") == null);
}

test "every template renders without leftover placeholders" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    for (templates.all_kinds) |kind| {
        const out = try renderOwned(allocator, kind);
        defer allocator.free(out);
        try testing.expect(out.len > 0);
        try testing.expect(std.mem.indexOf(u8, out, "{{") == null);
        try testing.expect(std.mem.indexOfScalar(u8, out, '\r') == null);
    }
}
