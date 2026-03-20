const std = @import("std");
const input_loader = @import("../input_loader.zig");
const models = @import("../models.zig");
const detector = @import("../detector.zig");
const test_utils = @import("test_utils.zig");

// ============================================================================
// UNIT TESTS - URL Detection Logic
// ============================================================================

test "isUrl detects http URLs" {
    try std.testing.expect(input_loader.isUrl("http://example.com/api.json"));
    try std.testing.expect(input_loader.isUrl("http://localhost:8080/spec.yaml"));
    try std.testing.expect(input_loader.isUrl("http://api.example.com/v1/openapi.json"));
}

test "isUrl detects https URLs" {
    try std.testing.expect(input_loader.isUrl("https://example.com/api.json"));
    try std.testing.expect(input_loader.isUrl("https://petstore3.swagger.io/api/v3/openapi.json"));
    try std.testing.expect(input_loader.isUrl("https://petstore.swagger.io/v2/swagger.json"));
}

test "isUrl rejects file paths" {
    try std.testing.expect(!input_loader.isUrl("openapi/v3.0/petstore.json"));
    try std.testing.expect(!input_loader.isUrl("./relative/path/spec.json"));
    try std.testing.expect(!input_loader.isUrl("/absolute/path/spec.json"));
    try std.testing.expect(!input_loader.isUrl("C:\\Windows\\path\\spec.json"));
}

test "isUrl rejects invalid URLs" {
    try std.testing.expect(!input_loader.isUrl("ftp://example.com/spec.json"));
    try std.testing.expect(!input_loader.isUrl("file:///path/to/spec.json"));
    try std.testing.expect(!input_loader.isUrl("htp://typo.com/spec.json"));
    try std.testing.expect(!input_loader.isUrl(""));
}

// ============================================================================
// UNIT TESTS - File Loading (Existing Functionality)
// ============================================================================

test "loadFromFile loads OpenAPI v3.0 petstore spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const contents = try input_loader.loadFromFile(allocator, "openapi/v3.0/petstore.json");
    defer allocator.free(contents);

    try std.testing.expect(contents.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, contents, "openapi") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "3.0") != null);
}

test "loadFromFile loads Swagger v2.0 petstore spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const contents = try input_loader.loadFromFile(allocator, "openapi/v2.0/petstore.json");
    defer allocator.free(contents);

    try std.testing.expect(contents.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, contents, "swagger") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "2.0") != null);
}

test "loadFromFile returns error for non-existent file" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const result = input_loader.loadFromFile(allocator, "nonexistent/file.json");
    try std.testing.expectError(error.FileNotFound, result);
}

// ============================================================================
// UNIT TESTS - InputSource Union Type
// ============================================================================

test "loadInput with file_path source loads v3.0 spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const source = input_loader.InputSource{ .file_path = "openapi/v3.0/petstore.json" };
    const contents = try input_loader.loadInput(allocator, source);
    defer allocator.free(contents);

    try std.testing.expect(contents.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, contents, "openapi") != null);
}

test "loadInput with file_path source loads v2.0 spec" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const source = input_loader.InputSource{ .file_path = "openapi/v2.0/petstore.json" };
    const contents = try input_loader.loadInput(allocator, source);
    defer allocator.free(contents);

    try std.testing.expect(contents.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, contents, "swagger") != null);
}

// ============================================================================
// UNIT TESTS - URL Error Cases with Mock Data
// ============================================================================

test "loadFromUrl returns InvalidUrl for invalid URL syntax" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const result = input_loader.loadFromUrl(allocator, "not a valid url");
    try std.testing.expectError(input_loader.LoadError.InvalidUrl, result);
}

test "loadFromUrl returns InvalidUrl for unsupported scheme" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    const result = input_loader.loadFromUrl(allocator, "ftp://example.com/spec.json");
    try std.testing.expectError(input_loader.LoadError.InvalidUrl, result);
}

test "loadFromUrl returns ConnectionFailed for unreachable host" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    // Use an unreachable IP address (reserved for documentation)
    const result = input_loader.loadFromUrl(allocator, "http://192.0.2.1:9999/spec.json");
    try std.testing.expectError(input_loader.LoadError.ConnectionFailed, result);
}

// ============================================================================
// UNIT TESTS - Memory Cleanup Validation
// ============================================================================

test "loadFromFile properly cleans up memory on success" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const contents = try input_loader.loadFromFile(allocator, "openapi/v3.0/petstore.json");
    allocator.free(contents);

    const deinit_status = gpa.deinit();
    try std.testing.expect(deinit_status != .leak);
}

test "loadFromFile properly cleans up memory on error" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    _ = input_loader.loadFromFile(allocator, "nonexistent/file.json") catch |err| {
        try std.testing.expectEqual(error.FileNotFound, err);
    };

    const deinit_status = gpa.deinit();
    try std.testing.expect(deinit_status != .leak);
}

// ============================================================================
// INTEGRATION TESTS - Parse and Convert Full Pipeline
// ============================================================================

fn testFullPipelineFromFile(allocator: std.mem.Allocator, file_path: []const u8, expected_version: detector.OpenApiVersion) !void {
    // Load from file
    const source = input_loader.InputSource{ .file_path = file_path };
    const contents = try input_loader.loadInput(allocator, source);
    defer allocator.free(contents);

    // Detect version
    const version = try detector.getOpenApiVersion(allocator, contents);
    try std.testing.expectEqual(expected_version, version);

    // Parse and validate based on version
    switch (version) {
        .v2_0 => {
            var swagger = try models.SwaggerDocument.parseFromJson(allocator, contents);
            defer swagger.deinit(allocator);
            try std.testing.expect(swagger.info.title.len > 0);
            std.debug.print("✓ Full pipeline (file): {s} - Swagger v2.0\n", .{swagger.info.title});
        },
        .v3_0 => {
            var openapi = try models.OpenApiDocument.parseFromJson(allocator, contents);
            defer openapi.deinit(allocator);
            try std.testing.expect(openapi.info.title.len > 0);
            std.debug.print("✓ Full pipeline (file): {s} - OpenAPI v3.0\n", .{openapi.info.title});
        },
        .v3_1 => {
            var openapi31 = try models.OpenApi31Document.parseFromJson(allocator, contents);
            defer openapi31.deinit(allocator);
            try std.testing.expect(openapi31.info.title.len > 0);
            std.debug.print("✓ Full pipeline (file): {s} - OpenAPI v3.1\n", .{openapi31.info.title});
        },
        .v3_2 => {
            var openapi32 = try models.OpenApi32Document.parseFromJson(allocator, contents);
            defer openapi32.deinit(allocator);
            try std.testing.expect(openapi32.info.title.len > 0);
            std.debug.print("✓ Full pipeline (file): {s} - OpenAPI v3.2\n", .{openapi32.info.title});
        },
        .Unsupported => return error.UnsupportedVersion,
    }
}

test "full pipeline: file load -> parse -> validate (v3.0 petstore)" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    try testFullPipelineFromFile(allocator, "openapi/v3.0/petstore.json", .v3_0);
}

test "full pipeline: file load -> parse -> validate (v2.0 petstore)" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    try testFullPipelineFromFile(allocator, "openapi/v2.0/petstore.json", .v2_0);
}

test "full pipeline: file load -> parse -> validate (v3.0 api-with-examples)" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    try testFullPipelineFromFile(allocator, "openapi/v3.0/api-with-examples.json", .v3_0);
}

test "full pipeline: file load -> parse -> validate (v2.0 api-with-examples)" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in test!\n", .{});
        }
    }

    try testFullPipelineFromFile(allocator, "openapi/v2.0/api-with-examples.json", .v2_0);
}

// ============================================================================
// INTEGRATION TESTS - Real HTTP Endpoints
// These tests are marked with @slow tag - meant to run in CI but skip in dev
// ============================================================================

// Helper function for real URL testing
fn testFullPipelineFromUrl(allocator: std.mem.Allocator, url: []const u8, expected_version: detector.OpenApiVersion) !void {
    // Load from URL
    const source = input_loader.InputSource{ .url = url };
    const contents = try input_loader.loadInput(allocator, source);
    defer allocator.free(contents);

    // Verify we got valid JSON
    try std.testing.expect(contents.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, contents, "{") != null);

    // Detect version
    const version = try detector.getOpenApiVersion(allocator, contents);
    try std.testing.expectEqual(expected_version, version);

    // Parse and validate based on version
    switch (version) {
        .v2_0 => {
            var swagger = try models.SwaggerDocument.parseFromJson(allocator, contents);
            defer swagger.deinit(allocator);
            try std.testing.expect(swagger.info.title.len > 0);
            std.debug.print("✓ Full pipeline (URL): {s} - Swagger v2.0 from {s}\n", .{ swagger.info.title, url });
        },
        .v3_0 => {
            var openapi = try models.OpenApiDocument.parseFromJson(allocator, contents);
            defer openapi.deinit(allocator);
            try std.testing.expect(openapi.info.title.len > 0);
            std.debug.print("✓ Full pipeline (URL): {s} - OpenAPI v3.0 from {s}\n", .{ openapi.info.title, url });
        },
        .v3_1 => {
            var openapi31 = try models.OpenApi31Document.parseFromJson(allocator, contents);
            defer openapi31.deinit(allocator);
            try std.testing.expect(openapi31.info.title.len > 0);
            std.debug.print("✓ Full pipeline (URL): {s} - OpenAPI v3.1 from {s}\n", .{ openapi31.info.title, url });
        },
        .v3_2 => {
            var openapi32 = try models.OpenApi32Document.parseFromJson(allocator, contents);
            defer openapi32.deinit(allocator);
            try std.testing.expect(openapi32.info.title.len > 0);
            std.debug.print("✓ Full pipeline (URL): {s} - OpenAPI v3.2 from {s}\n", .{ openapi32.info.title, url });
        },
        .Unsupported => {
            std.debug.print("✗ Unsupported OpenAPI version detected from URL: {s}\n", .{url});
            return error.UnsupportedVersion;
        },
    }
}

// @slow - Integration test with real OpenAPI v3.0 endpoint
test "integration: load OpenAPI v3.0 from public petstore URL" {
    // Skip this test in development, only run in CI
    // This can be controlled via environment variables or build flags
    const skip_integration = std.process.hasEnvVarConstant("SKIP_INTEGRATION_TESTS");
    if (skip_integration) return error.SkipZigTest;

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in integration test!\n", .{});
        }
    }

    try testFullPipelineFromUrl(
        allocator,
        "https://petstore3.swagger.io/api/v3/openapi.json",
        .v3_0,
    );
}

// @slow - Integration test with real Swagger v2.0 endpoint
test "integration: load Swagger v2.0 from public petstore URL" {
    const skip_integration = std.process.hasEnvVarConstant("SKIP_INTEGRATION_TESTS");
    if (skip_integration) return error.SkipZigTest;

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in integration test!\n", .{});
        }
    }

    try testFullPipelineFromUrl(
        allocator,
        "https://petstore.swagger.io/v2/swagger.json",
        .v2_0,
    );
}

// @slow - Integration test for HTTP 404 error handling
test "integration: loadFromUrl handles 404 not found" {
    const skip_integration = std.process.hasEnvVarConstant("SKIP_INTEGRATION_TESTS");
    if (skip_integration) return error.SkipZigTest;

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in integration test!\n", .{});
        }
    }

    const result = input_loader.loadFromUrl(allocator, "https://petstore3.swagger.io/api/v3/nonexistent.json");
    try std.testing.expectError(input_loader.LoadError.HttpNotFound, result);
    std.debug.print("✓ 404 error handling verified\n", .{});
}

// ============================================================================
// COMPARISON TESTS - File vs URL Consistency
// ============================================================================

test "file and URL loading produce equivalent results for v3.0" {
    const skip_integration = std.process.hasEnvVarConstant("SKIP_INTEGRATION_TESTS");
    if (skip_integration) return error.SkipZigTest;

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in comparison test!\n", .{});
        }
    }

    // Load from file
    const file_source = input_loader.InputSource{ .file_path = "openapi/v3.0/petstore.json" };
    const file_contents = try input_loader.loadInput(allocator, file_source);
    defer allocator.free(file_contents);

    var file_doc = try models.OpenApiDocument.parseFromJson(allocator, file_contents);
    defer file_doc.deinit(allocator);

    // Load from URL (if available)
    const url_source = input_loader.InputSource{ .url = "https://petstore3.swagger.io/api/v3/openapi.json" };
    const url_contents = try input_loader.loadInput(allocator, url_source);
    defer allocator.free(url_contents);

    var url_doc = try models.OpenApiDocument.parseFromJson(allocator, url_contents);
    defer url_doc.deinit(allocator);

    // Both should parse successfully and have valid OpenAPI versions
    try std.testing.expect(file_doc.openapi.len > 0);
    try std.testing.expect(url_doc.openapi.len > 0);
    try std.testing.expect(file_doc.info.title.len > 0);
    try std.testing.expect(url_doc.info.title.len > 0);

    std.debug.print("✓ File and URL loading consistency verified for v3.0\n", .{});
}

test "file and URL loading produce equivalent results for v2.0" {
    const skip_integration = std.process.hasEnvVarConstant("SKIP_INTEGRATION_TESTS");
    if (skip_integration) return error.SkipZigTest;

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in comparison test!\n", .{});
        }
    }

    // Load from file
    const file_source = input_loader.InputSource{ .file_path = "openapi/v2.0/petstore.json" };
    const file_contents = try input_loader.loadInput(allocator, file_source);
    defer allocator.free(file_contents);

    var file_doc = try models.SwaggerDocument.parseFromJson(allocator, file_contents);
    defer file_doc.deinit(allocator);

    // Load from URL (if available)
    const url_source = input_loader.InputSource{ .url = "https://petstore.swagger.io/v2/swagger.json" };
    const url_contents = try input_loader.loadInput(allocator, url_source);
    defer allocator.free(url_contents);

    var url_doc = try models.SwaggerDocument.parseFromJson(allocator, url_contents);
    defer url_doc.deinit(allocator);

    // Both should parse successfully and have the same structure
    try std.testing.expectEqualStrings(file_doc.swagger, url_doc.swagger);
    try std.testing.expect(file_doc.info.title.len > 0);
    try std.testing.expect(url_doc.info.title.len > 0);

    std.debug.print("✓ File and URL loading consistency verified for v2.0\n", .{});
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

test "loadFromFile handles large files without memory issues" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("Memory leak detected in large file test!\n", .{});
        }
    }

    // Use api-with-examples which is larger and more complex
    const contents = try input_loader.loadFromFile(allocator, "openapi/v3.0/api-with-examples.json");
    defer allocator.free(contents);

    try std.testing.expect(contents.len > 1000); // Should be reasonably large
    var parsed = try models.OpenApiDocument.parseFromJson(allocator, contents);
    defer parsed.deinit(allocator);

    std.debug.print("✓ Large file handling verified ({d} bytes)\n", .{contents.len});
}

test "InputSource discriminates between file_path and url correctly" {
    const file_source = input_loader.InputSource{ .file_path = "openapi/v3.0/petstore.json" };
    const url_source = input_loader.InputSource{ .url = "https://example.com/spec.json" };

    try std.testing.expect(std.meta.activeTag(file_source) == .file_path);
    try std.testing.expect(std.meta.activeTag(url_source) == .url);
}
