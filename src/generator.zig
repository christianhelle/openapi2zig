const std = @import("std");
const cli = @import("cli.zig");
const detector = @import("detector.zig");
const models = @import("models.zig");
const input_loader = @import("input_loader.zig");
const yaml_loader = @import("yaml_loader.zig");
const document_filter = @import("document_filter.zig");
const generated_header = @import("generators/generated_header.zig");
const OpenApiConverter = @import("generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("generators/converters/openapi32_converter.zig").OpenApi32Converter;
const SwaggerConverter = @import("generators/converters/swagger_converter.zig").SwaggerConverter;
const UnifiedModelGenerator = @import("generators/unified/model_generator.zig").UnifiedModelGenerator;
const UnifiedApiGenerator = @import("generators/unified/api_generator.zig").UnifiedApiGenerator;
const RuntimeGenerator = @import("generators/unified/runtime_generator.zig").RuntimeGenerator;

const openapi2zig = @import("lib.zig");

const default_output_file: []const u8 = "generated.zig";
const default_output_dir: []const u8 = "generated";
const default_runtime_only_file: []const u8 = "runtime.zig";

const Extension = enum {
    YAML,
    JSON,
};

pub const GeneratorErrors = error{
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
    if (args.runtime_only) {
        // The input spec is irrelevant for a runtime-only build: never
        // validate its extension or read it.
        return generateRuntimeOnly(allocator, io, std.Io.Dir.cwd(), args);
    }

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

pub fn generateCodeFromJsonContents(allocator: std.mem.Allocator, io: std.Io, json_contents: []const u8, args: cli.CliArgs) !void {
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

pub fn generateCodeFromUnifiedDocument(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, unified_doc: @import("models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
    var filtered_doc = unified_doc;
    try document_filter.filterByTags(allocator, &filtered_doc, args.tags);

    if (args.multiple_files) {
        try generateMultipleFiles(allocator, io, cwd, filtered_doc, args);
        return;
    }

    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const generated_models = try model_generator.generate(filtered_doc);
    defer allocator.free(generated_models);

    const generated_code = if (args.models_only)
        generated_models
    else blk: {
        var api_generator = UnifiedApiGenerator.init(allocator, args);
        defer api_generator.deinit();
        const generated_api = try api_generator.generate(filtered_doc);
        defer allocator.free(generated_api);

        const joined_code = try std.mem.join(allocator, "\n", &.{ generated_models, generated_api });
        break :blk joined_code;
    };
    defer if (!args.models_only) allocator.free(generated_code);

    const checksum = generated_header.computeChecksum(generated_code);
    const header = try generated_header.renderNowWithChecksum(allocator, io, checksum);
    defer allocator.free(header);
    const output_code = try std.mem.concat(allocator, u8, &.{ header, generated_code });
    defer allocator.free(output_code);

    const output_path = args.output_path orelse default_output_file;
    if (std.fs.path.dirname(output_path)) |dir_path| {
        try cwd.createDirPath(io, dir_path);
    }

    if (!args.force) {
        const full_path = try std.fs.path.join(allocator, &.{ ".", output_path });
        defer allocator.free(full_path);
        if (cwd.readFileAlloc(io, full_path, allocator, .limited(10 * 1024 * 1024))) |existing| {
            defer allocator.free(existing);
            if (!generated_header.hasChanged(existing, generated_code)) {
                std.log.info("Skipping '{s}' (unchanged)", .{output_path});
                return;
            }
        } else |_| {}
    } else {
        std.log.info("Force flag is set; overwriting '{s}'", .{output_path});
    }

    const output_file = try cwd.createFile(io, output_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, output_code);
    std.log.info("Code generated successfully and written to '{s}'.", .{output_path});
}

/// Generate only the runtime module. The input spec plays no role here, so
/// callers must not require or read one when `args.runtime_only` is set.
pub fn generateRuntimeOnly(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, args: cli.CliArgs) !void {
    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();
    const generated_runtime = try runtime_gen.generate();
    defer allocator.free(generated_runtime);

    if (args.multiple_files) {
        const dir_path = args.output_path orelse default_output_dir;
        try cwd.createDirPath(io, dir_path);
        const runtime_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.runtime) orelse cli.FileKind.runtime.defaultName(), "\\", "/");
        defer allocator.free(runtime_file);
        try writeFile(allocator, io, cwd, dir_path, runtime_file, generated_runtime, args.force);
        return;
    }

    const output_path = args.output_path orelse default_runtime_only_file;
    // Split into dir + name so writeFile never prefixes an absolute path with
    // "./", which the OS rejects as a malformed path.
    const output_dir = std.fs.path.dirname(output_path) orelse ".";
    try writeFile(allocator, io, cwd, output_dir, std.fs.path.basename(output_path), generated_runtime, args.force);
}

pub fn writeFile(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, dir_path: []const u8, file_name: []const u8, raw_code: []const u8, force: bool) !void {
    const full_path = try std.fs.path.join(allocator, &.{ dir_path, file_name });
    defer allocator.free(full_path);

    if (!force) {
        if (cwd.readFileAlloc(io, full_path, allocator, .limited(10 * 1024 * 1024))) |existing| {
            defer allocator.free(existing);
            if (!generated_header.hasChanged(existing, raw_code)) {
                std.log.info("Skipping '{s}' (unchanged)", .{full_path});
                return;
            }
        } else |_| {}
    } else {
        std.log.info("Force flag is set; overwriting '{s}'", .{full_path});
    }

    const checksum = generated_header.computeChecksum(raw_code);
    const header = try generated_header.renderNowWithChecksum(allocator, io, checksum);
    defer allocator.free(header);

    const content = try std.mem.concat(allocator, u8, &.{ header, raw_code });
    defer allocator.free(content);

    if (std.fs.path.dirname(full_path)) |parent| {
        try cwd.createDirPath(io, parent);
    }
    const output_file = try cwd.createFile(io, full_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, content);
    std.log.info("Wrote '{s}'", .{full_path});
}

pub fn generateMultipleFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, unified_doc: @import("models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
    const dir_path = args.output_path orelse default_output_dir;
    try cwd.createDirPath(io, dir_path);

    const models_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.models) orelse cli.FileKind.models.defaultName(), "\\", "/");
    defer allocator.free(models_file);
    const runtime_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.runtime) orelse cli.FileKind.runtime.defaultName(), "\\", "/");
    defer allocator.free(runtime_file);
    const client_file = try std.mem.replaceOwned(u8, allocator, args.file_names.get(.client) orelse cli.FileKind.client.defaultName(), "\\", "/");
    defer allocator.free(client_file);

    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const generated_models = try model_generator.generate(unified_doc);
    defer allocator.free(generated_models);

    try writeFile(allocator, io, cwd, dir_path, models_file, generated_models, args.force);

    if (args.models_only) return;

    var runtime_alias_owned: ?[]const u8 = null;
    defer if (runtime_alias_owned) |v| allocator.free(v);
    var runtime_import_owned: ?[]const u8 = null;
    defer if (runtime_import_owned) |v| allocator.free(v);

    var runtime_alias: []const u8 = undefined;
    var runtime_import_path: []const u8 = undefined;

    if (args.runtime_module) |mod| {
        std.log.info("Reusing runtime module '{s}' (skipping generation of '{s}')", .{ mod, runtime_file });
        runtime_import_owned = try std.mem.replaceOwned(u8, allocator, mod, "\\", "/");
        runtime_import_path = runtime_import_owned.?;
        runtime_alias_owned = try cli.deriveAlias(allocator, cli.importBasename(runtime_import_path), "runtime");
        runtime_alias = runtime_alias_owned.?;
        // Best-effort existence check relative to the output directory / client location.
        const candidate_path = if (std.fs.path.dirname(client_file)) |client_dir|
            try std.fs.path.join(allocator, &.{ dir_path, client_dir, runtime_import_path })
        else
            try std.fs.path.join(allocator, &.{ dir_path, runtime_import_path });
        defer allocator.free(candidate_path);
        cwd.access(io, candidate_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.log.info("Runtime module '{s}' not found at '{s}' (import will be dangling until file exists)", .{ mod, candidate_path });
            } else {
                std.log.warn("Failed to access runtime module '{s}' at '{s}': {}", .{ mod, candidate_path, err });
            }
        };
    } else {
        var runtime_gen = RuntimeGenerator.init(allocator);
        defer runtime_gen.deinit();
        const generated_runtime = try runtime_gen.generate();
        defer allocator.free(generated_runtime);

        try writeFile(allocator, io, cwd, dir_path, runtime_file, generated_runtime, args.force);

        runtime_alias_owned = try cli.deriveAlias(allocator, runtime_file, "runtime");
        runtime_alias = runtime_alias_owned.?;
        const computed_import = if (std.fs.path.dirname(client_file)) |client_dir| blk: {
            const raw = try std.fs.path.relative(allocator, ".", null, client_dir, runtime_file);
            defer allocator.free(raw);
            break :blk try std.mem.replaceOwned(u8, allocator, raw, "\\", "/");
        } else try allocator.dupe(u8, runtime_file);
        runtime_import_owned = computed_import;
        runtime_import_path = runtime_import_owned.?;
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

    var api_generator = UnifiedApiGenerator.init(allocator, args);
    api_generator.model_prefix = models_prefix;
    api_generator.emit_imports = true;
    api_generator.models_import = models_import_path;
    api_generator.models_import_alias = models_alias;
    api_generator.runtime_import = runtime_import_path;
    api_generator.runtime_import_alias = runtime_alias;
    defer api_generator.deinit();
    const generated_api = try api_generator.generateClientOnly(unified_doc);
    defer allocator.free(generated_api);

    try writeFile(allocator, io, cwd, dir_path, client_file, generated_api, args.force);
}

pub fn generateCodeFromDocument(allocator: std.mem.Allocator, io: std.Io, doc: anytype, args: cli.CliArgs, comptime Converter: type) !void {
    var converter = Converter.init(allocator);
    var unified_doc = try converter.convert(doc);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, std.Io.Dir.cwd(), unified_doc, args);
}

test {
    _ = @import("generator/tests.zig");
}
