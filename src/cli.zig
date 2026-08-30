const std = @import("std");
const version_info = @import("build_info");
const ident = @import("generators/unified/ident_utils.zig");

/// Print usage text unless running inside a test binary, where writing
/// diagnostics to stderr during the listen-mode test run produces spurious
/// "failed command" noise in `zig build test` output.
pub fn printUsage() void {
    if (@import("builtin").is_test) return;
    std.debug.print(
        \\
        \\ openapi2zig - OpenAPI/Swagger to Zig code generator
        \\ version: {s} ({s})
        \\
        \\ Usage: openapi2zig generate [options]
        \\        openapi2zig upgrade
        \\
        \\ Options:
        \\   -i, --input <PATH_OR_URL>  OpenAPI/Swagger spec (file path or http/https URL)
        \\   -o, --output <path>        Output file path for the generated Zig code.
        \\                              (default: generated.zig)
        \\                              When --multiple-files is used, this specifies the
        \\                              output directory (default: generated/)
        \\   --base-url <url>           Base URL for the API client.
        \\                              (default: server URL from OpenAPI Specification)
        \\   --resource-wrappers <mode> Generate resource wrappers: none, tags, paths, hybrid.
        \\                              (default: paths)
        \\   --multiple-clients [PerTag|PerEndpoint]
        \\                              Generate multiple client structs instead of a single
        \\                              flat client. PerTag (default): one client per OpenAPI
        \\                              tag. PerEndpoint: one struct per operation with an
        \\                              execute() method.
        \\   --tag <name>              Include only operations with the specified OpenAPI
        \\                              tag and only the models they reference.
        \\                              Can be specified multiple times.
        \\   --models-only              Generate only Zig models, skipping the API client.
        \\   --multiple-files           Generate separate output files for models, runtime, and API client
        \\                              into the output directory specified by -o.
        \\   --file-name <kind>=<name>  Customize an output file name in --multiple-files mode.
        \\                              <kind> is models, runtime, or client.
        \\                              (default: models.zig, runtime.zig, client.zig)
        \\                              Can be specified multiple times.
        \\   --runtime-module <path>    Re-use an existing runtime.zig instead of generating one.
        \\                              The path is a Zig import path relative to the generated
        \\                              client file (e.g. "../runtime.zig").
        \\                              Requires --multiple-files and is mutually exclusive with
        \\                              --file-name runtime=... .
        \\   --runtime-only             Generate only the runtime module. No input spec is
        \\                              required; when -i is given it is ignored.
        \\                              (default output: runtime.zig)
        \\   --force                   Force overwriting output even when unchanged
        \\   --parameters-as-struct    Wrap method parameters in a single options struct
        \\                            instead of individual function arguments
        \\
        \\ EXAMPLES:
        \\   openapi2zig generate -i ./openapi/petstore.json -o api.zig
        \\   openapi2zig generate -i ./openapi/petstore.json -o models.zig --models-only
        \\   openapi2zig generate -i https://petstore3.swagger.io/api/v3/openapi.json -o api.zig
        \\
    , .{ version_info.VERSION, version_info.GIT_COMMIT });
}

/// Print an error diagnostic unless running inside a test binary.
pub fn printError(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").is_test) return;
    std.debug.print("\nError: " ++ fmt, args);
}

pub const ResourceWrapperMode = enum {
    none,
    tags,
    paths,
    hybrid,
};

pub const MultipleClientsMode = enum {
    per_tag,
    per_endpoint,

    pub fn displayName(self: MultipleClientsMode) []const u8 {
        return switch (self) {
            .per_tag => "PerTag",
            .per_endpoint => "PerEndpoint",
        };
    }
};

pub const FileKind = enum {
    models,
    runtime,
    client,

    pub fn fromString(value: []const u8) ?FileKind {
        if (std.mem.eql(u8, value, "models")) return .models;
        if (std.mem.eql(u8, value, "runtime")) return .runtime;
        if (std.mem.eql(u8, value, "client")) return .client;
        return null;
    }

    pub fn defaultName(self: FileKind) []const u8 {
        return switch (self) {
            .models => "models.zig",
            .runtime => "runtime.zig",
            .client => "client.zig",
        };
    }
};

pub const FileNameOverrides = struct {
    models: ?[]const u8 = null,
    runtime: ?[]const u8 = null,
    client: ?[]const u8 = null,

    pub fn get(self: FileNameOverrides, kind: FileKind) ?[]const u8 {
        return switch (kind) {
            .models => self.models,
            .runtime => self.runtime,
            .client => self.client,
        };
    }

    pub fn set(self: *FileNameOverrides, kind: FileKind, name: []const u8) error{DuplicateFileOverride}!void {
        switch (kind) {
            .models => {
                if (self.models != null) return error.DuplicateFileOverride;
                self.models = name;
            },
            .runtime => {
                if (self.runtime != null) return error.DuplicateFileOverride;
                self.runtime = name;
            },
            .client => {
                if (self.client != null) return error.DuplicateFileOverride;
                self.client = name;
            },
        }
    }

    pub fn any(self: FileNameOverrides) bool {
        return self.models != null or self.runtime != null or self.client != null;
    }
};

pub fn findDuplicateFileName(file_names: FileNameOverrides) ?[]const u8 {
    const names = [_][]const u8{
        file_names.models orelse FileKind.models.defaultName(),
        file_names.runtime orelse FileKind.runtime.defaultName(),
        file_names.client orelse FileKind.client.defaultName(),
    };
    var i: usize = 0;
    while (i < names.len) : (i += 1) {
        var j = i + 1;
        while (j < names.len) : (j += 1) {
            if (fileNamesCollide(names[i], names[j])) return names[i];
        }
    }
    return null;
}

/// Compare two output file names treating '/' and '\' as equivalent path
/// separators and ignoring case, matching how the same on-disk path resolves on
/// case-insensitive filesystems.
pub fn fileNamesCollide(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const na = if (ca == '/' or ca == '\\') '/' else std.ascii.toLower(ca);
        const nb = if (cb == '/' or cb == '\\') '/' else std.ascii.toLower(cb);
        if (na != nb) return false;
    }
    return true;
}

const max_import_alias_len = 128;

/// Derive the Zig import alias for a generated file name into a caller-provided
/// buffer. This is the single source of truth for alias derivation; the
/// allocating `deriveAlias` used by the generator wraps this.
pub fn deriveAliasInto(buf: []u8, file_name: []const u8, fallback: []const u8) []const u8 {
    const stem = if (std.mem.lastIndexOfScalar(u8, file_name, '.')) |dot|
        file_name[0..dot]
    else
        file_name;
    if (stem.len == 0 or stem.len + 1 > buf.len) return fallback;

    var n: usize = 0;
    if (std.ascii.isDigit(stem[0])) {
        buf[n] = '_';
        n += 1;
    }
    for (stem) |c| {
        buf[n] = if (std.ascii.isAlphanumeric(c) or c == '_') c else '_';
        n += 1;
    }
    if (ident.isReservedIdent(buf[0..n])) {
        std.mem.copyBackwards(u8, buf[1 .. n + 1], buf[0..n]);
        buf[0] = '_';
        n += 1;
    }
    return buf[0..n];
}

/// Derive the Zig import alias for a generated file name. The caller owns the
/// returned slice. Mirrors the alias used by the multi-file generator so
/// parse-time validation agrees with the generated imports.
pub fn deriveAlias(allocator: std.mem.Allocator, file_name: []const u8, fallback: []const u8) ![]const u8 {
    var buf: [max_import_alias_len]u8 = undefined;
    return allocator.dupe(u8, deriveAliasInto(&buf, file_name, fallback));
}

/// Return the basename of an import path, treating both '/' and '\' as
/// separators. This handles Windows-style paths correctly on non-Windows hosts.
pub fn importBasename(path: []const u8) []const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return path[i + 1 ..];
        }
    }
    return path;
}

/// Return the directory of an import path, treating both '/' and '\' as
/// separators. Returns null if there is no directory component.
pub fn importDirname(path: []const u8) ?[]const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            if (i == 0) return "";
            return path[0..i];
        }
    }
    return null;
}

pub fn resolveRuntimeModulePath(allocator: std.mem.Allocator, client_name: []const u8, runtime_mod: []const u8) ![]const u8 {
    const client_dir = importDirname(client_name);
    var segments = std.ArrayList([]const u8).empty;
    defer segments.deinit(allocator);
    if (client_dir) |dir| {
        if (dir.len > 0) {
            var it = std.mem.splitAny(u8, dir, "/\\");
            while (it.next()) |part| {
                if (part.len == 0) continue;
                try segments.append(allocator, part);
            }
        }
    }
    var it = std.mem.splitAny(u8, runtime_mod, "/\\");
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (segments.items.len > 0 and !std.mem.eql(u8, segments.getLast(), "..")) {
                _ = segments.pop();
            } else {
                try segments.append(allocator, "..");
            }
        } else {
            try segments.append(allocator, part);
        }
    }
    if (segments.items.len == 0) {
        return try allocator.dupe(u8, "");
    }
    return try std.mem.join(allocator, "/", segments.items);
}

pub fn effectiveAliasesInto(file_names: FileNameOverrides, bufs: *[3][max_import_alias_len]u8) [3][]const u8 {
    var aliases: [3][]const u8 = undefined;
    const kinds = [_]FileKind{ .models, .runtime, .client };
    for (kinds, 0..) |kind, i| {
        const name = file_names.get(kind) orelse kind.defaultName();
        aliases[i] = deriveAliasInto(&bufs[i], name, switch (kind) {
            .models => "models",
            .runtime => "runtime",
            .client => "client",
        });
    }
    return aliases;
}

pub fn findDuplicateAlias(aliases: [3][]const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < aliases.len) : (i += 1) {
        var j = i + 1;
        while (j < aliases.len) : (j += 1) {
            if (std.mem.eql(u8, aliases[i], aliases[j])) return aliases[i];
        }
    }
    return null;
}

/// Aliases that collide with names the generated client declares itself.
const reserved_aliases = [_][]const u8{ "std", "Client", "_" };

pub fn findReservedAlias(aliases: [3][]const u8) ?[]const u8 {
    for (aliases) |alias| {
        for (reserved_aliases) |reserved| {
            if (std.mem.eql(u8, alias, reserved)) return alias;
        }
    }
    return null;
}

pub fn validateFileName(name: []const u8) error{InvalidFileName}!void {
    if (std.fs.path.isAbsolute(name)) return error.InvalidFileName;
    var fwd = std.mem.splitScalar(u8, name, '/');
    while (fwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidFileName;
    }
    var bwd = std.mem.splitScalar(u8, name, '\\');
    while (bwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidFileName;
    }
}

/// Return true when `path` is absolute under any platform's conventions. This
/// treats root-relative and Windows drive paths as absolute regardless of the
/// build host, so import validation does not depend on the platform.
pub fn isAbsoluteImportPath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '\\') return true;
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return true;
    return false;
}

pub fn validateImportPath(path: []const u8) error{InvalidFileName}!void {
    if (isAbsoluteImportPath(path)) return error.InvalidFileName;
    if (path.len == 0) return error.InvalidFileName;
    var fwd = std.mem.splitScalar(u8, path, '/');
    while (fwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) return error.InvalidFileName;
    }
    var bwd = std.mem.splitScalar(u8, path, '\\');
    while (bwd.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) return error.InvalidFileName;
    }
    if (std.mem.eql(u8, importBasename(path), "..")) return error.InvalidFileName;
}

pub const CliArgs = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    resource_wrappers: ResourceWrapperMode = .paths,
    models_only: bool = false,
    multiple_files: bool = false,
    multiple_clients: ?MultipleClientsMode = null,
    file_names: FileNameOverrides = .{},
    /// Optional import path to an existing runtime.zig. When set, no
    /// runtime.zig is generated and the client imports this path instead.
    /// The path is relative to the generated client file.
    runtime_module: ?[]const u8 = null,
    /// OpenAPI tags to include. When empty, no tag filtering is applied.
    /// The slice is freed by `deinit(allocator)` when `owns_tags` is true.
    tags: []const []const u8 = &.{},
    /// Whether `tags` was allocated by the parser and must be freed.
    owns_tags: bool = false,
    force: bool = false,
    /// Generate only the runtime module. The input spec is not required and,
    /// when given, is ignored entirely.
    runtime_only: bool = false,
    /// Wrap non-body method parameters in a single `options` struct instead of
    /// emitting them as individual function arguments.
    parameters_as_struct: bool = false,

    pub fn deinit(self: *CliArgs, allocator: std.mem.Allocator) void {
        if (self.owns_tags) allocator.free(self.tags);
        self.tags = &.{};
        self.owns_tags = false;
    }
};

pub const ParsedArgs = struct {
    args: CliArgs,
    upgrade: bool = false,
    help: bool = false,

    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        self.args.deinit(allocator);
    }
};

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

test {
    _ = @import("cli/tests.zig");
}
