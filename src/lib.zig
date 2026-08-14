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
//! pub fn main(init: std.process.Init) !void {
//!     const allocator = init.gpa;
//!     const io = init.io;
//!
//!     // Detect OpenAPI version
//!     const json_content = try std.Io.Dir.cwd().readFileAlloc(io, "api.json", allocator, .limited(1024 * 1024));
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
const yaml_loader = @import("yaml_loader.zig");
const generated_header = @import("generators/generated_header.zig");

// Core version detection
pub const ApiVersion = @import("detector.zig").OpenApiVersion;
pub const detectVersion = @import("detector.zig").getOpenApiVersion;

// Document models
pub const models = @import("models.zig");
pub const OpenApiDocument = models.OpenApiDocument;
pub const OpenApi31Document = models.OpenApi31Document;
pub const OpenApi32Document = models.OpenApi32Document;
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
pub const OpenApi31Converter = @import("generators/converters/openapi31_converter.zig").OpenApi31Converter;
pub const OpenApi32Converter = @import("generators/converters/openapi32_converter.zig").OpenApi32Converter;

// Document filtering
pub const DocumentFilter = @import("document_filter.zig");

// Code generators
pub const UnifiedModelGenerator = @import("generators/unified/model_generator.zig").UnifiedModelGenerator;
pub const UnifiedApiGenerator = @import("generators/unified/api_generator.zig").UnifiedApiGenerator;
pub const RuntimeGenerator = @import("generators/unified/runtime_generator.zig").RuntimeGenerator;

// CLI argument types for code generation
pub const CliArgs = @import("cli.zig").CliArgs;
pub const yamlToJson = yaml_loader.yamlToJson;

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
        .v3_0 => return parseUnifiedWithSourceDoc(allocator, json_content, OpenApiDocument, OpenApiConverter),
        .v2_0 => return parseUnifiedWithSourceDoc(allocator, json_content, SwaggerDocument, SwaggerConverter),
        .v3_1 => return parseUnifiedWithSourceDoc(allocator, json_content, OpenApi31Document, OpenApi31Converter),
        .v3_2 => return parseUnifiedWithSourceDoc(allocator, json_content, OpenApi32Document, OpenApi32Converter),
        .Unsupported => {
            return error.UnsupportedApiVersion;
        },
    }
}

/// Parse a version-specific document, convert it to a unified document, and
/// keep the parsed document alive as an owned source so the borrowed string
/// slices in the unified document remain valid until it is deinitialized.
fn parseUnifiedWithSourceDoc(
    allocator: std.mem.Allocator,
    json_content: []const u8,
    comptime DocType: type,
    comptime Converter: type,
) !UnifiedDocument {
    const doc = try allocator.create(DocType);
    errdefer allocator.destroy(doc);
    doc.* = try DocType.parseFromJson(allocator, json_content);
    errdefer doc.deinit(allocator);
    var unified = try convertDocument(allocator, doc.*, Converter);
    unified._owned_source = doc;
    unified._owned_source_deinit = sourceDocDeinit(DocType);
    return unified;
}

fn sourceDocDeinit(comptime DocType: type) *const fn (source: *anyopaque, allocator: std.mem.Allocator) void {
    return &struct {
        fn deinitSource(source: *anyopaque, allocator: std.mem.Allocator) void {
            const doc: *DocType = @ptrCast(@alignCast(source));
            doc.deinit(allocator);
            allocator.destroy(doc);
        }
    }.deinitSource;
}

/// Detect the OpenAPI/Swagger version from a YAML specification.
pub fn detectVersionFromYaml(allocator: std.mem.Allocator, yaml_content: []const u8) !ApiVersion {
    const json_content = try yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);
    return try detectVersion(allocator, json_content);
}

fn parseYaml(comptime T: type, allocator: std.mem.Allocator, yaml_content: []const u8) !T {
    const json_content = try yamlToJson(allocator, yaml_content);
    defer allocator.free(json_content);
    return try T.parseFromJson(allocator, json_content);
}

/// Parse a YAML string containing an OpenAPI v3.0 specification.
/// The caller is responsible for calling `deinit()` on the returned document.
pub fn parseOpenApiYaml(allocator: std.mem.Allocator, yaml_content: []const u8) !OpenApiDocument {
    return parseYaml(OpenApiDocument, allocator, yaml_content);
}

/// Parse a YAML string containing an OpenAPI v3.1 specification.
/// The caller is responsible for calling `deinit()` on the returned document.
pub fn parseOpenApi31Yaml(allocator: std.mem.Allocator, yaml_content: []const u8) !OpenApi31Document {
    return parseYaml(OpenApi31Document, allocator, yaml_content);
}

/// Parse a YAML string containing an OpenAPI v3.2 specification.
/// The caller is responsible for calling `deinit()` on the returned document.
pub fn parseOpenApi32Yaml(allocator: std.mem.Allocator, yaml_content: []const u8) !OpenApi32Document {
    return parseYaml(OpenApi32Document, allocator, yaml_content);
}

/// Parse a YAML string containing a Swagger v2.0 specification.
/// The caller is responsible for calling `deinit()` on the returned document.
pub fn parseSwaggerYaml(allocator: std.mem.Allocator, yaml_content: []const u8) !SwaggerDocument {
    return parseYaml(SwaggerDocument, allocator, yaml_content);
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
/// - io: Standard I/O context for reading the generation timestamp
/// - unified_doc: The unified document containing schema and operation definitions
/// - args: CLI arguments for customizing code generation
///
/// Returns:
/// - String containing complete generated Zig code
pub fn generateCode(allocator: std.mem.Allocator, io: std.Io, unified_doc: UnifiedDocument, args: CliArgs) ![]const u8 {
    const models_code = try generateModels(allocator, unified_doc);
    defer allocator.free(models_code);

    const header = try generated_header.renderNowFromBuildInfo(allocator, io);
    defer allocator.free(header);

    if (args.models_only) {
        return try std.mem.concat(allocator, u8, &.{ header, models_code });
    }

    const api_code = try generateApi(allocator, unified_doc, args);
    defer allocator.free(api_code);

    return try std.mem.concat(allocator, u8, &.{ header, models_code, "\n", api_code });
}

/// Result of generating code in multiple-files mode.
pub const GeneratedFiles = struct {
    models: []const u8,
    runtime: ?[]const u8 = null,
    client: ?[]const u8 = null,

    pub fn deinit(self: *GeneratedFiles, allocator: std.mem.Allocator) void {
        allocator.free(self.models);
        if (self.runtime) |r| allocator.free(r);
        if (self.client) |c| allocator.free(c);
    }
};

/// Generate separate Zig source files (models, runtime, client) from a unified document.
/// Only the models field is always present; runtime and client are null when
/// args.models_only is true.
pub fn generateCodeMultiple(allocator: std.mem.Allocator, io: std.Io, unified_doc: UnifiedDocument, args: CliArgs) !GeneratedFiles {
    const models_code = try generateModels(allocator, unified_doc);
    defer allocator.free(models_code);

    const header = try generated_header.renderNowFromBuildInfo(allocator, io);
    defer allocator.free(header);

    const models_with_header = try std.mem.concat(allocator, u8, &.{ header, models_code });
    errdefer allocator.free(models_with_header);

    if (args.models_only) {
        return .{ .models = models_with_header };
    }

    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();
    const runtime_code = try runtime_gen.generate();
    defer allocator.free(runtime_code);

    const runtime_with_header = try std.mem.concat(allocator, u8, &.{ header, runtime_code });
    errdefer allocator.free(runtime_with_header);

    var api_gen = UnifiedApiGenerator.init(allocator, args);
    api_gen.model_prefix = "models.";
    api_gen.emit_imports = true;
    defer api_gen.deinit();
    const api_code = try api_gen.generateClientOnly(unified_doc);
    defer allocator.free(api_code);

    const client_with_header = try std.mem.concat(allocator, u8, &.{ header, api_code });
    errdefer allocator.free(client_with_header);

    return .{
        .models = models_with_header,
        .runtime = runtime_with_header,
        .client = client_with_header,
    };
}

fn convertDocument(allocator: std.mem.Allocator, doc: anytype, comptime Converter: type) !UnifiedDocument {
    var converter = Converter.init(allocator);
    return try converter.convert(doc);
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
    return convertDocument(allocator, openapi_doc, OpenApiConverter);
}

/// Convert a version-specific OpenAPI v3.1 document to unified representation.
///
/// Parameters:
/// - allocator: Memory allocator to use for conversion
/// - openapi31_doc: Parsed OpenAPI v3.1 document
///
/// Returns:
/// - UnifiedDocument: Unified representation of the OpenAPI v3.1 document
pub fn convertOpenApi31ToUnified(allocator: std.mem.Allocator, openapi31_doc: OpenApi31Document) !UnifiedDocument {
    return convertDocument(allocator, openapi31_doc, OpenApi31Converter);
}

/// Convert a version-specific OpenAPI v3.2 document to unified representation.
///
/// Parameters:
/// - allocator: Memory allocator to use for conversion
/// - openapi32_doc: Parsed OpenAPI v3.2 document
///
/// Returns:
/// - UnifiedDocument: Unified representation of the OpenAPI v3.2 document
pub fn convertOpenApi32ToUnified(allocator: std.mem.Allocator, openapi32_doc: OpenApi32Document) !UnifiedDocument {
    return convertDocument(allocator, openapi32_doc, OpenApi32Converter);
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
    return convertDocument(allocator, swagger_doc, SwaggerConverter);
}

// Version information
pub const version_info = @import("build_info");

// Test utilities for library users
pub const test_utils = @import("tests/test_utils.zig");

test {
    // Import all tests to ensure they're run when testing the library
    std.testing.refAllDecls(@This());
    _ = @import("tests.zig");
}
