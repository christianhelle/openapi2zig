const std = @import("std");
const api = @import("../lib.zig");
const common = @import("../models/common/document.zig");

fn exerciseReservations(allocator: std.mem.Allocator) !void {
    var parameters = [_]common.Parameter{
        .{ .name = "callback", .location = .query },
        .{ .name = "callback_param", .location = .query },
        .{ .name = "callback_param1", .location = .header },
        .{ .name = "Widget", .location = .path },
    };
    const operation: common.Operation = .{
        .operationId = "createWidget",
        .parameters = &parameters,
        .responses = std.StringHashMap(common.Response).init(allocator),
    };
    var paths = std.StringHashMap(common.PathItem).init(allocator);
    defer paths.deinit();
    try paths.put("/widgets/{Widget}", .{ .post = operation });
    var generator = api.UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    // Include a preamble declaration that blocks the first available alias.
    try generator.buffer.appendSlice(allocator, "pub const callback_param2 = bool;\n");
    const document: common.UnifiedDocument = .{ .version = "3.1.0", .info = .{ .title = "fixture", .version = "1" }, .paths = paths };
    try generator.reserveOperationNames(document);
    try generator.reserveFlatParameterNames(document);
    try generator.reserveFlatParameterNames(document);
    generator.buffer.clearRetainingCapacity();
    try generator.appendFlatParamIdentifier("callback");
    try std.testing.expectEqualStrings("callback_param3", generator.buffer.items);
}

test "flat parameter reservations clean up partial allocations and repeated passes" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseReservations, .{});
}

test "collision aliases are deterministic across repeated single and multi-file generation" {
    const allocator = std.testing.allocator;
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "openapi/v3.1/regression-parameter-collisions.json", allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    var document = try api.parseToUnified(allocator, source);
    defer document.deinit(allocator);
    for ([_]bool{ false, true }) |options_mode| {
        var generator = api.UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .parameters_as_struct = options_mode });
        defer generator.deinit();
        const first = try generator.generate(document);
        defer allocator.free(first);
        const second = try generator.generate(document);
        defer allocator.free(second);
        try std.testing.expectEqualStrings(first, second);
        if (!options_mode) {
            try std.testing.expect(std.mem.indexOf(u8, first, "callback_param3: []const u8") != null);
            try std.testing.expect(std.mem.indexOf(u8, first, "Widget_param1: []const u8") != null);
            try std.testing.expect(std.mem.indexOf(u8, first, "create_param1: []const u8") != null);
            try std.testing.expect(std.mem.indexOf(u8, first, "widgets_param1: []const u8") != null);
        }
        generator.model_prefix = "models.";
        const multi = try generator.generateClientOnly(document);
        defer allocator.free(multi);
        const multi_again = try generator.generateClientOnly(document);
        defer allocator.free(multi_again);
        try std.testing.expectEqualStrings(multi, multi_again);
        if (!options_mode) try std.testing.expect(std.mem.indexOf(u8, multi, "Widget: []const u8") != null);
    }
}
