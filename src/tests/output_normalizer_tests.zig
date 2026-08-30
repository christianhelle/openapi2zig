const std = @import("std");
const test_utils = @import("test_utils.zig");
const normalizer = @import("../generators/output_normalizer.zig");

test "normalize strips trailing whitespace from lines" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const input = "// Description:\n// \n//\nconst a = 1;\n";
    const result = try normalizer.normalize(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("// Description:\n//\n//\nconst a = 1;\n", result);
}

test "normalize collapses consecutive blank lines" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const input = "const a = 1;\n\n\n\nconst b = 2;\n";
    const result = try normalizer.normalize(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("const a = 1;\n\nconst b = 2;\n", result);
}

test "normalize ends output with exactly one newline" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const input = "const a = 1;\n\n\n";
    const result = try normalizer.normalize(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("const a = 1;\n", result);
}

test "normalize appends a trailing newline when missing" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const result = try normalizer.normalize(allocator, "const a = 1;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("const a = 1;\n", result);
}

test "normalize strips carriage returns" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const result = try normalizer.normalize(allocator, "const a = 1;\r\nconst b = 2;\r\n");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("const a = 1;\nconst b = 2;\n", result);
}

test "normalize is idempotent" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const input = "// Description:\n// \n//\n\n\n\nconst a = 1;   \n\n\n";
    const once = try normalizer.normalize(allocator, input);
    defer allocator.free(once);
    const twice = try normalizer.normalize(allocator, once);
    defer allocator.free(twice);

    try std.testing.expectEqualStrings(once, twice);
}

test "normalize leaves already clean output untouched" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const input = "const std = @import(\"std\");\n\npub fn main() void {}\n";
    const result = try normalizer.normalize(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(input, result);
}

test "normalize handles empty input" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const result = try normalizer.normalize(allocator, "");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "normalize preserves indentation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const input = "pub fn main() void {\n    const a = 1;\n}\n";
    const result = try normalizer.normalize(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(input, result);
}
