const std = @import("std");
const fixture = @import("provider_fixture");
comptime {
    _ = @import("provider_http_tests.zig");
}

test "fresh provider model declarations compile with collision references intact" {
    std.testing.refAllDecls(fixture);
    _ = fixture.resources.models.list;
    try std.testing.expect(@FieldType(fixture.FunctionTool, "parameters") == ?std.json.Value);
    try std.testing.expect(fixture.OwnerFooBar == i64);
    try std.testing.expect(fixture.OwnerFooBar_2 == bool);
    try std.testing.expect(fixture.CollectionItem == bool);
    try std.testing.expect(fixture.VariantVariant0 == bool);
    const owner: fixture.Owner = .{
        .@"foo-bar" = .{ .first = "first" },
        .foo_bar = .{ .second = 42 },
        .list = &.{.{ .nested = true }},
        .component = 17,
    };
    try std.testing.expectEqualStrings("first", owner.@"foo-bar".first.?);
    try std.testing.expectEqual(@as(i64, 42), owner.foo_bar.second.?);
    const destination: fixture.BetaTelemetryDestination = .{ .traces = .{ .enabled = true } };
    try std.testing.expect(destination.traces.enabled);
    const dream: fixture.BetaDream = .{ .usage = .{ .input_tokens = 3 } };
    try std.testing.expectEqual(@as(i64, 3), dream.usage.input_tokens);
}

test "open generated schema models round-trip arbitrary JSON schema keywords" {
    const allocator = std.testing.allocator;
    const source =
        \\{"type":"object","$schema":"https://json-schema.org/draft/2020-12/schema","additionalProperties":false,"properties":{"name":{"type":"string","minLength":2}},"required":["name"],"$defs":{"extra":{"oneOf":[{"type":"string"},{"type":"integer"}]}},"x-provider":{"nested":[true,null,1]}}
    ;
    inline for (.{ fixture.InputSchema, fixture.OpenDerived, @FieldType(fixture.Container, "schema") }) |T| {
        const parsed = try std.json.parseFromSlice(T, allocator, source, .{});
        defer parsed.deinit();
        const encoded = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
        defer allocator.free(encoded);
        try std.testing.expectEqualStrings(source, encoded);
    }
}

test "objects with schema-valued additional properties keep typed field access" {
    const parsed = try std.json.parseFromSlice(fixture.TypedOpen, std.testing.allocator, "{\"id\":\"one\",\"other\":\"ignored\"}", .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("one", parsed.value.id.?);
}
