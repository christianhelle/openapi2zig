const std = @import("std");
const cli = @import("cli.zig");
const detector = @import("detector.zig");
const models = @import("models.zig");
const input_loader = @import("input_loader.zig");
const OpenApiConverter = @import("generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("generators/converters/openapi32_converter.zig").OpenApi32Converter;
const SwaggerConverter = @import("generators/converters/swagger_converter.zig").SwaggerConverter;
const UnifiedModelGenerator = @import("generators/unified/model_generator.zig").UnifiedModelGenerator;
const UnifiedApiGenerator = @import("generators/unified/api_generator.zig").UnifiedApiGenerator;

const default_output_file: []const u8 = "generated.zig";

const Extension = enum {
    YAML,
    JSON,
};

const GeneratorErrors = error{UnsupportedExtension};

pub fn validateExtension(input_file_path: []const u8) !Extension {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const lowercase = std.ascii.lowerString(&buf, input_file_path);

    if (std.mem.endsWith(u8, lowercase, ".yaml") or std.mem.endsWith(u8, lowercase, ".yml")) {
        return Extension.YAML;
    }

    if (std.mem.endsWith(u8, lowercase, ".json")) {
        return Extension.JSON;
    }

    std.debug.print("Invalid file extension. Only json and yaml are supported: \n", .{});
    return GeneratorErrors.UnsupportedExtension;
}

pub fn generateCode(allocator: std.mem.Allocator, io: std.Io, args: cli.CliArgs) !void {
    const extension = try validateExtension(args.input_path);

    // Determine input source: URL or file path
    const source = if (input_loader.isUrl(args.input_path))
        input_loader.InputSource{ .url = args.input_path }
    else
        input_loader.InputSource{ .file_path = args.input_path };

    const file_contents = try input_loader.loadInput(allocator, io, source);
    defer allocator.free(file_contents);

    switch (extension) {
        .YAML => {
            std.debug.print("YAML support is not yet implemented\n", .{});
            return GeneratorErrors.UnsupportedExtension;
        },
        .JSON => {
            const version = detector.getOpenApiVersion(allocator, file_contents) catch |err| {
                std.debug.print("Failed to parse OpenAPI version: {}\n", .{err});
                return err;
            };

            std.debug.print("Detected OpenAPI version: {s}\n", .{detector.getOpenApiVersionString(version)});

            switch (version) {
                .v2_0 => {
                    var swagger = try models.SwaggerDocument.parseFromJson(allocator, file_contents);
                    defer swagger.deinit(allocator);
                    std.debug.print("Successfully parsed Swagger v2.0 document\n", .{});
                    try generateCodeFromSwaggerDocument(allocator, io, swagger, args);
                },
                .v3_0 => {
                    var openapi = try models.OpenApiDocument.parseFromJson(allocator, file_contents);
                    defer openapi.deinit(allocator);
                    std.debug.print("Successfully parsed OpenAPI v3.0 document\n", .{});
                    try generateCodeFromOpenApiDocument(allocator, io, openapi, args);
                },
                .v3_1 => {
                    var openapi31 = try models.OpenApi31Document.parseFromJson(allocator, file_contents);
                    defer openapi31.deinit(allocator);
                    std.debug.print("Successfully parsed OpenAPI v3.1 document\n", .{});
                    try generateCodeFromOpenApi31Document(allocator, io, openapi31, args);
                },
                .v3_2 => {
                    var openapi32 = try models.OpenApi32Document.parseFromJson(allocator, file_contents);
                    defer openapi32.deinit(allocator);
                    std.debug.print("Successfully parsed OpenAPI v3.2 document\n", .{});
                    try generateCodeFromOpenApi32Document(allocator, io, openapi32, args);
                },
                else => {
                    std.debug.print("Unsupported OpenAPI version: {s}\n", .{detector.getOpenApiVersionString(version)});
                    return GeneratorErrors.UnsupportedExtension;
                },
            }
        },
    }
}

fn generateCodeFromUnifiedDocument(allocator: std.mem.Allocator, io: std.Io, unified_doc: @import("models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const generated_models = try model_generator.generate(unified_doc);
    defer allocator.free(generated_models);

    var api_generator = UnifiedApiGenerator.init(allocator, args);
    defer api_generator.deinit();
    const generated_api = try api_generator.generate(unified_doc);
    defer allocator.free(generated_api);

    const generated_code = try std.mem.join(allocator, "\n", &.{ generated_models, generated_api });
    defer allocator.free(generated_code);

    const output_path = args.output_path orelse default_output_file;
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(output_path)) |dir_path| {
        try cwd.createDirPath(io, dir_path);
    }
    const output_file = try cwd.createFile(io, output_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, generated_code);
    std.debug.print("Code generated successfully and written to '{s}'.\n", .{output_path});
}

fn generateCodeFromSwaggerDocument(allocator: std.mem.Allocator, io: std.Io, swagger: models.SwaggerDocument, args: cli.CliArgs) !void {
    var swagger_converter = SwaggerConverter.init(allocator);
    var unified_doc = try swagger_converter.convert(swagger);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, unified_doc, args);
}

fn generateCodeFromOpenApiDocument(allocator: std.mem.Allocator, io: std.Io, openapi: models.OpenApiDocument, args: cli.CliArgs) !void {
    var openapi_converter = OpenApiConverter.init(allocator);
    var unified_doc = try openapi_converter.convert(openapi);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, unified_doc, args);
}

fn generateCodeFromOpenApi31Document(allocator: std.mem.Allocator, io: std.Io, openapi: models.OpenApi31Document, args: cli.CliArgs) !void {
    var openapi31_converter = OpenApi31Converter.init(allocator);
    var unified_doc = try openapi31_converter.convert(openapi);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, unified_doc, args);
}

fn generateCodeFromOpenApi32Document(allocator: std.mem.Allocator, io: std.Io, openapi: models.OpenApi32Document, args: cli.CliArgs) !void {
    var openapi32_converter = OpenApi32Converter.init(allocator);
    var unified_doc = try openapi32_converter.convert(openapi);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, unified_doc, args);
}
