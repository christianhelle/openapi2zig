const std = @import("std");
const models = @import("models.zig");
const cli = @import("cli.zig");
const detector = @import("detector.zig");
const ApiCodeGeneratorV2 = @import("generators/v2.0/apigenerator.zig").ApiCodeGenerator;
const ModelCodeGeneratorV2 = @import("generators/v2.0/modelgenerator.zig").ModelCodeGenerator;
const ApiCodeGeneratorV3 = @import("generators/v3.0/apigenerator.zig").ApiCodeGenerator;
const ModelCodeGeneratorV3 = @import("generators/v3.0/modelgenerator.zig").ModelCodeGenerator;

const default_output_file: []const u8 = "generated.zig";

const Extension = enum {
    YAML,
    JSON,
};

const GeneratorErrors = error{UnsupportedExtension};

pub fn validateExtension(input_file_path: []const u8) !Extension {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const lowercase = std.ascii.lowerString(&buf, input_file_path);
    if (std.mem.endsWith(u8, lowercase, ".yaml") or
        std.mem.endsWith(u8, lowercase, ".yml"))
    {
        return Extension.YAML;
    }
    if (std.mem.endsWith(u8, lowercase, ".json")) {
        return Extension.JSON;
    }

    std.debug.print("Invalid file extension. Only json and yaml are supported: \n", .{});
    return GeneratorErrors.UnsupportedExtension;
}

pub fn generateCode(allocator: std.mem.Allocator, args: cli.CliArgs) !void {
    const extension = try validateExtension(args.input_path);

    const openapi_file = try std.fs.cwd().openFile(args.input_path, .{});
    defer openapi_file.close();

    try openapi_file.seekBy(0);
    const file_contents = try openapi_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    switch (extension) {
        .YAML => {
            std.debug.print("YAML support is not yet implemented\n", .{});
            return GeneratorErrors.UnsupportedExtension;
        },
        .JSON => {
            const version = detector.getOpenApiVersion(allocator, file_contents) catch |err| {
                std.debug.print("Failed to parse OpenAPI version: {any}\n", .{err});
                return err;
            };
            std.debug.print("Detected OpenAPI version: {s}\n", .{detector.getOpenApiVersionString(version)});
            switch (version) {
                .v2_0 => {
                    var swagger = try models.SwaggerDocument.parseFromJson(allocator, file_contents);
                    defer swagger.deinit(allocator);
                    std.debug.print("Successfully parsed Swagger v2.0 document\n", .{});
                    try generateCodeFromSwaggerDocument(allocator, swagger, args);
                },
                .v3_0 => {
                    var openapi = try models.OpenApiDocument.parseFromJson(allocator, file_contents);
                    defer openapi.deinit(allocator);
                    std.debug.print("Successfully parsed OpenAPI v3.0 document\n", .{});
                    try generateCodeFromOpenApiDocument(allocator, openapi, args);
                },
                else => {
                    std.debug.print("Unsupported OpenAPI version: {s}\n", .{detector.getOpenApiVersionString(version)});
                    return GeneratorErrors.UnsupportedExtension;
                },
            }
        },
    }
}

// Swagger v2.0 code generation
fn generateCodeFromSwaggerDocument(allocator: std.mem.Allocator, swagger: models.SwaggerDocument, args: cli.CliArgs) !void {
    var model_generator = ModelCodeGeneratorV2.init(allocator);
    defer model_generator.deinit();

    const generated_models = try model_generator.generate(swagger);
    defer allocator.free(generated_models);

    var api_generator = ApiCodeGeneratorV2.init(allocator, args);
    defer api_generator.deinit();

    const generated_api = try api_generator.generate(swagger);
    defer allocator.free(generated_api);

    const generated_code = try std.mem.join(allocator, "\n", &.{ generated_models, generated_api });
    defer allocator.free(generated_code);

    if (args.output_path) |output_path| {
        if (std.fs.path.dirname(output_path)) |dir_path| {
            try std.fs.cwd().makePath(dir_path);
        }
        const output_file = try std.fs.cwd().createFile(output_path, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Code generated successfully and written to '{s}'.\n", .{output_path});
    } else {
        const output_file = try std.fs.cwd().createFile(default_output_file, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Code generated successfully and written to '{s}'.\n", .{default_output_file});
    }
}

// OpenAPI v3.0 code generation
fn generateCodeFromOpenApiDocument(allocator: std.mem.Allocator, openapi: models.OpenApiDocument, args: cli.CliArgs) !void {
    var model_generator = ModelCodeGeneratorV3.init(allocator);
    defer model_generator.deinit();

    const generated_models = try model_generator.generate(openapi);
    defer allocator.free(generated_models);

    var api_generator = ApiCodeGeneratorV3.init(allocator, args);
    defer api_generator.deinit();

    const generated_api = try api_generator.generate(openapi);
    defer allocator.free(generated_api);

    const generated_code = try std.mem.join(allocator, "\n", &.{ generated_models, generated_api });
    defer allocator.free(generated_code);

    if (args.output_path) |output_path| {
        if (std.fs.path.dirname(output_path)) |dir_path| {
            try std.fs.cwd().makePath(dir_path);
        }
        const output_file = try std.fs.cwd().createFile(output_path, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Models generated successfully and written to '{s}'.\n", .{output_path});
    } else {
        const output_file = try std.fs.cwd().createFile(default_output_file, .{ .read = true });
        defer output_file.close();
        try output_file.writeAll(generated_code);
        std.debug.print("Models generated successfully and written to 'generated_models.zig'.\n", .{});
    }
}
