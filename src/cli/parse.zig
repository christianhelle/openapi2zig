const std = @import("std");
const types = @import("types.zig");
const usage = @import("usage.zig");
const fnames = @import("file_names.zig");
const ResourceWrapperMode = types.ResourceWrapperMode;
const MultipleClientsMode = types.MultipleClientsMode;
const FileKind = types.FileKind;
const FileNameOverrides = types.FileNameOverrides;
const CliArgs = types.CliArgs;
const ParsedArgs = types.ParsedArgs;
const printUsage = usage.printUsage;
const printError = usage.printError;
const max_import_alias_len = fnames.max_import_alias_len;
const findDuplicateFileName = fnames.findDuplicateFileName;
const fileNamesCollide = fnames.fileNamesCollide;
const deriveAlias = fnames.deriveAlias;
const deriveAliasInto = fnames.deriveAliasInto;
const importBasename = fnames.importBasename;
const importDirname = fnames.importDirname;
const resolveRuntimeModulePath = fnames.resolveRuntimeModulePath;
const effectiveAliasesInto = fnames.effectiveAliasesInto;
const findDuplicateAlias = fnames.findDuplicateAlias;
const findReservedAlias = fnames.findReservedAlias;
const validateFileName = fnames.validateFileName;
const isAbsoluteImportPath = fnames.isAbsoluteImportPath;
const validateImportPath = fnames.validateImportPath;

pub fn parse(allocator: std.mem.Allocator, args: []const [:0]const u8) !ParsedArgs {
    if (args.len >= 2 and std.mem.eql(u8, args[1], "upgrade")) {
        return .{
            .upgrade = true,
            .args = .{ .input_path = "" },
        };
    }

    var has_runtime_only = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--runtime-only")) {
            has_runtime_only = true;
            break;
        }
    }

    const min_args: usize = if (has_runtime_only) 3 else 4;
    if (args.len < min_args or (args.len >= 1 and !std.mem.eql(u8, args[1], "generate"))) {
        printUsage();
        return .{
            .help = true,
            .args = .{ .input_path = "" },
        };
    }

    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var base_url: ?[]const u8 = null;
    var resource_wrappers: ResourceWrapperMode = .paths;
    var resource_wrappers_explicit = false;
    var models_only = false;
    var multiple_files = false;
    var multiple_clients: ?MultipleClientsMode = null;
    var file_names: FileNameOverrides = .{};
    var runtime_module: ?[]const u8 = null;
    var tags_list = std.ArrayList([]const u8).empty;
    defer tags_list.deinit(allocator);
    var tags: []const []const u8 = &.{};
    var tags_owned = false;
    var force = false;
    var runtime_only = false;
    var parameters_as_struct = false;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("OpenAPI spec path or URL required\n", .{});
                return error.InvalidArguments;
            }
            input_path = args[i];
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("output path required\n", .{});
                return error.InvalidArguments;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--base-url")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("base URL required\n", .{});
                return error.InvalidArguments;
            }
            base_url = args[i];
        } else if (std.mem.eql(u8, arg, "--resource-wrappers")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("resource wrapper mode required\n", .{});
                return error.InvalidArguments;
            }
            resource_wrappers = parseResourceWrapperMode(args[i]) orelse {
                printUsage();
                printError("invalid resource wrapper mode '{s}'\n", .{args[i]});
                return error.InvalidArguments;
            };
            resource_wrappers_explicit = true;
        } else if (std.mem.eql(u8, arg, "--models-only")) {
            models_only = true;
        } else if (std.mem.eql(u8, arg, "--tag")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("--tag value required\n", .{});
                return error.InvalidArguments;
            }
            if (std.mem.startsWith(u8, args[i], "-")) {
                printUsage();
                printError("--tag value must not start with '-'\n", .{});
                return error.InvalidArguments;
            }
            try tags_list.append(allocator, args[i]);
        } else if (std.mem.eql(u8, arg, "--multiple-files")) {
            multiple_files = true;
        } else if (std.mem.eql(u8, arg, "--multiple-clients")) {
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                i += 1;
                multiple_clients = parseMultipleClientsMode(args[i]) orelse {
                    printUsage();
                    printError("invalid multiple-clients mode '{s}', expected PerTag or PerEndpoint\n", .{args[i]});
                    return error.InvalidArguments;
                };
            } else {
                multiple_clients = .per_tag;
            }
        } else if (std.mem.eql(u8, arg, "--file-name")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("--file-name value required\n", .{});
                return error.InvalidArguments;
            }
            const value = args[i];
            const eq = std.mem.indexOfScalar(u8, value, '=') orelse {
                printUsage();
                printError("invalid --file-name value '{s}', expected format <kind>=<name>\n", .{value});
                return error.InvalidArguments;
            };
            const kind = FileKind.fromString(value[0..eq]) orelse {
                printUsage();
                printError("invalid file kind '{s}', expected models, runtime, or client\n", .{value[0..eq]});
                return error.InvalidArguments;
            };
            if (eq + 1 >= value.len) {
                printUsage();
                printError("empty file name for kind '{s}'\n", .{value[0..eq]});
                return error.InvalidArguments;
            }
            const file_name = value[eq + 1 ..];
            validateFileName(file_name) catch |err| switch (err) {
                error.InvalidFileName => {
                    printUsage();
                    printError("invalid file name '{s}' for kind '{s}'\n", .{ file_name, value[0..eq] });
                    return error.InvalidArguments;
                },
            };
            file_names.set(kind, file_name) catch |err| switch (err) {
                error.DuplicateFileOverride => {
                    printUsage();
                    printError("duplicate --file-name for kind '{s}'\n", .{value[0..eq]});
                    return error.InvalidArguments;
                },
            };
        } else if (std.mem.eql(u8, arg, "--runtime-module")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                printError("--runtime-module value required\n", .{});
                return error.InvalidArguments;
            }
            if (runtime_module != null) {
                printUsage();
                printError("duplicate --runtime-module\n", .{});
                return error.InvalidArguments;
            }
            const value = args[i];
            validateImportPath(value) catch |err| switch (err) {
                error.InvalidFileName => {
                    printUsage();
                    printError("invalid runtime module path '{s}'\n", .{value});
                    return error.InvalidArguments;
                },
            };
            runtime_module = value;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--runtime-only")) {
            runtime_only = true;
        } else if (std.mem.eql(u8, arg, "--parameters-as-struct")) {
            parameters_as_struct = true;
        }
    }

    if (input_path == null and !runtime_only) {
        printUsage();
        printError("OpenAPI spec path or URL required\n", .{});
        return error.InvalidArguments;
    }

    if (runtime_only and models_only) {
        printUsage();
        printError("--runtime-only and --models-only are mutually exclusive\n", .{});
        return error.InvalidArguments;
    }

    if (runtime_only and runtime_module != null) {
        printUsage();
        printError("--runtime-only and --runtime-module are mutually exclusive\n", .{});
        return error.InvalidArguments;
    }

    if (runtime_only) {
        if (multiple_clients != null) {
            printUsage();
            printError("--multiple-clients has no effect with --runtime-only\n", .{});
            return error.InvalidArguments;
        }
        if (tags_list.items.len > 0) {
            printUsage();
            printError("--tag has no effect with --runtime-only\n", .{});
            return error.InvalidArguments;
        }
        if (base_url != null) {
            printUsage();
            printError("--base-url has no effect with --runtime-only\n", .{});
            return error.InvalidArguments;
        }
        if (parameters_as_struct) {
            printUsage();
            printError("--parameters-as-struct has no effect with --runtime-only\n", .{});
            return error.InvalidArguments;
        }
        if (resource_wrappers_explicit) {
            printUsage();
            printError("--resource-wrappers has no effect with --runtime-only\n", .{});
            return error.InvalidArguments;
        }
        if (file_names.models != null or file_names.client != null) {
            printUsage();
            printError("--file-name for models or client has no effect with --runtime-only\n", .{});
            return error.InvalidArguments;
        }
    }

    if (!multiple_files and file_names.any()) {
        printUsage();
        printError("--file-name requires --multiple-files\n", .{});
        return error.InvalidArguments;
    }

    if (runtime_module != null and !multiple_files) {
        printUsage();
        printError("--runtime-module requires --multiple-files\n", .{});
        return error.InvalidArguments;
    }

    if (runtime_module != null and file_names.runtime != null) {
        printUsage();
        printError("--runtime-module and --file-name runtime are mutually exclusive\n", .{});
        return error.InvalidArguments;
    }

    if (runtime_module != null and models_only) {
        printUsage();
        printError("--runtime-module has no effect with --models-only\n", .{});
        return error.InvalidArguments;
    }

    if (multiple_clients != null and resource_wrappers_explicit and resource_wrappers != .none) {
        printUsage();
        printError("--multiple-clients and --resource-wrappers are mutually exclusive (only --resource-wrappers none is allowed)\n", .{});
        return error.InvalidArguments;
    }

    if (multiple_clients != null and models_only) {
        printUsage();
        printError("--multiple-clients has no effect with --models-only\n", .{});
        return error.InvalidArguments;
    }

    // --multiple-clients is mutually exclusive with resource wrappers; when the
    // user did not pass --resource-wrappers explicitly, default it to none so
    // the generator does not also emit resource wrappers.
    if (multiple_clients != null and !resource_wrappers_explicit) {
        resource_wrappers = .none;
    }

    if (models_only and (file_names.runtime != null or file_names.client != null)) {
        printUsage();
        printError("--file-name for runtime or client has no effect with --models-only\n", .{});
        return error.InvalidArguments;
    }

    if (!models_only) {
        if (runtime_module) |mod| {
            // When re-using an external runtime, only models and client are emitted, so
            // duplicate checks must be scoped to those two outputs plus the imported runtime alias.
            const models_name = file_names.get(.models) orelse FileKind.models.defaultName();
            const client_name = file_names.get(.client) orelse FileKind.client.defaultName();
            if (fileNamesCollide(models_name, client_name)) {
                printUsage();
                printError("duplicate output file name '{s}' for multiple --file-name options\n", .{models_name});
                return error.InvalidArguments;
            }
            const resolved_runtime = try resolveRuntimeModulePath(allocator, client_name, mod);
            defer allocator.free(resolved_runtime);
            if (fileNamesCollide(resolved_runtime, models_name)) {
                printUsage();
                printError("runtime module path '{s}' resolves to output file '{s}'\n", .{ mod, models_name });
                return error.InvalidArguments;
            }
            if (fileNamesCollide(resolved_runtime, client_name)) {
                printUsage();
                printError("runtime module path '{s}' resolves to output file '{s}'\n", .{ mod, client_name });
                return error.InvalidArguments;
            }
            var alias_bufs: [3][max_import_alias_len]u8 = undefined;
            var aliases: [3][]const u8 = undefined;
            aliases[0] = deriveAliasInto(&alias_bufs[0], models_name, "models");
            aliases[1] = deriveAliasInto(&alias_bufs[1], importBasename(mod), "runtime");
            aliases[2] = deriveAliasInto(&alias_bufs[2], client_name, "client");
            if (findDuplicateAlias(aliases)) |dup| {
                printUsage();
                printError("output file names map to the same import alias '{s}' for multiple --file-name options\n", .{dup});
                return error.InvalidArguments;
            }
            if (findReservedAlias(aliases)) |alias| {
                printUsage();
                printError("output file name maps to import alias '{s}', which the generated client reserves\n", .{alias});
                return error.InvalidArguments;
            }
        } else {
            if (findDuplicateFileName(file_names)) |dup| {
                printUsage();
                printError("duplicate output file name '{s}' for multiple --file-name options\n", .{dup});
                return error.InvalidArguments;
            }

            var alias_bufs: [3][max_import_alias_len]u8 = undefined;
            const aliases = effectiveAliasesInto(file_names, &alias_bufs);

            if (findDuplicateAlias(aliases)) |dup| {
                printUsage();
                printError("output file names map to the same import alias '{s}' for multiple --file-name options\n", .{dup});
                return error.InvalidArguments;
            }

            if (findReservedAlias(aliases)) |alias| {
                printUsage();
                printError("output file name maps to import alias '{s}', which the generated client reserves\n", .{alias});
                return error.InvalidArguments;
            }
        }
    }

    if (tags_list.items.len > 0) {
        tags = try tags_list.toOwnedSlice(allocator);
        tags_owned = true;
    }
    errdefer if (tags_owned) allocator.free(tags);

    return .{
        .args = .{
            .input_path = input_path orelse "",
            .output_path = output_path,
            .base_url = base_url,
            .resource_wrappers = resource_wrappers,
            .models_only = models_only,
            .multiple_files = multiple_files,
            .multiple_clients = multiple_clients,
            .file_names = file_names,
            .runtime_module = runtime_module,
            .tags = tags,
            .owns_tags = tags_owned,
            .force = force,
            .runtime_only = runtime_only,
            .parameters_as_struct = parameters_as_struct,
        },
    };
}

pub fn parseResourceWrapperMode(value: []const u8) ?ResourceWrapperMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "tags")) return .tags;
    if (std.mem.eql(u8, value, "paths")) return .paths;
    if (std.mem.eql(u8, value, "hybrid")) return .hybrid;
    return null;
}

/// Parse a --multiple-clients mode value. Matching is case-insensitive and
/// ignores '-' and '_' separators, so PerTag, pertag, per-tag, and PER_TAG
/// all resolve to .per_tag.
pub fn parseMultipleClientsMode(value: []const u8) ?MultipleClientsMode {
    var buf: [64]u8 = undefined;
    if (value.len == 0 or value.len > buf.len) return null;
    var n: usize = 0;
    for (value) |c| {
        const lower = std.ascii.toLower(c);
        if (lower == '-' or lower == '_') continue;
        buf[n] = lower;
        n += 1;
    }
    const key = buf[0..n];
    if (std.mem.eql(u8, key, "pertag")) return .per_tag;
    if (std.mem.eql(u8, key, "perendpoint")) return .per_endpoint;
    return null;
}
