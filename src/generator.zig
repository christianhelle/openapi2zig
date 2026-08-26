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

fn generateCodeFromUnifiedDocument(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, unified_doc: @import("models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
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

fn writeFile(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, dir_path: []const u8, file_name: []const u8, raw_code: []const u8, force: bool) !void {
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
        // Best-effort existence check relative to the output directory / client location.
        const candidate_path = if (std.fs.path.dirname(client_file)) |client_dir|
            try std.fs.path.join(allocator, &.{ dir_path, client_dir, mod })
        else
            try std.fs.path.join(allocator, &.{ dir_path, mod });
        defer allocator.free(candidate_path);
        cwd.access(io, candidate_path, .{}) catch {
            std.log.info("Runtime module '{s}' not found at '{s}' (import will be dangling until file exists)", .{ mod, candidate_path });
        };
        runtime_alias_owned = try cli.deriveAlias(allocator, std.fs.path.basename(mod), "runtime");
        runtime_alias = runtime_alias_owned.?;
        runtime_import_owned = try std.mem.replaceOwned(u8, allocator, mod, "\\", "/");
        runtime_import_path = runtime_import_owned.?;
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

fn generateCodeFromDocument(allocator: std.mem.Allocator, io: std.Io, doc: anytype, args: cli.CliArgs, comptime Converter: type) !void {
    var converter = Converter.init(allocator);
    var unified_doc = try converter.convert(doc);
    defer unified_doc.deinit(allocator);
    try generateCodeFromUnifiedDocument(allocator, io, std.Io.Dir.cwd(), unified_doc, args);
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

test "generateCodeFromUnifiedDocument filters operations and models by requested tags" {
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
        \\        "tags": ["pet"],
        \\        "responses": {
        \\          "200": {
        \\            "description": "ok",
        \\            "content": { "application/json": { "schema": { "type": "array", "items": { "$ref": "#/components/schemas/Pet" } } } }
        \\          }
        \\        }
        \\      }
        \\    },
        \\    "/store/order": {
        \\      "post": {
        \\        "operationId": "placeOrder",
        \\        "tags": ["store"],
        \\        "requestBody": {
        \\          "required": true,
        \\          "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Order" } } }
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
        \\      },
        \\      "Order": {
        \\        "type": "object",
        \\        "properties": { "id": { "type": "integer" } }
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var unified = try openapi2zig.parseToUnified(allocator, json);
    defer unified.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "api.zig",
        .tags = &.{"pet"},
    });

    const api = try tmp.dir.readFileAlloc(std.testing.io, "api.zig", allocator, .unlimited);
    defer allocator.free(api);

    try std.testing.expect(std.mem.indexOf(u8, api, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "pub const Order") == null);
    try std.testing.expect(std.mem.indexOf(u8, api, "pub fn listPets") != null);
    try std.testing.expect(std.mem.indexOf(u8, api, "placeOrder") == null);
}

test "generateMultipleFiles composes per-tag client structs into the client file" {
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
        \\        "tags": ["pet"],
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
        .multiple_clients = .per_tag,
        .output_path = "out",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "pub const PetClient = struct {") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "pub fn listPets(self: *PetClient") != null);

    const models_content = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(models_content);
    try std.testing.expect(std.mem.indexOf(u8, models_content, "pub const Pet") != null);
    try std.testing.expect(std.mem.indexOf(u8, models_content, "PetClient") == null);
}

test "generateCodeFromUnifiedDocument preserves timestamp when code unchanged" {
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

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const first = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(first);

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const second = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expectEqualStrings(first, second);
}

test "generateMultipleFiles preserves timestamps when code unchanged" {
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
    });

    const first_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(first_models);

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
    });

    const second_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(second_models);

    try std.testing.expectEqualStrings(first_models, second_models);
}

test "generateCodeFromUnifiedDocument overwrites unchanged file when force is set" {
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

    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
    });

    const first = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(first);

    // Sleep to ensure timestamp in header will differ (header uses second precision)
    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    // Force overwrites even when unchanged, so second file should have a new timestamp header
    try generateCodeFromUnifiedDocument(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .output_path = "out/api.zig",
        .force = true,
    });

    const second = try tmp.dir.readFileAlloc(std.testing.io, "out/api.zig", allocator, .unlimited);
    defer allocator.free(second);

    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "generateMultipleFiles overwrites unchanged files when force is set" {
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
    });

    const first_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(first_models);

    try std.Io.sleep(std.testing.io, .fromMilliseconds(1100), .real);

    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "out",
        .force = true,
    });

    const second_models = try tmp.dir.readFileAlloc(std.testing.io, "out/models.zig", allocator, .unlimited);
    defer allocator.free(second_models);

    try std.testing.expect(!std.mem.eql(u8, first_models, second_models));
}

test "generateMultipleFiles with runtime_module reuses existing runtime" {
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

    // Leader: normal generation that creates runtime.zig in shared location
    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "shared",
    });

    const shared_runtime = try tmp.dir.readFileAlloc(std.testing.io, "shared/runtime.zig", allocator, .unlimited);
    defer allocator.free(shared_runtime);
    try std.testing.expect(std.mem.indexOf(u8, shared_runtime, "pub fn Owned") != null);

    // Follower: reuse existing runtime via client-relative import
    try generateMultipleFiles(allocator, std.testing.io, tmp.dir, unified, .{
        .input_path = "fixture.json",
        .multiple_files = true,
        .output_path = "client",
        .runtime_module = "../shared/runtime.zig",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "client/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../shared/runtime.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const runtime = @import(\"../shared/runtime.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const Owned = runtime.Owned;") != null);

    // No runtime should be emitted in the follower output
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "client/runtime.zig", .{}));

    const models_content = try tmp.dir.readFileAlloc(std.testing.io, "client/models.zig", allocator, .unlimited);
    defer allocator.free(models_content);
    try std.testing.expect(std.mem.indexOf(u8, models_content, "pub const Pet") != null);
}

test "generateMultipleFiles with runtime_module derives alias from basename and supports custom models name" {
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
        .runtime_module = "../shared/my_runtime.zig",
        .file_names = .{ .models = "contracts.zig" },
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "const my_runtime = @import(\"../shared/my_runtime.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const Owned = my_runtime.Owned;") != null);
    try std.testing.expect(std.mem.indexOf(u8, client, "const contracts = @import(\"contracts.zig\");") != null);
}

test "generateMultipleFiles with runtime_module and nested client preserves verbatim import" {
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
        .file_names = .{ .client = "sub/client.zig" },
        .runtime_module = "../../shared/runtime.zig",
    });

    const client = try tmp.dir.readFileAlloc(std.testing.io, "out/sub/client.zig", allocator, .unlimited);
    defer allocator.free(client);
    try std.testing.expect(std.mem.indexOf(u8, client, "@import(\"../../shared/runtime.zig\")") != null);
}
