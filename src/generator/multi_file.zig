const std = @import("std");
const cli = @import("../cli.zig");
const output_writer = @import("output_writer.zig");
const UnifiedModelGenerator = @import("../generators/unified/model_generator.zig").UnifiedModelGenerator;
const UnifiedApiGenerator = @import("../generators/unified/api_generator.zig").UnifiedApiGenerator;
const RuntimeGenerator = @import("../generators/unified/runtime_generator.zig").RuntimeGenerator;
const default_output_dir = @import("../generator.zig").default_output_dir;

pub fn writeFile(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, dir_path: []const u8, file_name: []const u8, raw_code: []const u8, force: bool) !void {
    const full_path = try std.fs.path.join(allocator, &.{ dir_path, file_name });
    defer allocator.free(full_path);

    try output_writer.writeGeneratedFile(allocator, io, cwd, full_path, raw_code, force);
}

pub fn generateMultipleFiles(allocator: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, unified_doc: @import("../models/common/document.zig").UnifiedDocument, args: cli.CliArgs) !void {
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
