const std = @import("std");
const cli = @import("cli.zig");
const detector = @import("detector.zig");
const models = @import("models.zig");
const input_loader = @import("input_loader.zig");
const yaml_loader = @import("yaml_loader.zig");
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

const GeneratorErrors = error{
    UnsupportedExtension,
    UnsupportedOpenAPIVersion,
};

pub fn validateExtension(input_file_path: []const u8) !Extension {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const lowercase = std.ascii.lowerString(&buf, input_file_path);

    if (std.mem.endsWith(u8, lowercase, ".yaml") or std.mem.endsWith(u8, lowercase, ".yml")) {
        return Extension.YAML;
    }

    if (std.mem.endsWith(u8, lowercase, ".json")) {
        return Extension.JSON;
    }

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

    var normalized_yaml_json: ?[]const u8 = null;
    defer if (normalized_yaml_json) |json_contents| allocator.free(json_contents);

    const json_contents = switch (extension) {
        .YAML => blk: {
            normalized_yaml_json = yaml_loader.yamlToJson(allocator, file_contents) catch |err| {
                return err;
            };
            break :blk normalized_yaml_json.?;
        },
        .JSON => file_contents,
    };

    try generateCodeFromJsonContents(allocator, io, json_contents, args);
}

fn generateCodeFromJsonContents(allocator: std.mem.Allocator, io: std.Io, json_contents: []const u8, args: cli.CliArgs) !void {
    const version = detector.getOpenApiVersion(allocator, json_contents) catch |err| {
        return err;
    };

    std.log.info("Detected OpenAPI version: {s}", .{detector.getOpenApiVersionString(version)});

    switch (version) {
        .v2_0 => {
            var swagger = try models.SwaggerDocument.parseFromJson(allocator, json_contents);
            defer swagger.deinit(allocator);
            std.log.info("Successfully parsed Swagger v2.0 document", .{});
            try generateCodeFromDocument(allocator, io, swagger, args, SwaggerConverter);
        },
        .v3_0 => {
            var openapi = try models.OpenApiDocument.parseFromJson(allocator, json_contents);
            defer openapi.deinit(allocator);
            std.log.info("Successfully parsed OpenAPI v3.0 document", .{});
            try generateCodeFromDocument(allocator, io, openapi, args, OpenApiConverter);
        },
        .v3_1 => {
            var openapi31 = try models.OpenApi31Document.parseFromJson(allocator, json_contents);
            defer openapi31.deinit(allocator);
            std.log.info("Successfully parsed OpenAPI v3.1 document", .{});
            try generateCodeFromDocument(allocator, io, openapi31, args, OpenApi31Converter);
        },
        .v3_2 => {
            var openapi32 = try models.OpenApi32Document.parseFromJson(allocator, json_contents);
            defer openapi32.deinit(allocator);
            std.log.info("Successfully parsed OpenAPI v3.2 document", .{});
            try generateCodeFromDocument(allocator, io, openapi32, args, OpenApi32Converter);
        },
        else => {
            return GeneratorErrors.UnsupportedOpenAPIVersion;
        },
    }
}

fn generateCodeFromUnifiedDocument(allocator: std.mem.Allocator, io: std.Io, unified_doc: @import("models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const generated_models = try model_generator.generate(unified_doc);
    defer allocator.free(generated_models);

    const generated_code = if (args.models_only)
        generated_models
    else blk: {
        var api_generator = UnifiedApiGenerator.init(allocator, args);
        defer api_generator.deinit();
        const generated_api = try api_generator.generate(unified_doc);
        defer allocator.free(generated_api);

        const joined_code = try std.mem.join(allocator, "\n", &.{ generated_models, generated_api });
        break :blk joined_code;
    };
    defer if (!args.models_only) allocator.free(generated_code);

    const output_path = args.output_path orelse default_output_file;
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(output_path)) |dir_path| {
        try cwd.createDirPath(io, dir_path);
    }
    const output_file = try cwd.createFile(io, output_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, generated_code);
    std.log.info("Code generated successfully and written to '{s}'.", .{output_path});
}

fn generateCodeFromDocument(allocator: std.mem.Allocator, io: std.Io, doc: anytype, args: cli.CliArgs, comptime Converter: type) !void {
    var converter = Converter.init(allocator);
    var unified_doc = try converter.convert(doc);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, unified_doc, args);
}

test "unsupported OpenAPI versions return a distinct generator error" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json_contents =
        \\{
        \\  "openapi": "9.9.9",
        \\  "info": {
        \\    "title": "Unsupported",
        \\    "version": "1.0.0"
        \\  },
        \\  "paths": {}
        \\}
    ;

    try std.testing.expectError(
        GeneratorErrors.UnsupportedOpenAPIVersion,
        generateCodeFromJsonContents(allocator, std.testing.io, json_contents, .{
            .input_path = "unsupported.json",
        }),
    );
}
