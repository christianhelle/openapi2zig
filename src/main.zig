const models = @import("models.zig");
const openapi = @import("openapi.zig");

const std = @import("std");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush(); // Don't forget to flush!
}

const OpenAPI = struct {
    openapi: []const u8,
};

test "can deserialize openapi version" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(OpenAPI, allocator,
        \\{ "openapi": "3.0.0" }
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("3.0.0", parsed.value.openapi);
}

test "can deserialize petstore.json" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try std.json.parseFromSlice(OpenAPI, allocator, file_contents, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("3.0.2", parsed.value.openapi);
}

test "can deserialize petstore into OpenApiDocument" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try models.OpenApiDocument.parse(allocator, file_contents);
    try std.testing.expectEqualStrings("3.0.2", parsed.openapi);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);
}

test "can deserialize petstore into new OpenAPI v3.0 structures" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("openapi/petstore.json", .{});
    defer file.close();
    try file.seekBy(0);
    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    const parsed = try openapi.OpenAPI.parse(allocator, file_contents);
    
    // Test basic required fields
    try std.testing.expectEqualStrings("3.0.2", parsed.openapi);
    try std.testing.expectEqualStrings("Swagger Petstore", parsed.info.title);
    try std.testing.expectEqualStrings("1.0.5", parsed.info.version);
    
    // Test optional info fields
    try std.testing.expect(parsed.info.description != null);
    try std.testing.expect(parsed.info.termsOfService != null);
    try std.testing.expect(parsed.info.contact != null);
    try std.testing.expect(parsed.info.license != null);
    
    // Test contact details
    if (parsed.info.contact) |contact| {
        try std.testing.expectEqualStrings("apiteam@swagger.io", contact.email.?);
    }
    
    // Test license details
    if (parsed.info.license) |license| {
        try std.testing.expectEqualStrings("Apache 2.0", license.name);
        try std.testing.expect(license.url != null);
    }
    
    // Test external documentation
    try std.testing.expect(parsed.externalDocs != null);
    if (parsed.externalDocs) |ext_docs| {
        try std.testing.expectEqualStrings("http://swagger.io", ext_docs.url);
        try std.testing.expectEqualStrings("Find out more about Swagger", ext_docs.description.?);
    }
    
    // Test tags
    try std.testing.expect(parsed.tags != null);
    if (parsed.tags) |tags| {
        try std.testing.expect(tags.len > 0);
        try std.testing.expectEqualStrings("pet", tags[0].name);
    }
    
    // Test security requirements
    try std.testing.expect(parsed.security != null);
    if (parsed.security) |security| {
        try std.testing.expect(security.len > 0);
    }
    
    // Test paths exist and contain operations
    try std.testing.expect(parsed.paths.paths.count() > 0);
    
    // Test that we can access a specific path
    const pet_path = parsed.paths.paths.get("/pet");
    try std.testing.expect(pet_path != null);
    if (pet_path) |path| {
        try std.testing.expect(path.put != null);
        try std.testing.expect(path.post != null);
    }
}
