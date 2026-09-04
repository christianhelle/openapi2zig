const std = @import("std");
const testing = std.testing;
const test_utils = @import("test_utils.zig");
const models = @import("../models.zig");
const OpenApiConverter = @import("../generators/converters/openapi_converter.zig").OpenApiConverter;

const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;

test "operation description containing tabs generates comments without tabs" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const spec =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "Tabbed", "version": "1.0.0" },
        \\  "paths": {
        \\    "/things": {
        \\      "get": {
        \\        "operationId": "listThings",
        \\        "description": "| Column\tone | Column\ttwo |",
        \\        "responses": { "200": { "description": "ok" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    // The converter borrows description strings from the parsed document, so the
    // parsed document has to outlive the unified one.
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, spec);
    defer parsed.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    var unified = try converter.convert(parsed);
    defer unified.deinit(allocator);

    var generator = UnifiedApiGenerator.init(allocator, .{ .input_path = "fixture.json" });
    defer generator.deinit();
    const code = try generator.generate(unified);
    defer allocator.free(code);

    // Zig rejects a tab inside a comment, so descriptions carried over from the
    // specification must have theirs replaced before they are emitted.
    try testing.expect(std.mem.indexOf(u8, code, "Column one") != null);
    try testing.expect(std.mem.indexOfScalar(u8, code, 0x09) == null);
}
