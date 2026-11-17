const std = @import("std");
const template = @import("../generators/sdk/template.zig");
const templates = @import("../generators/sdk/templates.zig");
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

fn testContext() templates.SdkContext {
    return .{
        .config = .{ .name = "petstore", .version = "1.2.3", .description = "Petstore SDK", .repository = "https://github.com/example/petstore-sdk-for-zig", .author = "Jane Doe" },
        .generator_version = "9.9.9",
        .base_url = "https://petstore.example.com/v1",
        .path_count = 3,
        .operation_count = 5,
        .schema_count = 7,
        .fingerprint = 0xabcdef0123456789,
    };
}

fn renderOwned(allocator: std.mem.Allocator, kind: templates.Kind) ![]u8 {
    return templates.render(allocator, kind, testContext());
}

test "root.zig template re-exports the generated modules" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try renderOwned(allocator, .root_zig);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "pub const client = @import(\"client.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const models = @import(\"models.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const runtime = @import(\"runtime.zig\");") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const Owned = runtime.Owned;") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub const api_base_url = \"https://petstore.example.com/v1\";") != null);
    try testing.expect(std.mem.indexOf(u8, out, "pub fn init(allocator: std.mem.Allocator, io: std.Io, token: []const u8) Client") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Petstore SDK") != null);
    try testing.expect(std.mem.indexOf(u8, out, "{{") == null);
}

test "every template renders without leftover placeholders" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    for (templates.all_kinds) |kind| {
        const out = try renderOwned(allocator, kind);
        defer allocator.free(out);
        try testing.expect(out.len > 0);
        if (kind != .ci and kind != .release) try testing.expect(std.mem.indexOf(u8, out, "{{") == null);
        try testing.expect(std.mem.indexOfScalar(u8, out, '\r') == null);
    }
}

test "compile_check.zig template walks every client declaration" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try renderOwned(allocator, .compile_check_zig);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "@import(\"client.zig\")") != null);
    try testing.expect(std.mem.indexOf(u8, out, "std.meta.declarations(client)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "@setEvalBranchQuota") != null);
}

test "build.zig template exports the module and the examples" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var ctx = testContext();
    ctx.examples = &.{ "quickstart", "list_pets" };
    const out = try templates.render(allocator, .build_zig, ctx);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "b.addModule(\"petstore\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"src/root.zig\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "    \"quickstart\",\n    \"list_pets\",\n};") != null);
    try testing.expect(std.mem.indexOf(u8, out, "b.step(\"check\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "b.step(\"examples\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, ".name = \"petstore\", .module = mod") != null);
}

test "fingerprint combines a package id with the name checksum" {
    const fp = templates.fingerprintFor("petstore", "https://github.com/example/petstore");
    try testing.expectEqual(@as(u64, std.hash.Crc32.hash("petstore")), fp >> 32);
    const id: u32 = @truncate(fp);
    try testing.expect(id != 0 and id != 0xffffffff);
    try testing.expectEqual(fp, templates.fingerprintFor("petstore", "https://github.com/example/petstore"));
    try testing.expect(fp != templates.fingerprintFor("petstore", "https://github.com/other/petstore"));
}

test "build.zig.zon template carries the package metadata" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try renderOwned(allocator, .build_zig_zon);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, ".name = .petstore,") != null);
    try testing.expect(std.mem.indexOf(u8, out, ".version = \"1.2.3\",") != null);
    try testing.expect(std.mem.indexOf(u8, out, ".fingerprint = 0xabcdef0123456789,") != null);
    try testing.expect(std.mem.indexOf(u8, out, ".minimum_zig_version = \"0.17.1\",") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\"CHANGELOG.md\",") != null);
}

test "scaffold and generated ownership" {
    try testing.expectEqual(@import("../generator/output_writer.zig").Ownership.scaffold, templates.Kind.build_zig_zon.ownership());
    try testing.expectEqual(@import("../generator/output_writer.zig").Ownership.generated, templates.Kind.build_zig.ownership());
}

test "static repository files render" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const ignore = try renderOwned(allocator, .gitignore);
    defer allocator.free(ignore);
    try testing.expect(std.mem.indexOf(u8, ignore, ".zig-cache/") != null);
    try testing.expect(std.mem.indexOf(u8, ignore, "zig-out/") != null);

    const attrs = try renderOwned(allocator, .gitattributes);
    defer allocator.free(attrs);
    try testing.expect(std.mem.indexOf(u8, attrs, "src/client.zig linguist-generated=true") != null);
    try testing.expect(std.mem.indexOf(u8, attrs, "openapi/openapi.json linguist-generated=true") != null);

    const license = try renderOwned(allocator, .license);
    defer allocator.free(license);
    try testing.expect(std.mem.indexOf(u8, license, "MIT License") != null);
    try testing.expect(std.mem.indexOf(u8, license, "Copyright (c) 2026 Jane Doe") != null);

    const changelog = try renderOwned(allocator, .changelog);
    defer allocator.free(changelog);
    try testing.expect(std.mem.indexOf(u8, changelog, "## 1.2.3") != null);
    try testing.expect(std.mem.indexOf(u8, changelog, "openapi2zig 9.9.9") != null);
}

test "license template only applies to MIT" {
    var ctx = testContext();
    try testing.expect(templates.applies(.license, ctx));
    ctx.config.license = "Apache-2.0";
    try testing.expect(!templates.applies(.license, ctx));
    try testing.expect(templates.applies(.gitignore, ctx));
}

test "template escapes doubled braces for github expressions" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try template.expand(allocator, "os: ${{{{ matrix.os }}}} v{{ v }}", &.{.{ .name = "v", .value = "1" }});
    defer allocator.free(out);
    try testing.expectEqualStrings("os: ${{ matrix.os }} v1", out);
}

test "readme template documents install and regeneration" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try renderOwned(allocator, .readme);
    defer allocator.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "# Petstore SDK") != null);
    try testing.expect(std.mem.indexOf(u8, out, "zig fetch --save git+https://github.com/example/petstore-sdk-for-zig#v1.2.3") != null);
    try testing.expect(std.mem.indexOf(u8, out, "b.dependency(\"petstore\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "all 3 paths (5 operations)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "7 schemas") != null);
    try testing.expect(std.mem.indexOf(u8, out, "openapi2zig 9.9.9") != null);
    try testing.expect(std.mem.indexOf(u8, out, "docs/REGENERATING.md") != null);
}

test "docs templates mention the generate command" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const regen = try renderOwned(allocator, .regenerating);
    defer allocator.free(regen);
    try testing.expect(std.mem.indexOf(u8, regen, "openapi2zig generate --sdk") != null);
    try testing.expect(std.mem.indexOf(u8, regen, "openapi/openapi.json") != null);

    const usage = try renderOwned(allocator, .usage);
    defer allocator.free(usage);
    try testing.expect(std.mem.indexOf(u8, usage, "https://petstore.example.com/v1") != null);
    try testing.expect(std.mem.indexOf(u8, usage, "ApiResult") != null);
}

test "workflow templates keep github expressions" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const ci = try renderOwned(allocator, .ci);
    defer allocator.free(ci);
    try testing.expect(std.mem.indexOf(u8, ci, "runs-on: ${{ matrix.os }}") != null);
    try testing.expect(std.mem.indexOf(u8, ci, "version: 0.17.1") != null);
    try testing.expect(std.mem.indexOf(u8, ci, "zig build check") != null);

    const release = try renderOwned(allocator, .release);
    defer allocator.free(release);
    try testing.expect(std.mem.indexOf(u8, release, "VERSION: ${{ inputs.version }}") != null);
    try testing.expect(std.mem.indexOf(u8, release, "gh release create") != null);
}

test "quickstart example imports the sdk module" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const out = try renderOwned(allocator, .quickstart);
    defer allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "@import(\"petstore\")") != null);
    try testing.expect(std.mem.indexOf(u8, out, "client.deinit()") != null);
}

test "root.zig template exports the runtime features that were generated" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var ctx = testContext();
    ctx.config.retry.max_retries = 3;
    const plain = try templates.render(allocator, .root_zig, ctx);
    defer allocator.free(plain);
    try testing.expect(std.mem.indexOf(u8, plain, "pub const TokenProvider = client.TokenProvider;") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "pub const RetryPolicy = client.RetryPolicy;") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "api.retry = .{ .max_retries = 3 };") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "pub fn initWithTokenProvider(") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "Pager") == null);
    try testing.expect(std.mem.indexOf(u8, plain, "ApiError") == null);

    ctx.pagination = true;
    ctx.typed_errors = true;
    const full = try templates.render(allocator, .root_zig, ctx);
    defer allocator.free(full);
    try testing.expect(std.mem.indexOf(u8, full, "pub const Pager = client.Pager;") != null);
    try testing.expect(std.mem.indexOf(u8, full, "pub const ApiError = client.ApiError;") != null);
    try testing.expect(std.mem.indexOf(u8, full, "pub const parseApiError = client.parseApiError;") != null);
}

test "sdk config reads the retry count" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const sdk_config = @import("../generators/sdk/config.zig");
    var parsed = try sdk_config.parse(allocator, "{ \"name\": \"pets\", \"retry\": { \"max_retries\": 4 }, \"generator\": { \"pagination\": true, \"typed_errors\": true } }");
    defer parsed.deinit();
    try testing.expectEqual(@as(u8, 4), parsed.value.retry.max_retries);
    const args = parsed.value.toCliArgs(.{ .input_path = "", .sdk = true });
    try testing.expect(args.pagination);
    try testing.expect(args.typed_errors);
}
