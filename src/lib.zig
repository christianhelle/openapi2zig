//! openapi2zig - A Zig library for parsing OpenAPI/Swagger specifications
//!
//! This library provides functionality to parse both OpenAPI v3.0 and Swagger v2.0
//! specifications and convert them to a unified document representation.
//!
//! Example usage:
//!
//! ```zig
//! const std = @import("std");
//! const openapi2zig = @import("openapi2zig");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     // Detect OpenAPI version
//!     const json_content = try std.fs.cwd().readFileAlloc(allocator, "api.json", 1024 * 1024);
//!     defer allocator.free(json_content);
//!
//!     const version = try openapi2zig.detectVersion(allocator, json_content);
//!     std.debug.print("Detected version: {}\n", .{version});
//!
//!     // Parse and convert to unified document
//!     var unified_doc = try openapi2zig.parseToUnified(allocator, json_content);
//!     defer unified_doc.deinit(allocator);
//!
//!     std.debug.print("API title: {s}\n", .{unified_doc.info.title});
//! }
//! ```

const std = @import("std");

// Core version detection
pub const ApiVersion = @import("detector.zig").OpenApiVersion;
pub const detectVersion = @import("detector.zig").getOpenApiVersion;

// Document models
pub const models = @import("models.zig");
pub const OpenApiDocument = models.OpenApiDocument;
pub const SwaggerDocument = models.SwaggerDocument;

// Unified document representation
pub const UnifiedDocument = @import("models/common/document.zig").UnifiedDocument;
pub const DocumentInfo = @import("models/common/document.zig").DocumentInfo;
pub const ContactInfo = @import("models/common/document.zig").ContactInfo;
pub const LicenseInfo = @import("models/common/document.zig").LicenseInfo;
pub const ExternalDocumentation = @import("models/common/document.zig").ExternalDocumentation;
pub const Tag = @import("models/common/document.zig").Tag;
pub const Server = @import("models/common/document.zig").Server;
pub const SecurityRequirement = @import("models/common/document.zig").SecurityRequirement;
pub const Schema = @import("models/common/document.zig").Schema;
pub const SchemaType = @import("models/common/document.zig").SchemaType;
pub const Parameter = @import("models/common/document.zig").Parameter;
pub const ParameterLocation = @import("models/common/document.zig").ParameterLocation;
pub const Response = @import("models/common/document.zig").Response;
pub const Operation = @import("models/common/document.zig").Operation;
pub const PathItem = @import("models/common/document.zig").PathItem;

// Converters for transforming version-specific documents to unified representation
pub const SwaggerConverter = @import("generators/converters/swagger_converter.zig").SwaggerConverter;
pub const OpenApiConverter = @import("generators/converters/openapi_converter.zig").OpenApiConverter;

// Code generators
pub const UnifiedModelGenerator = @import("generators/unified/model_generator.zig").UnifiedModelGenerator;
pub const UnifiedApiGenerator = @import("generators/unified/api_generator.zig").UnifiedApiGenerator;

// CLI argument types for code generation
pub const CliArgs = @import("cli.zig").CliArgs;

/// Parse a JSON string containing an OpenAPI or Swagger specification and convert it to a unified document representation.
/// The caller is responsible for calling `deinit()` on the returned document.
///
/// Parameters:
/// - allocator: Memory allocator to use for parsing and conversion
/// - json_content: JSON string containing the OpenAPI/Swagger specification
///
/// Returns:
/// - UnifiedDocument: A unified representation that works with both OpenAPI v3.0 and Swagger v2.0
///
/// Errors:
/// - Returns error if JSON parsing fails, version detection fails, or conversion fails
pub fn parseToUnified(allocator: std.mem.Allocator, json_content: []const u8) !UnifiedDocument {
    const version = try detectVersion(allocator, json_content);

    switch (version) {
        .v3_0 => {
            var openapi_doc = try OpenApiDocument.parseFromJson(allocator, json_content);
            defer openapi_doc.deinit(allocator);

            var converter = OpenApiConverter.init(allocator);

            return try converter.convert(openapi_doc);
        },
        .v2_0 => {
            var swagger_doc = try SwaggerDocument.parseFromJson(allocator, json_content);
            defer swagger_doc.deinit(allocator);

            var converter = SwaggerConverter.init(allocator);

            return try converter.convert(swagger_doc);
        },
        .Unsupported, .v3_1 => {
            return error.UnsupportedApiVersion;
        },
    }
}

/// Parse a JSON string containing an OpenAPI v3.0 specification.
/// The caller is responsible for calling `deinit()` on the returned document.
///
/// Parameters:
/// - allocator: Memory allocator to use for parsing
/// - json_content: JSON string containing the OpenAPI v3.0 specification
///
/// Returns:
/// - OpenApiDocument: Parsed OpenAPI v3.0 document
pub fn parseOpenApi(allocator: std.mem.Allocator, json_content: []const u8) !OpenApiDocument {
    return try OpenApiDocument.parseFromJson(allocator, json_content);
}

/// Parse a JSON string containing a Swagger v2.0 specification.
/// The caller is responsible for calling `deinit()` on the returned document.
///
/// Parameters:
/// - allocator: Memory allocator to use for parsing
/// - json_content: JSON string containing the Swagger v2.0 specification
///
/// Returns:
/// - SwaggerDocument: Parsed Swagger v2.0 document
pub fn parseSwagger(allocator: std.mem.Allocator, json_content: []const u8) !SwaggerDocument {
    return try SwaggerDocument.parseFromJson(allocator, json_content);
}

/// Generate Zig model structs from a unified document.
///
/// Parameters:
/// - allocator: Memory allocator to use for code generation
/// - unified_doc: The unified document containing schema definitions
///
/// Returns:
/// - String containing generated Zig model code
pub fn generateModels(allocator: std.mem.Allocator, unified_doc: UnifiedDocument) ![]const u8 {
    var generator = UnifiedModelGenerator.init(allocator);
    defer generator.deinit();

    return try generator.generate(unified_doc);
}

/// Generate Zig API client functions from a unified document.
///
/// Parameters:
/// - allocator: Memory allocator to use for code generation
/// - unified_doc: The unified document containing API operations
/// - args: CLI arguments for customizing code generation
///
/// Returns:
/// - String containing generated Zig API client code
pub fn generateApi(allocator: std.mem.Allocator, unified_doc: UnifiedDocument, args: CliArgs) ![]const u8 {
    var generator = UnifiedApiGenerator.init(allocator, args);
    defer generator.deinit();

    return try generator.generate(unified_doc);
}

/// Generate complete Zig code (models + API client) from a unified document.
///
/// Parameters:
/// - allocator: Memory allocator to use for code generation
/// - unified_doc: The unified document containing schema and operation definitions
/// - args: CLI arguments for customizing code generation
///
/// Returns:
/// - String containing complete generated Zig code
pub fn generateCode(allocator: std.mem.Allocator, unified_doc: UnifiedDocument, args: CliArgs) ![]const u8 {
    const models_code = try generateModels(allocator, unified_doc);
    defer allocator.free(models_code);

    const api_code = try generateApi(allocator, unified_doc, args);
    defer allocator.free(api_code);

    const header =
        \\///////////////////////////////////////////
        \\// Generated Zig code from OpenAPI
        \\///////////////////////////////////////////
        \\
        \\const std = @import("std");
        \\
        \\
    ;

    return try std.fmt.allocPrint(allocator, "{s}{s}\n{s}", .{ header, models_code, api_code });
}

/// Convert a version-specific OpenAPI document to unified representation.
///
/// Parameters:
/// - allocator: Memory allocator to use for conversion
/// - openapi_doc: Parsed OpenAPI v3.0 document
///
/// Returns:
/// - UnifiedDocument: Unified representation of the OpenAPI document
pub fn convertOpenApiToUnified(allocator: std.mem.Allocator, openapi_doc: OpenApiDocument) !UnifiedDocument {
    var converter = OpenApiConverter.init(allocator);

    return try converter.convert(openapi_doc);
}

/// Convert a version-specific Swagger document to unified representation.
///
/// Parameters:
/// - allocator: Memory allocator to use for conversion
/// - swagger_doc: Parsed Swagger v2.0 document
///
/// Returns:
/// - UnifiedDocument: Unified representation of the Swagger document
pub fn convertSwaggerToUnified(allocator: std.mem.Allocator, swagger_doc: SwaggerDocument) !UnifiedDocument {
    var converter = SwaggerConverter.init(allocator);

    return try converter.convert(swagger_doc);
}

// Version information
pub const version_info = @import("version_info.zig");

// Test utilities for library users
pub const test_utils = @import("tests/test_utils.zig");

test {
    // Import all tests to ensure they're run when testing the library
    std.testing.refAllDecls(@This());
    _ = @import("tests.zig");
}
