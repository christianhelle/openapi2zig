const std = @import("std");
const sdk = @import("composition_fixture");

const object = "{\"base\":\"kept\",\"variant\":7,\"stream\":true}";

test "generated mixed compositions preserve base and variant fields" {
    std.testing.refAllDecls(sdk);
    inline for (.{ sdk.MixedOne, sdk.MixedAny, sdk.MixedBoth, sdk.VariantWrapperVariant0, sdk.VariantWrapper }) |T| {
        const parsed = try std.json.parseFromSlice(T, std.testing.allocator, object, .{});
        defer parsed.deinit();
        const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, parsed.value, .{});
        defer std.testing.allocator.free(encoded);
        try std.testing.expectEqualStrings(object, encoded);
    }
}

test "generated fields and array items preserve mixed composition data" {
    const payload = "{\"one\":" ++ object ++ ",\"any\":" ++ object ++ ",\"list\":[" ++ object ++ "]}";
    const parsed = try std.json.parseFromSlice(sdk.Envelope, std.testing.allocator, payload, .{});
    defer parsed.deinit();
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, parsed.value, .{});
    defer std.testing.allocator.free(encoded);
    const decoded = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, encoded, .{});
    defer decoded.deinit();
    for ([_]std.json.Value{
        decoded.value.object.get("one").?,
        decoded.value.object.get("any").?,
        decoded.value.object.get("list").?.array.items[0],
    }) |value| {
        try std.testing.expectEqualStrings("kept", value.object.get("base").?.string);
        try std.testing.expectEqual(@as(i64, 7), value.object.get("variant").?.integer);
        try std.testing.expect(value.object.get("stream").?.bool);
    }
}
