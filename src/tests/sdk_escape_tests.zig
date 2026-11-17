const std = @import("std");
const templates = @import("../generators/sdk/templates.zig");
const zig_text = @import("../generators/sdk/zig_text.zig");
const test_utils = @import("test_utils.zig");

const testing = std.testing;

fn context() templates.SdkContext {
    return .{
        .config = .{ .name = "petstore", .description = "Pets SDK\nHandles pet operations.\r\nMore." },
        .generator_version = "9.9.9",
        .base_url = "https://x.example.com/\"; pub const injected = 1; //\\\n",
    };
}

test "escapeString makes text safe inside a string literal" {
    const out = try zig_text.escapeString(testing.allocator, "a\"b\\c\nd\te\x01");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("a\\\"b\\\\c\\nd\\te\\x01", out);
}

test "docComment prefixes every line" {
    const out = try zig_text.docComment(testing.allocator, "one\r\ntwo\nthree");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("one\n//! two\n//! three", out);
}

test "root.zig escapes the base url" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try templates.render(allocator, .root_zig, context());
    defer allocator.free(out);

    const expected = "pub const api_base_url = \"https://x.example.com/\\\"; pub const injected = 1; //\\\\\\n\";";
    try testing.expect(std.mem.indexOf(u8, out, expected) != null);
}

test "root.zig keeps a multi-line description commented" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try templates.render(allocator, .root_zig, context());
    defer allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "//! Pets SDK\n//! Handles pet operations.\n//! More., generated") != null);

    // The README keeps the description as written.
    const readme = try templates.render(allocator, .readme, context());
    defer allocator.free(readme);
    try testing.expect(std.mem.indexOf(u8, readme, "# Pets SDK\nHandles pet operations.") != null);
}
