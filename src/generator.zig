const std = @import("std");
const cli = @import("cli.zig");
const detector = @import("detector.zig");
const models = @import("models.zig");
const input_loader = @import("input_loader.zig");
const yaml_loader = @import("yaml_loader.zig");
const generated_header = @import("generators/generated_header.zig");
const OpenApiConverter = @import("generators/converters/openapi_converter.zig").OpenApiConverter;
const OpenApi31Converter = @import("generators/converters/openapi31_converter.zig").OpenApi31Converter;
const OpenApi32Converter = @import("generators/converters/openapi32_converter.zig").OpenApi32Converter;
const SwaggerConverter = @import("generators/converters/swagger_converter.zig").SwaggerConverter;
const UnifiedModelGenerator = @import("generators/unified/model_generator.zig").UnifiedModelGenerator;
const UnifiedApiGenerator = @import("generators/unified/api_generator.zig").UnifiedApiGenerator;
const RuntimeGenerator = @import("generators/unified/runtime_generator.zig").RuntimeGenerator;
const ident = @import("generators/unified/ident_utils.zig");

const openapi2zig = @import("lib.zig");

const default_output_file: []const u8 = "generated.zig";
const default_output_dir: []const u8 = "generated";

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
    const cwd = std.Io.Dir.cwd();

    if (args.multiple_files) {
        try generateMultipleFiles(allocator, io, cwd, unified_doc, args);
        return;
    }

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

    const header = try generated_header.renderNowFromBuildInfo(allocator, io);
    defer allocator.free(header);
    const output_code = try std.mem.concat(allocator, u8, &.{ header, generated_code });
    defer allocator.free(output_code);

    const output_path = args.output_path orelse default_output_file;
    if (std.fs.path.dirname(output_path)) |dir_path| {
        try cwd.createDirPath(io, dir_path);
    }
    const output_file = try cwd.createFile(io, output_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, output_code);
    std.log.info("Code generated successfully and written to '{s}'.", .{output_path});
}

fn writeFile(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, dir_path: []const u8, file_name: []const u8, content: []const u8) !void {
    const full_path = try std.fs.path.join(allocator, &.{ dir_path, file_name });
    defer allocator.free(full_path);
    if (std.fs.path.dirname(full_path)) |parent| {
        try cwd.createDirPath(io, parent);
    }
    const output_file = try cwd.createFile(io, full_path, .{});
    defer output_file.close(io);
    try output_file.writeStreamingAll(io, content);
    std.log.info("Wrote '{s}'", .{full_path});
}

fn generateMultipleFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, unified_doc: @import("models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
    const dir_path = args.output_path orelse default_output_dir;
    try cwd.createDirPath(io, dir_path);

    const models_file = args.file_names.get(.models) orelse cli.FileKind.models.defaultName();
    const runtime_file = args.file_names.get(.runtime) orelse cli.FileKind.runtime.defaultName();
    const client_file = args.file_names.get(.client) orelse cli.FileKind.client.defaultName();

    var model_generator = UnifiedModelGenerator.init(allocator);
    defer model_generator.deinit();
    const generated_models = try model_generator.generate(unified_doc);
    defer allocator.free(generated_models);

    const header = try generated_header.renderNowFromBuildInfo(allocator, io);
    defer allocator.free(header);

    const models_content = try std.mem.concat(allocator, u8, &.{ header, generated_models });
    defer allocator.free(models_content);
    try writeFile(allocator, io, cwd, dir_path, models_file, models_content);

    if (args.models_only) return;

    var runtime_gen = RuntimeGenerator.init(allocator);
    defer runtime_gen.deinit();
    const generated_runtime = try runtime_gen.generate();
    defer allocator.free(generated_runtime);

    const runtime_content = try std.mem.concat(allocator, u8, &.{ header, generated_runtime });
    defer allocator.free(runtime_content);
    try writeFile(allocator, io, cwd, dir_path, runtime_file, runtime_content);

    const models_alias = try deriveAlias(allocator, models_file, "models");
    defer allocator.free(models_alias);
    const runtime_alias = try deriveAlias(allocator, runtime_file, "runtime");
    defer allocator.free(runtime_alias);
    const models_prefix = try std.mem.concat(allocator, u8, &.{ models_alias, "." });
    defer allocator.free(models_prefix);

    const models_import_path = if (std.fs.path.dirname(client_file)) |client_dir|
        blk: {
            const raw = try std.fs.path.relative(allocator, ".", null, client_dir, models_file);
            defer allocator.free(raw);
            break :blk try std.mem.replaceOwned(u8, allocator, raw, "\\", "/");
        }
    else
        models_file;
    defer if (std.fs.path.dirname(client_file) != null) allocator.free(models_import_path);
    const runtime_import_path = if (std.fs.path.dirname(client_file)) |client_dir|
        blk: {
            const raw = try std.fs.path.relative(allocator, ".", null, client_dir, runtime_file);
            defer allocator.free(raw);
            break :blk try std.mem.replaceOwned(u8, allocator, raw, "\\", "/");
        }
    else
        runtime_file;
    defer if (std.fs.path.dirname(client_file) != null) allocator.free(runtime_import_path);

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

    const client_content = try std.mem.concat(allocator, u8, &.{ header, generated_api });
    defer allocator.free(client_content);
    try writeFile(allocator, io, cwd, dir_path, client_file, client_content);
}

fn generateCodeFromDocument(allocator: std.mem.Allocator, io: std.Io, doc: anytype, args: cli.CliArgs, comptime Converter: type) !void {
    var converter = Converter.init(allocator);
    var unified_doc = try converter.convert(doc);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, unified_doc, args);
}

fn deriveAlias(allocator: std.mem.Allocator, file_name: []const u8, fallback: []const u8) ![]const u8 {
    const stem = if (std.mem.lastIndexOfScalar(u8, file_name, '.')) |dot|
        file_name[0..dot]
    else
        file_name;
    if (stem.len == 0) return allocator.dupe(u8, fallback);

    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    if (std.ascii.isDigit(stem[0])) try buf.append(allocator, '_');
    for (stem) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_') {
            try buf.append(allocator, c);
        } else {
            try buf.append(allocator, '_');
        }
    }
    const result = try buf.toOwnedSlice(allocator);
    if (ident.isReservedIdent(result)) {
        defer allocator.free(result);
        var prefixed = std.ArrayList(u8).empty;
        defer prefixed.deinit(allocator);
        try prefixed.append(allocator, '_');
        try prefixed.appendSlice(allocator, result);
        return try prefixed.toOwnedSlice(allocator);
    }
    return result;
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

test "deriveAlias returns the file stem as the import alias" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias = try deriveAlias(allocator, "types.zig", "models");
    defer allocator.free(alias);
    try std.testing.expectEqualStrings("types", alias);
}

test "deriveAlias sanitizes non-identifier characters in the stem" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias = try deriveAlias(allocator, "my-types.zig", "models");
    defer allocator.free(alias);
    try std.testing.expectEqualStrings("my_types", alias);
}

test "deriveAlias prefixes underscore when the stem starts with a digit" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias = try deriveAlias(allocator, "1types.zig", "models");
    defer allocator.free(alias);
    try std.testing.expectEqualStrings("_1types", alias);
}

test "deriveAlias handles file names without an extension" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias = try deriveAlias(allocator, "models", "models");
    defer allocator.free(alias);
    try std.testing.expectEqualStrings("models", alias);
}

test "deriveAlias falls back to the kind name when the stem is empty" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias = try deriveAlias(allocator, ".zig", "runtime");
    defer allocator.free(alias);
    try std.testing.expectEqualStrings("runtime", alias);
}

test "deriveAlias prefixes underscore for reserved Zig keywords" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias = try deriveAlias(allocator, "if.zig", "models");
    defer allocator.free(alias);
    try std.testing.expectEqualStrings("_if", alias);
}

test "deriveAlias handles collision between models.zig and a-b.zig" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const alias1 = try deriveAlias(allocator, "models.zig", "models");
    defer allocator.free(alias1);
    const alias2 = try deriveAlias(allocator, "a-b.zig", "models");
    defer allocator.free(alias2);
    try std.testing.expect(!std.mem.eql(u8, alias1, alias2));
}

fn buildPetstoreUnified(allocator: std.mem.Allocator) !@import("models/common/document.zig").UnifiedDocument {
    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
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
    var openapi = try models.OpenApiDocument.parseFromJson(allocator, json);
    defer openapi.deinit(allocator);
    var converter = OpenApiConverter.init(allocator);
    return try converter.convert(openapi);
}

test "generateMultipleFiles writes custom file names with derived import aliases" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
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

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "types.zig", .runtime = "http.zig", .client = "api.zig" },
    });

    const types = try tmp.dir.readFileAlloc(std.testing.io, "out/types.zig", allocator, .unlimited);
    defer allocator.free(types);
    try std.testing.expect(std.mem.indexOf(u8, types, "pub const Pet") != null);

    const http = try tmp.dir.readFileAlloc(std.testing.io, "out/http.zig", allocator, .unlimited);
    defer allocator.free(http);
    try std.testing.expect(std.mem.indexOf(u8, http, "pub fn Owned") != null);

    const api = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(api);
    try std.testing.expect(std.mem.indexOf(u8, api, "const types = @import(\"types.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "const http = @import(\"http.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "const Owned = http.Owned;") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/models.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/runtime.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/client.zig", .{}));
}

test "generateMultipleFiles sanitizes the import alias from the file name" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
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

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "my-types.zig" },
    });

    const api = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(api);
    try std.testing.expect(std.mem.indexOf(u8, api, "const my_types = @import(\"my-types.zig\");") != null);
}

test "generateMultipleFiles with models-only honors the custom models file name" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "post": {
        \\        "operationId": "addPet",
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": {
        \\            "application/json": {
        \\              "schema": { "$ref": "#/components/schemas/Pet" }
        \\            }
        \\          }
        \\        },
        \\        "responses": {
        \\          "200": { "description": "ok" }
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

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .models_only = true,
        .output_path = "out",
        .file_names = .{ .models = "types.zig" },
    });

    const types = try tmp.dir.readFileAlloc(std.testing.io, "out/types.zig", allocator, .unlimited);
    defer allocator.free(types);
    try std.testing.expect(std.mem.indexOf(u8, types, "pub const Pet") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/runtime.zig", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "out/client.zig", .{}));
}


test "generateMultipleFiles creates parent directories for file names with subpaths" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {}
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "gen/models.zig" },
    });

    const content = try tmp.dir.readFileAlloc(std.testing.io, "out/gen/models.zig", allocator, .unlimited);
    defer allocator.free(content);
    try std.testing.expect(content.len > 0);
}

test "generateMultipleFiles computes relative import paths for nested client" {
    const test_utils = @import("tests/test_utils.zig");

    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "openapi": "3.0.0",
        \\  "info": { "title": "fixture", "version": "1.0.0" },
        \\  "paths": {
        \\    "/pets": {
        \\      "get": {
        \\        "operationId": "listPets",
        \\        "responses": {
        \\          "200": {
        \\            "description": "ok",
        \\            "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Pet" } } } }
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

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .file_names = .{ .models = "types.zig", .runtime = "http.zig", .client = "sub/client.zig" },
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/sub/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../types.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../http.zig\")") != null);
}
