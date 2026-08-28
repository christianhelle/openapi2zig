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
const cli = @import("cli.zig");

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
pub fn generateRuntime(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();
    const runtime_code = try runtime_gen.generate();
    defer allocator.free(runtime_code);
    const checksum = generated_header.computeChecksum(runtime_code);
    const header = try generated_header.renderNowWithChecksum(allocator, io, checksum);
    defer allocator.free(header);
    return try std.mem.concat(allocator, u8, &.{ header, runtime_code });
}

pub fn generateCode(allocator: std.mem.Allocator, io: std.Io, unified_doc: UnifiedDocument, args: CliArgs) ![]const u8 {
    if (args.runtime_only) {
        return try generateRuntime(allocator, io);
    }
    const models_code = try generateModels(allocator, unified_doc);
    defer allocator.free(models_code);

    if (args.models_only) {
        const checksum = generated_header.computeChecksum(models_code);
        const header = try generated_header.renderNowWithChecksum(allocator, io, checksum);
        defer allocator.free(header);
        return try std.mem.concat(allocator, u8, &.{ header, models_code });
    }

    const api_code = try generateApi(allocator, unified_doc, args);
    defer allocator.free(api_code);

    const combined = try std.mem.concat(allocator, u8, &.{ models_code, "\n", api_code });
    defer allocator.free(combined);

    const checksum = generated_header.computeChecksum(combined);
    const header = try generated_header.renderNowWithChecksum(allocator, io, checksum);
    defer allocator.free(header);

    return try std.mem.concat(allocator, u8, &.{ header, combined });
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
/// args.models_only is true. `runtime` is also null when `args.runtime_module` is set
/// to reuse an existing runtime module instead of generating one.
pub fn generateCodeMultiple(allocator: std.mem.Allocator, io: std.Io, unified_doc: UnifiedDocument, args: CliArgs) !GeneratedFiles {
    if (args.runtime_only) {
        if (args.models_only) return error.InvalidArguments;
        if (args.multiple_clients != null) return error.InvalidArguments;
        if (args.runtime_module != null) return error.InvalidArguments;
        if (args.file_names.models != null or args.file_names.client != null) return error.InvalidArguments;
        const runtime_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.runtime) orelse cli.FileKind.runtime.defaultName(), "\\", "/");
        defer allocator.free(runtime_file);
        const r_alias = try cli.deriveAlias(allocator, runtime_file, "runtime");
        defer allocator.free(r_alias);
        const reserved = [_][]const u8{ "std", "Client", "_" };
        for (reserved) |r| if (std.mem.eql(u8, r_alias, r)) return error.InvalidArguments;
        var runtime_gen = RuntimeGenerator.init(allocator);
        defer runtime_gen.deinit();
        const runtime_code = try runtime_gen.generate();
        defer allocator.free(runtime_code);
        const runtime_checksum = generated_header.computeChecksum(runtime_code);
        const runtime_header = try generated_header.renderNowWithChecksum(allocator, io, runtime_checksum);
        defer allocator.free(runtime_header);
        const runtime_with_header = try std.mem.concat(allocator, u8, &.{ runtime_header, runtime_code });
        errdefer allocator.free(runtime_with_header);
        const empty_models = try allocator.dupe(u8, "");
        return .{ .models = empty_models, .runtime = runtime_with_header, .client = null };
    }
    const models_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.models) orelse cli.FileKind.models.defaultName(), "\\", "/");
    defer allocator.free(models_file);
    const runtime_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.runtime) orelse cli.FileKind.runtime.defaultName(), "\\", "/");
    defer allocator.free(runtime_file);
    const client_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.client) orelse cli.FileKind.client.defaultName(), "\\", "/");
    defer allocator.free(client_file);

    const models_code = try generateModels(allocator, unified_doc);
    defer allocator.free(models_code);

    const models_checksum = generated_header.computeChecksum(models_code);
    const models_header = try generated_header.renderNowWithChecksum(allocator, io, models_checksum);
    defer allocator.free(models_header);

    const models_with_header = try std.mem.concat(allocator, u8, &.{ models_header, models_code });
    errdefer allocator.free(models_with_header);

    if (args.models_only) {
        return .{ .models = models_with_header };
    }

    // Validate file names and import aliases the same way `cli.parse` does, so
    // the library cannot emit invalid Zig (e.g. duplicate `const <alias>` lines
    // or `const std = @import("std.zig")` colliding with `const std = @import("std")`).
    if (args.runtime_module) |mod| {
        cli.validateImportPath(mod) catch return error.InvalidArguments;
        if (cli.fileNamesCollide(models_file, client_file)) return error.InvalidArguments;
        const resolved_runtime = try cli.resolveRuntimeModulePath(allocator, client_file, mod);
        defer allocator.free(resolved_runtime);
        if (cli.fileNamesCollide(resolved_runtime, models_file)) return error.InvalidArguments;
        if (cli.fileNamesCollide(resolved_runtime, client_file)) return error.InvalidArguments;
        const m_alias = try cli.deriveAlias(allocator, models_file, "models");
        defer allocator.free(m_alias);
        const r_alias = try cli.deriveAlias(allocator, cli.importBasename(mod), "runtime");
        defer allocator.free(r_alias);
        const c_alias = try cli.deriveAlias(allocator, client_file, "client");
        defer allocator.free(c_alias);
        if (std.mem.eql(u8, m_alias, r_alias) or std.mem.eql(u8, m_alias, c_alias) or std.mem.eql(u8, r_alias, c_alias)) {
            return error.InvalidArguments;
        }
        const reserved = [_][]const u8{ "std", "Client", "_" };
        for ([_][]const u8{ m_alias, r_alias, c_alias }) |a| {
            for (reserved) |r| if (std.mem.eql(u8, a, r)) return error.InvalidArguments;
        }
    } else {
        if (cli.fileNamesCollide(models_file, runtime_file) or cli.fileNamesCollide(models_file, client_file) or cli.fileNamesCollide(runtime_file, client_file)) {
            return error.InvalidArguments;
        }
        const m_alias = try cli.deriveAlias(allocator, models_file, "models");
        defer allocator.free(m_alias);
        const r_alias = try cli.deriveAlias(allocator, runtime_file, "runtime");
        defer allocator.free(r_alias);
        const c_alias = try cli.deriveAlias(allocator, client_file, "client");
        defer allocator.free(c_alias);
        if (std.mem.eql(u8, m_alias, r_alias) or std.mem.eql(u8, m_alias, c_alias) or std.mem.eql(u8, r_alias, c_alias)) {
            return error.InvalidArguments;
        }
        const reserved = [_][]const u8{ "std", "Client", "_" };
        for ([_][]const u8{ m_alias, r_alias, c_alias }) |a| {
            for (reserved) |r| if (std.mem.eql(u8, a, r)) return error.InvalidArguments;
        }
    }

    var runtime_with_header: ?[]const u8 = null;
    errdefer if (runtime_with_header) |r| allocator.free(r);

    var runtime_import_owned: ?[]const u8 = null;
    defer if (runtime_import_owned) |v| allocator.free(v);
    var runtime_alias_owned: ?[]const u8 = null;
    defer if (runtime_alias_owned) |v| allocator.free(v);

    if (args.runtime_module) |mod| {
        const normalized = try std.mem.replaceOwned(u8, allocator, mod, "\\", "/");
        defer allocator.free(normalized);
        runtime_alias_owned = try cli.deriveAlias(allocator, cli.importBasename(normalized), "runtime");
        runtime_import_owned = try allocator.dupe(u8, normalized);
    } else {
        var runtime_gen = RuntimeGenerator.init(allocator);
        defer runtime_gen.deinit();
        const runtime_code = try runtime_gen.generate();
        defer allocator.free(runtime_code);

        const runtime_checksum = generated_header.computeChecksum(runtime_code);
        const runtime_header = try generated_header.renderNowWithChecksum(allocator, io, runtime_checksum);
        defer allocator.free(runtime_header);

        runtime_with_header = try std.mem.concat(allocator, u8, &.{ runtime_header, runtime_code });

        runtime_alias_owned = try cli.deriveAlias(allocator, runtime_file, "runtime");
        const computed_import = if (std.fs.path.dirname(client_file)) |client_dir| blk: {
            const raw = try std.fs.path.relative(allocator, ".", null, client_dir, runtime_file);
            defer allocator.free(raw);
            break :blk try std.mem.replaceOwned(u8, allocator, raw, "\\", "/");
        } else try allocator.dupe(u8, runtime_file);
        runtime_import_owned = computed_import;
    }

    const models_alias = try cli.deriveAlias(allocator, models_file, "models");
    defer allocator.free(models_alias);
    const models_prefix = try std.mem.concat(allocator, u8, &.{ models_alias, "." });
    defer allocator.free(models_prefix);
    const models_import_path = if (std.fs.path.dirname(client_file)) |client_dir| blk: {
        const raw = try std.fs.path.relative(allocator, ".", null, client_dir, models_file);
        defer allocator.free(raw);
        break :blk try std.mem.replaceOwned(u8, allocator, raw, "\\", "/");
    } else models_file;
    defer if (std.fs.path.dirname(client_file) != null) allocator.free(models_import_path);

    var api_gen = UnifiedApiGenerator.init(allocator, args);
    defer api_gen.deinit();
    api_gen.model_prefix = models_prefix;
    api_gen.emit_imports = true;
    api_gen.models_import = models_import_path;
    api_gen.models_import_alias = models_alias;
    api_gen.runtime_import = runtime_import_owned.?;
    api_gen.runtime_import_alias = runtime_alias_owned.?;

    const api_code = try api_gen.generateClientOnly(unified_doc);
    defer allocator.free(api_code);

    const client_checksum = generated_header.computeChecksum(api_code);
    const client_header = try generated_header.renderNowWithChecksum(allocator, io, client_checksum);
    defer allocator.free(client_header);

    const client_with_header = try std.mem.concat(allocator, u8, &.{ client_header, api_code });
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

test "generateCodeMultiple with windows-style runtime_module normalizes separators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var result = try generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .runtime_module = "..\\shared\\my_runtime.zig",
    });
    defer result.deinit(allocator);

    try std.testing.expect(result.runtime == null);
    try std.testing.expect(result.client != null);
    try std.testing.expect(std.mem.indexOf(u8, result.client.?, "@import(\"../shared/my_runtime.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.client.?, "const my_runtime = @import(\"../shared/my_runtime.zig\");") != null);
}

test "generateCodeMultiple honors custom file names and nested client paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "operationId": "getPet",
        \\        "responses": {
        \\          "200": {
        \\            "description": "ok",
        \\            "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } } }
        \\          }
        \\        }
        \\      }
        \\    }
        \\  },
        \\  "components": {
        \\    "schemas": {
        \\      "Pet": {
        \\        "type": "object",
        \\        "properties": { "name": { "type": "string" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var result = try generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .file_names = .{ .models = "gen\\models.zig", .runtime = "rt\\runtime.zig", .client = "sub\\client.zig" },
    });
    defer result.deinit(allocator);

    try std.testing.expect(result.runtime != null);
    try std.testing.expect(result.client != null);
    const client = result.client.?;

    try std.testing.expect(std.mem.indexOf(u8, client, "const gen_models = @import(\"../gen/models.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const rt_runtime = @import(\"../rt/runtime.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "gen_models.Pet") != null);

    // No backslash-separated imports should leak into generated code.
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"gen\\models.zig\")") == null);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"rt\\runtime.zig\")") == null);
}

test "generateCodeMultiple with runtime_module honors custom models name and nested client" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var result = try generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .file_names = .{ .models = "contracts.zig", .client = "sub\\client.zig" },
        .runtime_module = "..\\shared\\my_runtime.zig",
    });
    defer result.deinit(allocator);

    try std.testing.expect(result.runtime == null);
    try std.testing.expect(result.client != null);
    const client = result.client.?;

    try std.testing.expect(std.mem.indexOf(u8, client, "const contracts = @import(\"../contracts.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const my_runtime = @import(\"../shared/my_runtime.zig\");") != null);
}

test "generateCodeMultiple rejects reserved alias std" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .file_names = .{ .models = "std.zig" },
    }));
}

test "generateCodeMultiple rejects duplicate alias derived from file names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .file_names = .{ .models = "my-models.zig", .runtime = "my_models.zig" },
    }));
}

test "generateCodeMultiple rejects reserved alias via runtime_module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .runtime_module = "../std.zig",
    }));
}

test "generateCodeMultiple rejects duplicate alias between models and runtime_module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .file_names = .{ .models = "runtime.zig" },
        .runtime_module = "../runtime.zig",
    }));
}

test "generateCodeMultiple rejects duplicate file name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .file_names = .{ .models = "foo.zig", .runtime = "foo.zig" },
    }));
}

test "generateCodeMultiple rejects runtime_module that resolves to models file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .file_names = .{ .client = "sub/client.zig" },
        .runtime_module = "../models.zig",
    }));
}

test "generateCodeMultiple allows reserved alias when models_only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    var result = try generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .models_only = true,
        .file_names = .{ .models = "std.zig" },
    });
    defer result.deinit(allocator);
    try std.testing.expect(result.runtime == null);
    try std.testing.expect(result.client == null);
}

test "generateCodeMultiple rejects absolute runtime_module path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;
    var unified = try parseToUnified(allocator, json);
    defer unified.deinit(allocator);
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .runtime_module = "/absolute/runtime.zig",
    }));
    try std.testing.expectError(error.InvalidArguments, generateCodeMultiple(allocator, io, unified, .{
        .input_path = "fixture.json",
        .runtime_module = "C:runtime.zig",
    }));
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
