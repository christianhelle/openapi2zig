const std = @import("std");
const openapi2zig = @import("src/lib.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: Parse and detect version
    const openapi_content = try std.fs.cwd().readFileAlloc(allocator, "openapi/v3.0/petstore.json", 1024 * 1024);
    defer allocator.free(openapi_content);

    const version = try openapi2zig.detectVersion(allocator, openapi_content);
    std.debug.print("Detected API version: {}\n", .{version});

    // Example 2: Parse to unified document representation
    var unified_doc = try openapi2zig.parseToUnified(allocator, openapi_content);
    defer unified_doc.deinit(allocator);

    std.debug.print("API Info:\n", .{});
    std.debug.print("  Title: {s}\n", .{unified_doc.info.title});
    std.debug.print("  Version: {s}\n", .{unified_doc.info.version});
    if (unified_doc.info.description) |desc| {
        std.debug.print("  Description: {s}\n", .{desc});
    } else {
        std.debug.print("  Description: (none)\n", .{});
    }

    // Example 3: Generate Zig models and API client code
    const args = openapi2zig.CliArgs{
        .input_path = "openapi/v3.0/petstore.json",
        .output_path = null,
        .base_url = "https://petstore.swagger.io/v2",
    };

    const generated_code = try openapi2zig.generateCode(allocator, unified_doc, args);
    defer allocator.free(generated_code);

    std.debug.print("\nGenerated {} bytes of Zig code\n", .{generated_code.len});
    std.debug.print("First 500 characters:\n{s}...\n", .{generated_code[0..@min(500, generated_code.len)]});

    // Example 4: Use individual parsers for specific versions
    if (version == .v3_0) {
        var openapi_doc = try openapi2zig.parseOpenApi(allocator, openapi_content);
        defer openapi_doc.deinit(allocator);
        std.debug.print("\nParsed OpenAPI document with {} path(s)\n", .{openapi_doc.paths.path_items.count()});
    }

    std.debug.print("\nLibrary example completed successfully!\n", .{});
}
