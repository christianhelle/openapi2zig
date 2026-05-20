const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const document = @import("../models/common/document.zig");
const Parameter = document.Parameter;
const ParameterLocation = document.ParameterLocation;

test "Parameter.content_type owns and frees its allocation" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var param = Parameter{
        .name = "requestBody",
        .location = .body,
        .required = true,
        .content_type = try allocator.dupe(u8, "application/octet-stream"),
    };
    defer param.deinit(allocator);

    try testing.expect(param.content_type != null);
    try testing.expectEqualStrings("application/octet-stream", param.content_type.?);
}

test "Parameter.content_type defaults to null for non-body parameters" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var param = Parameter{
        .name = "petId",
        .location = .path,
        .required = true,
    };
    defer param.deinit(allocator);

    try testing.expect(param.content_type == null);
}
