const std = @import("std");
const cli = @import("../cli.zig");
const sdk_config = @import("../generators/sdk/config.zig");
const test_utils = @import("test_utils.zig");

const testing = std.testing;

const full_config =
    \\{
    \\  "name": "msgraph",
    \\  "version": "1.2.3",
    \\  "description": "Microsoft Graph SDK for Zig",
    \\  "repository": "https://github.com/example/msgraph-sdk-for-zig",
    \\  "author": "Jane Doe",
    \\  "license": "MIT",
    \\  "minimum_zig_version": "0.17.1",
    \\  "spec": "openapi/openapi.yaml",
    \\  "base_url": "https://graph.example.com/v1.0",
    \\  "generator": { "resource_wrappers": "tags", "parameters_as_struct": true, "tags": ["users", "groups"] }
    \\}
;

test "sdk config parses every field" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try sdk_config.parse(allocator, full_config);
    defer parsed.deinit();
    const config = parsed.value;

    try testing.expectEqualStrings("msgraph", config.name);
    try testing.expectEqualStrings("1.2.3", config.version);
    try testing.expectEqualStrings("Jane Doe", config.author);
    try testing.expectEqualStrings("openapi/openapi.yaml", config.spec.?);
    try testing.expectEqualStrings("https://graph.example.com/v1.0", config.base_url.?);
    try testing.expectEqual(cli.ResourceWrapperMode.tags, config.generator.resource_wrappers);
    try testing.expect(config.generator.parameters_as_struct);
    try testing.expectEqual(@as(usize, 2), config.generator.tags.len);
}

test "sdk config applies defaults for a minimal config" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try sdk_config.parse(allocator, "{\"name\": \"petstore\"}");
    defer parsed.deinit();
    const config = parsed.value;

    try testing.expectEqualStrings("0.1.0", config.version);
    try testing.expectEqualStrings("MIT", config.license);
    try testing.expectEqualStrings("0.17.1", config.minimum_zig_version);
    try testing.expect(config.spec == null);
    try testing.expect(config.base_url == null);
    try testing.expectEqual(cli.ResourceWrapperMode.paths, config.generator.resource_wrappers);
    try testing.expect(!config.generator.parameters_as_struct);
    try testing.expectEqual(@as(usize, 0), config.generator.tags.len);
}

test "sdk config rejects unknown keys" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    try testing.expectError(error.InvalidConfig, sdk_config.parse(allocator, "{\"name\": \"petstore\", \"nmae\": \"typo\"}"));
}

test "sdk config rejects invalid names" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    try testing.expectError(error.InvalidConfig, sdk_config.parse(allocator, "{\"name\": \"Pet-Store\"}"));
    try testing.expectError(error.InvalidConfig, sdk_config.parse(allocator, "{}"));
    try testing.expectError(error.InvalidConfig, sdk_config.parse(allocator, "not json"));
}

test "sdk config renders a default config for a name" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const rendered = try sdk_config.renderDefault(allocator, "petstore", "openapi/petstore.json");
    defer allocator.free(rendered);

    var parsed = try sdk_config.parse(allocator, rendered);
    defer parsed.deinit();
    try testing.expectEqualStrings("petstore", parsed.value.name);
    try testing.expectEqualStrings("openapi/petstore.json", parsed.value.spec.?);
}

test "sdk config maps onto cli args" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try sdk_config.parse(allocator, full_config);
    defer parsed.deinit();

    const args = parsed.value.toCliArgs(.{ .input_path = "from-cli.json", .sdk = true });

    try testing.expectEqualStrings("from-cli.json", args.input_path);
    try testing.expect(args.multiple_files);
    try testing.expect(args.sdk);
    try testing.expectEqual(cli.ResourceWrapperMode.tags, args.resource_wrappers);
    try testing.expect(args.parameters_as_struct);
    try testing.expectEqualStrings("https://graph.example.com/v1.0", args.base_url.?);
    try testing.expectEqual(@as(usize, 2), args.tags.len);
}

test "sdk config uses the config spec when the cli has no input" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try sdk_config.parse(allocator, full_config);
    defer parsed.deinit();

    const args = parsed.value.toCliArgs(.{ .input_path = "", .sdk = true });
    try testing.expectEqualStrings("openapi/openapi.yaml", args.input_path);
}

test "sdk config cli base url wins over the config" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try sdk_config.parse(allocator, full_config);
    defer parsed.deinit();

    const args = parsed.value.toCliArgs(.{ .input_path = "", .base_url = "https://cli.example.com", .sdk = true });
    try testing.expectEqualStrings("https://cli.example.com", args.base_url.?);
}

test "sdk config selects the model naming" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var parsed = try sdk_config.parse(allocator, "{ \"name\": \"pets\", \"generator\": { \"model_naming\": \"namespaced\" } }");
    defer parsed.deinit();
    const args = parsed.value.toCliArgs(.{ .input_path = "", .sdk = true });
    try testing.expectEqual(@import("../generators/unified/model_names.zig").Mode.namespaced, args.model_naming);

    var defaults = try sdk_config.parse(allocator, "{ \"name\": \"pets\" }");
    defer defaults.deinit();
    try testing.expectEqual(@import("../generators/unified/model_names.zig").Mode.raw, defaults.value.generator.model_naming);
}
