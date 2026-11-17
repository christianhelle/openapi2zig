const std = @import("std");
const models = @import("../models.zig");
const cli = @import("../cli.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const entry_count = 40;

/// Builds a spec whose paths and schemas are listed in forward or reverse order.
fn buildSpec(allocator: std.mem.Allocator, reverse: bool) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"t\",\"version\":\"1\"},\"paths\":{");
    for (0..entry_count) |n| {
        const i = if (reverse) entry_count - 1 - n else n;
        if (n != 0) try out.append(allocator, ',');
        try out.print(allocator, "\"/items{d}\":{{\"get\":{{\"operationId\":\"getItem{d}\",\"responses\":{{\"200\":{{\"description\":\"ok\",\"content\":{{\"application/json\":{{\"schema\":{{\"$ref\":\"#/components/schemas/Item{d}\"}}}}}}}}}}}}}}", .{ i, i, i });
    }
    try out.appendSlice(allocator, "},\"components\":{\"schemas\":{");
    for (0..entry_count) |n| {
        const i = if (reverse) entry_count - 1 - n else n;
        if (n != 0) try out.append(allocator, ',');
        try out.print(allocator, "\"Item{d}\":{{\"type\":\"object\",\"properties\":{{\"name\":{{\"type\":\"string\"}}}}}}", .{i});
    }
    try out.appendSlice(allocator, "}}}");
    return out.toOwnedSlice(allocator);
}

const Generated = struct {
    models: []u8,
    client: []u8,

    fn deinit(self: Generated, allocator: std.mem.Allocator) void {
        allocator.free(self.models);
        allocator.free(self.client);
    }
};

fn generate(allocator: std.mem.Allocator, reverse: bool, wrappers: cli.ResourceWrapperMode) !Generated {
    const spec = try buildSpec(allocator, reverse);
    defer allocator.free(spec);

    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const model_code = try model_generator.generate(unified);
    errdefer allocator.free(model_code);

    var api_generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json", .resource_wrappers = wrappers });
    defer api_generator.deinit();
    const client_code = try api_generator.generate(unified);

    return .{ .models = @constCast(model_code), .client = @constCast(client_code) };
}

test "generated output does not depend on the order of the spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const forward = try generate(allocator, false, .none);
    defer forward.deinit(allocator);
    const reverse = try generate(allocator, true, .none);
    defer reverse.deinit(allocator);

    try testing.expectEqualStrings(forward.models, reverse.models);
    try testing.expectEqualStrings(forward.client, reverse.client);
}

test "models and operations are emitted in sorted order" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const result = try generate(allocator, true, .none);
    defer result.deinit(allocator);

    const item1 = std.mem.indexOf(u8, result.models, "pub const Item1 = ").?;
    const item2 = std.mem.indexOf(u8, result.models, "pub const Item2 = ").?;
    const item10 = std.mem.indexOf(u8, result.models, "pub const Item10 = ").?;
    try testing.expect(item1 < item10);
    try testing.expect(item10 < item2);

    const get1 = std.mem.indexOf(u8, result.client, "pub fn getItem1(").?;
    const get10 = std.mem.indexOf(u8, result.client, "pub fn getItem10(").?;
    try testing.expect(get1 < get10);
}

test "resource wrappers do not depend on the order of the spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    inline for (.{ cli.ResourceWrapperMode.paths, cli.ResourceWrapperMode.tags, cli.ResourceWrapperMode.hybrid }) |mode| {
        const forward = try generate(allocator, false, mode);
        defer forward.deinit(allocator);
        const reverse = try generate(allocator, true, mode);
        defer reverse.deinit(allocator);
        try testing.expectEqualStrings(forward.client, reverse.client);
    }
}
