const std = @import("std");
const template = @import("../generators/sdk/template.zig");
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
