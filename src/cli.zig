const std = @import("std");
const version_info = @import("build_info");

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
    const names = [_]?[]const u8{ file_names.models, file_names.runtime, file_names.client };
    var i: usize = 0;
    while (i < names.len) : (i += 1) {
        const first = names[i] orelse continue;
        var j = i + 1;
        while (j < names.len) : (j += 1) {
            const second = names[j] orelse continue;
            if (std.mem.eql(u8, first, second)) return first;
        }
    }
    return null;
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
                std.debug.print("\nError: OpenAPI spec path or URL required\n", .{});
                return error.InvalidArguments;
            }
            input_path = args[i];
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                std.debug.print("\nError: output path required\n", .{});
                return error.InvalidArguments;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--base-url")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                std.debug.print("\nError: base URL required\n", .{});
                return error.InvalidArguments;
            }
            base_url = args[i];
        } else if (std.mem.eql(u8, arg, "--resource-wrappers")) {
            i += 1;
            if (i >= args.len) {
                printUsage();
                std.debug.print("\nError: resource wrapper mode required\n", .{});
                return error.InvalidArguments;
            }
            resource_wrappers = parseResourceWrapperMode(args[i]) orelse {
                printUsage();
                std.debug.print("\nError: invalid resource wrapper mode '{s}'\n", .{args[i]});
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
                std.debug.print("\nError: --file-name value required\n", .{});
                return error.InvalidArguments;
            }
            const value = args[i];
            const eq = std.mem.indexOfScalar(u8, value, '=') orelse {
                printUsage();
                std.debug.print("\nError: invalid --file-name value '{s}', expected format <kind>=<name>\n", .{value});
                return error.InvalidArguments;
            };
            const kind = FileKind.fromString(value[0..eq]) orelse {
                printUsage();
                std.debug.print("\nError: invalid file kind '{s}', expected models, runtime, or client\n", .{value[0..eq]});
                return error.InvalidArguments;
            };
            if (eq + 1 >= value.len) {
                printUsage();
                std.debug.print("\nError: empty file name for kind '{s}'\n", .{value[0..eq]});
                return error.InvalidArguments;
            }
            file_names.set(kind, value[eq + 1 ..]) catch {
                printUsage();
                std.debug.print("\nError: duplicate --file-name for kind '{s}'\n", .{value[0..eq]});
                return error.InvalidArguments;
            };
        }
    }

    if (input_path == null) {
        printUsage();
        std.debug.print("\nError: OpenAPI spec path or URL required\n", .{});
        return error.InvalidArguments;
    }

    if (!multiple_files and file_names.any()) {
        printUsage();
        std.debug.print("\nError: --file-name requires --multiple-files\n", .{});
        return error.InvalidArguments;
    }

    if (findDuplicateFileName(file_names)) |dup| {
        printUsage();
        std.debug.print("\nError: duplicate output file name '{s}' for multiple --file-name options\n", .{dup});
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

fn printUsage() void {
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
