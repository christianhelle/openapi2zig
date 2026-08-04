const std = @import("std");
const version_info = @import("build_info");
const ident = @import("generators/unified/ident_utils.zig");

/// Print usage text unless running inside a test binary, where writing
/// diagnostics to stderr during the listen-mode test run produces spurious
/// "failed command" noise in `zig build test` output.
fn printUsage() void {
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
        \\   --models-only              Generate only Zig models, skipping the API client.
        \\   --multiple-files           Generate separate output files for models, runtime, and API client
        \\                              into the output directory specified by -o.
        \\   --file-name <kind>=<name>  Customize an output file name in --multiple-files mode.
        \\                              <kind> is models, runtime, or client.
        \\                              (default: models.zig, runtime.zig, client.zig)
        \\                              Can be specified multiple times.
        \\
        \\ EXAMPLES:
        \\   openapi2zig generate -i ./openapi/petstore.json -o api.zig
        \\   openapi2zig generate -i ./openapi/petstore.json -o models.zig --models-only
        \\   openapi2zig generate -i https://petstore3.swagger.io/api/v3/openapi.json -o api.zig
        \\
    , .{ version_info.VERSION, version_info.GIT_COMMIT });
}

/// Print an error diagnostic unless running inside a test binary.
fn printError(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").is_test) return;
    std.debug.print("\nError: " ++ fmt, args);
}

pub const ResourceWrapperMode = enum {
    none,
    tags,
    paths,
    hybrid,
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

fn findDuplicateFileName(file_names: FileNameOverrides) ?[]const u8 {
    const names = [_][]const u8{
        file_names.models orelse FileKind.models.defaultName(),
        file_names.runtime orelse FileKind.runtime.defaultName(),
        file_names.client orelse FileKind.client.defaultName(),
    };
    var i: usize = 0;
    while (i < names.len) : (i += 1) {
        var j = i + 1;
        while (j < names.len) : (j += 1) {
            if (std.ascii.eqlIgnoreCase(names[i], names[j])) return names[i];
        }
    }
    return null;
}

const max_import_alias_len = 128;

/// Derive the Zig import alias for a generated file name into a caller-provided
/// buffer. This is the single source of truth for alias derivation; the
/// allocating `deriveAlias` used by the generator wraps this.
fn deriveAliasInto(buf: []u8, file_name: []const u8, fallback: []const u8) []const u8 {
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

fn effectiveAliasesInto(file_names: FileNameOverrides, bufs: *[3][max_import_alias_len]u8) [3][]const u8 {
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

fn findDuplicateAlias(file_names: FileNameOverrides) ?[]const u8 {
    var bufs: [3][max_import_alias_len]u8 = undefined;
    const aliases = effectiveAliasesInto(file_names, &bufs);
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

fn findReservedAlias(file_names: FileNameOverrides) ?[]const u8 {
    var bufs: [3][max_import_alias_len]u8 = undefined;
    const aliases = effectiveAliasesInto(file_names, &bufs);
    for (aliases) |alias| {
        for (reserved_aliases) |reserved| {
            if (std.mem.eql(u8, alias, reserved)) return alias;
        }
    }
    return null;
}

fn validateFileName(name: []const u8) error{InvalidFileName}!void {
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

pub const CliArgs = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    resource_wrappers: ResourceWrapperMode = .paths,
    models_only: bool = false,
    multiple_files: bool = false,
    file_names: FileNameOverrides = .{},
};

pub const ParsedArgs = struct {
    args: CliArgs,
    upgrade: bool = false,
    help: bool = false,
};

pub fn parse(args: []const [:0]const u8) !ParsedArgs {
    if (args.len >= 2 and std.mem.eql(u8, args[1], "upgrade")) {
        return .{
            .upgrade = true,
            .args = .{ .input_path = "" },
        };
    }

    if (args.len < 4 or (args.len >= 1 and !std.mem.eql(u8, args[1], "generate"))) {
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
    var models_only = false;
    var multiple_files = false;
    var file_names: FileNameOverrides = .{};

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
        } else if (std.mem.eql(u8, arg, "--models-only")) {
            models_only = true;
        } else if (std.mem.eql(u8, arg, "--multiple-files")) {
            multiple_files = true;
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
        }
    }

    if (input_path == null) {
        printUsage();
        printError("OpenAPI spec path or URL required\n", .{});
        return error.InvalidArguments;
    }

    if (!multiple_files and file_names.any()) {
        printUsage();
        printError("--file-name requires --multiple-files\n", .{});
        return error.InvalidArguments;
    }

    if (findDuplicateFileName(file_names)) |dup| {
        printUsage();
        printError("duplicate output file name '{s}' for multiple --file-name options\n", .{dup});
        return error.InvalidArguments;
    }

    if (findDuplicateAlias(file_names)) |dup| {
        printUsage();
        printError("output file names map to the same import alias '{s}' for multiple --file-name options\n", .{dup});
        return error.InvalidArguments;
    }

    if (findReservedAlias(file_names)) |alias| {
        printUsage();
        printError("output file name maps to import alias '{s}', which the generated client reserves\n", .{alias});
        return error.InvalidArguments;
    }

    return .{
        .args = .{
            .input_path = input_path.?,
            .output_path = output_path,
            .base_url = base_url,
            .resource_wrappers = resource_wrappers,
            .models_only = models_only,
            .multiple_files = multiple_files,
            .file_names = file_names,
        },
    };
}

fn parseResourceWrapperMode(value: []const u8) ?ResourceWrapperMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "tags")) return .tags;
    if (std.mem.eql(u8, value, "paths")) return .paths;
    if (std.mem.eql(u8, value, "hybrid")) return .hybrid;
    return null;
}

test "parse generate supports models-only flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--models-only",
    };

    const parsed = try parse(&argv);

    try std.testing.expect(parsed.args.models_only);
    try std.testing.expectEqualStrings("openapi.json", parsed.args.input_path);
}

test "parse generate defaults to complete output" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
    };

    const parsed = try parse(&argv);

    try std.testing.expect(!parsed.args.models_only);
}

test "parse upgrade" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "upgrade",
    };

    const parsed = try parse(&argv);

    try std.testing.expect(parsed.upgrade);
}

test "parse generate supports multiple-files flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
    };

    const parsed = try parse(&argv);

    try std.testing.expect(parsed.args.multiple_files);
    try std.testing.expectEqualStrings("openapi.json", parsed.args.input_path);
}

test "parse generate silently ignores --sse-buffer flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--sse-buffer",
        "large",
    };

    const parsed = try parse(&argv);

    try std.testing.expectEqualStrings("openapi.json", parsed.args.input_path);
}

test "parse generate supports --file-name overrides" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=types.zig",
        "--file-name",
        "runtime=http.zig",
    };

    const parsed = try parse(&argv);

    try std.testing.expectEqualStrings("types.zig", parsed.args.file_names.models.?);
    try std.testing.expectEqualStrings("http.zig", parsed.args.file_names.runtime.?);
    try std.testing.expect(parsed.args.file_names.client == null);
    try std.testing.expect(parsed.args.multiple_files);
}

test "parse rejects --file-name with unknown kind" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "foo=bar.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name without equals sign" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name with empty name" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects duplicate --file-name for same kind" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=a.zig",
        "--file-name",
        "models=b.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name overrides mapping to the same file" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=foo.zig",
        "--file-name",
        "runtime=foo.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name override that collides with another kind default" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=runtime.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name without --multiple-files" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--file-name",
        "models=types.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name with absolute path" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=/etc/passwd.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name with parent traversal" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=../escape.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "validateFileName accepts simple relative names" {
    try validateFileName("types.zig");
    try validateFileName("gen/models.zig");
}

test "validateFileName rejects absolute paths" {
    try std.testing.expectError(error.InvalidFileName, validateFileName("/etc/passwd"));
}

test "validateFileName rejects parent traversal" {
    try std.testing.expectError(error.InvalidFileName, validateFileName("../escape.zig"));
    try std.testing.expectError(error.InvalidFileName, validateFileName("a/../b.zig"));
}

test "validateFileName rejects empty, dot, and dot-relative parts" {
    try std.testing.expectError(error.InvalidFileName, validateFileName("."));
    try std.testing.expectError(error.InvalidFileName, validateFileName("./foo.zig"));
    try std.testing.expectError(error.InvalidFileName, validateFileName("//foo.zig"));
    try std.testing.expectError(error.InvalidFileName, validateFileName("foo/"));
    try std.testing.expectError(error.InvalidFileName, validateFileName("foo\\"));
}

test "deriveAlias returns the file stem as the import alias" {
    const alias = try deriveAlias(std.testing.allocator, "types.zig", "models");
    defer std.testing.allocator.free(alias);
    try std.testing.expectEqualStrings("types", alias);
}

test "deriveAlias sanitizes non-identifier characters in the stem" {
    const alias = try deriveAlias(std.testing.allocator, "my-types.zig", "models");
    defer std.testing.allocator.free(alias);
    try std.testing.expectEqualStrings("my_types", alias);
}

test "deriveAlias prefixes underscore when the stem starts with a digit" {
    const alias = try deriveAlias(std.testing.allocator, "1types.zig", "models");
    defer std.testing.allocator.free(alias);
    try std.testing.expectEqualStrings("_1types", alias);
}

test "deriveAlias handles file names without an extension" {
    const alias = try deriveAlias(std.testing.allocator, "models", "models");
    defer std.testing.allocator.free(alias);
    try std.testing.expectEqualStrings("models", alias);
}

test "deriveAlias falls back to the kind name when the stem is empty" {
    const alias = try deriveAlias(std.testing.allocator, ".zig", "runtime");
    defer std.testing.allocator.free(alias);
    try std.testing.expectEqualStrings("runtime", alias);
}

test "deriveAlias prefixes underscore for reserved Zig keywords" {
    const alias = try deriveAlias(std.testing.allocator, "if.zig", "models");
    defer std.testing.allocator.free(alias);
    try std.testing.expectEqualStrings("_if", alias);
}

test "parse rejects --file-name overrides mapping to the same import alias" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=my-models.zig",
        "--file-name",
        "runtime=my_models.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name override mapping to the reserved std alias" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=std.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name override mapping to a discard-only alias" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=-.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}

test "parse rejects --file-name overrides that differ only by case" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=Types.zig",
        "--file-name",
        "runtime=types.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(&argv));
}
