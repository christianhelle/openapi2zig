const std = @import("std");
const cli = @import("../cli.zig");
const ResourceWrapperMode = cli.ResourceWrapperMode;
const MultipleClientsMode = cli.MultipleClientsMode;
const FileKind = cli.FileKind;
const FileNameOverrides = cli.FileNameOverrides;
const CliArgs = cli.CliArgs;
const ParsedArgs = cli.ParsedArgs;
const parse = cli.parse;
const fileNamesCollide = cli.fileNamesCollide;
const deriveAlias = cli.deriveAlias;
const importBasename = cli.importBasename;
const importDirname = cli.importDirname;
const resolveRuntimeModulePath = cli.resolveRuntimeModulePath;
const isAbsoluteImportPath = cli.isAbsoluteImportPath;
const validateImportPath = cli.validateImportPath;
const validateFileName = cli.validateFileName;
const parseResourceWrapperMode = cli.parseResourceWrapperMode;
const parseMultipleClientsMode = cli.parseMultipleClientsMode;

test "parse generate supports models-only flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--models-only",
    };

    const parsed = try parse(std.testing.allocator, &argv);

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

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(!parsed.args.models_only);
}

test "parse upgrade" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "upgrade",
    };

    const parsed = try parse(std.testing.allocator, &argv);

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

    const parsed = try parse(std.testing.allocator, &argv);

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

    const parsed = try parse(std.testing.allocator, &argv);

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

    const parsed = try parse(std.testing.allocator, &argv);

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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime or client overrides with --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--models-only",
        "--file-name",
        "runtime=http.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse accepts models override with --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--models-only",
        "--file-name",
        "models=types.zig",
    };

    const parsed = try parse(std.testing.allocator, &argv);
    try std.testing.expectEqualStrings("types.zig", parsed.args.file_names.models.?);
}

test "parse accepts models override colliding with a default name under --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--models-only",
        "--file-name",
        "models=runtime.zig",
    };

    const parsed = try parse(std.testing.allocator, &argv);
    try std.testing.expectEqualStrings("runtime.zig", parsed.args.file_names.models.?);
}

test "parse accepts models override mapping to the reserved std alias under --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--models-only",
        "--file-name",
        "models=std.zig",
    };

    const parsed = try parse(std.testing.allocator, &argv);
    try std.testing.expectEqualStrings("std.zig", parsed.args.file_names.models.?);
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
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

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --file-name overrides colliding across separator styles" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--file-name",
        "models=dir/Types.zig",
        "--file-name",
        "runtime=DIR\\types.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "fileNamesCollide treats separator styles and case as equivalent" {
    try std.testing.expect(fileNamesCollide("dir/Types.zig", "DIR\\types.zig"));
    try std.testing.expect(fileNamesCollide("a/b.zig", "a/b.zig"));
    try std.testing.expect(!fileNamesCollide("dir/Types.zig", "dir/Other.zig"));
    try std.testing.expect(!fileNamesCollide("dir/Types.zig", "dirOther.zig"));
}

test "parse generate leaves multiple_clients unset when flag absent" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.multiple_clients == null);
}

test "parse generate defaults multiple-clients to PerTag when no value given" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.multiple_clients == .per_tag);
    try std.testing.expect(parsed.args.resource_wrappers == .none);
}

test "parse generate accepts --multiple-clients PerTag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
        "PerTag",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.multiple_clients == .per_tag);
}

test "parse generate accepts --multiple-clients PerEndpoint" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
        "PerEndpoint",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.multiple_clients == .per_endpoint);
}

test "parse generate accepts case-insensitive multiple-clients values" {
    {
        const variants = [_][:0]const u8{ "pertag", "PER_TAG", "per-tag" };
        for (variants) |variant| {
            const argv = [_][:0]const u8{
                "openapi2zig",
                "generate",
                "-i",
                "openapi.json",
                "--multiple-clients",
                variant,
            };

            const parsed = try parse(std.testing.allocator, &argv);
            try std.testing.expect(parsed.args.multiple_clients == .per_tag);
        }
    }
    {
        const variants = [_][:0]const u8{ "perendpoint", "PER_ENDPOINT", "per-endpoint" };
        for (variants) |variant| {
            const argv = [_][:0]const u8{
                "openapi2zig",
                "generate",
                "-i",
                "openapi.json",
                "--multiple-clients",
                variant,
            };

            const parsed = try parse(std.testing.allocator, &argv);
            try std.testing.expect(parsed.args.multiple_clients == .per_endpoint);
        }
    }
}

test "parse rejects --multiple-clients with an invalid mode value" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
        "bogus",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --multiple-clients with non-none resource wrappers" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
        "PerTag",
        "--resource-wrappers",
        "tags",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --multiple-clients with resource wrappers hybrid" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--resource-wrappers",
        "hybrid",
        "--multiple-clients",
        "PerEndpoint",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse accepts --multiple-clients with resource wrappers none" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
        "PerTag",
        "--resource-wrappers",
        "none",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.multiple_clients == .per_tag);
    try std.testing.expect(parsed.args.resource_wrappers == .none);
}

test "parse rejects --multiple-clients with --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-clients",
        "PerTag",
        "--models-only",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse accepts --multiple-clients with --multiple-files" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--multiple-clients",
        "PerTag",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.multiple_clients == .per_tag);
    try std.testing.expect(parsed.args.multiple_files);
}

test "CliArgs deinit does not free unowned tags" {
    var args = CliArgs{
        .input_path = "",
        .tags = &.{"Pet"},
    };

    args.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), args.tags.len);
}

test "parse generate accepts repeatable --tag flags" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--tag",
        "Pet",
        "--tag",
        "Store",
        "--tag",
        "User",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), parsed.args.tags.len);
    try std.testing.expectEqualStrings("Pet", parsed.args.tags[0]);
    try std.testing.expectEqualStrings("Store", parsed.args.tags[1]);
    try std.testing.expectEqualStrings("User", parsed.args.tags[2]);
}

test "parse generate accepts a single --tag flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--tag",
        "Pet",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.args.tags.len);
    try std.testing.expectEqualStrings("Pet", parsed.args.tags[0]);
}

test "parse generate leaves tags empty when --tag is absent" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expectEqual(@as(usize, 0), parsed.args.tags.len);
}

test "parse rejects --tag without a value" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--tag",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --tag followed by another flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--tag",
        "--models-only",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse accepts --tag with --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--models-only",
        "--tag",
        "Pet",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(parsed.args.models_only);
    try std.testing.expectEqual(@as(usize, 1), parsed.args.tags.len);
}

test "parse generate supports --force flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--force",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(parsed.args.force);
}

test "parse generate defaults force to false" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
    };

    const parsed = try parse(std.testing.allocator, &argv);

    try std.testing.expect(!parsed.args.force);
}

test "parse generate supports parameters-as-struct flag" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--parameters-as-struct",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(parsed.args.parameters_as_struct);
}

test "parse generate defaults parameters-as-struct to false" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(!parsed.args.parameters_as_struct);
}

test "parse accepts --runtime-module with --multiple-files" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../runtime.zig",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("../runtime.zig", parsed.args.runtime_module.?);
    try std.testing.expect(parsed.args.multiple_files);
}

test "parse accepts --runtime-module with nested path and custom models name" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../shared/runtime.zig",
        "--file-name",
        "models=contracts.zig",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("../shared/runtime.zig", parsed.args.runtime_module.?);
    try std.testing.expectEqualStrings("contracts.zig", parsed.args.file_names.models.?);
}

test "parse rejects --runtime-module without --multiple-files" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--runtime-module",
        "../runtime.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-module without value" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects duplicate --runtime-module" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../runtime.zig",
        "--runtime-module",
        "../other.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-module combined with --file-name runtime" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../runtime.zig",
        "--file-name",
        "runtime=custom.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-module with --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--models-only",
        "--runtime-module",
        "../runtime.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-module with absolute path" {
    const cases = [_][:0]const u8{
        "/absolute/runtime.zig",
        "C:\\absolute\\runtime.zig",
        "C:/absolute/runtime.zig",
        "\\\\server\\share\\runtime.zig",
        "C:runtime.zig",
        "C:shared\\runtime.zig",
    };
    for (cases) |path| {
        const argv = [_][:0]const u8{
            "openapi2zig",
            "generate",
            "-i",
            "openapi.json",
            "--multiple-files",
            "--runtime-module",
            path,
        };
        try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
    }
}

test "parse rejects --runtime-module mapping to reserved alias" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../std.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-module alias colliding with models alias" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../runtime.zig",
        "--file-name",
        "models=runtime.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "validateImportPath allows parent traversal and nested paths" {
    try validateImportPath("../runtime.zig");
    try validateImportPath("../../shared/runtime.zig");
    try validateImportPath("a/b/runtime.zig");
}

test "validateImportPath rejects dot segments and absolute paths" {
    try std.testing.expectError(error.InvalidFileName, validateImportPath("./runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("a//b.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("/abs/runtime.zig"));
}

test "validateImportPath rejects absolute paths on any platform" {
    try std.testing.expectError(error.InvalidFileName, validateImportPath("/abs/runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("\\abs\\runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("C:\\abs\\runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("C:/abs/runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("C:runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("C:shared\\runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("C:shared/runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("\\\\server\\share\\runtime.zig"));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("//server/share/runtime.zig"));
}

test "importBasename handles both separators" {
    try std.testing.expectEqualStrings("runtime.zig", importBasename("../runtime.zig"));
    try std.testing.expectEqualStrings("runtime.zig", importBasename("..\\runtime.zig"));
    try std.testing.expectEqualStrings("my_runtime.zig", importBasename("..\\shared\\my_runtime.zig"));
    try std.testing.expectEqualStrings("my_runtime.zig", importBasename("../shared/my_runtime.zig"));
    try std.testing.expectEqualStrings("file.zig", importBasename("file.zig"));
}

test "validateImportPath allows windows separators and parent traversal" {
    try validateImportPath("..\\runtime.zig");
    try validateImportPath("..\\shared\\runtime.zig");
    try validateImportPath("a\\b\\runtime.zig");
}

test "parse accepts windows-style runtime-module path" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "..\\shared\\runtime.zig",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("..\\shared\\runtime.zig", parsed.args.runtime_module.?);
}

test "parse rejects windows-style runtime-module alias colliding with models alias" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "..\\shared\\my_runtime.zig",
        "--file-name",
        "models=my_runtime.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "validateImportPath rejects basename dotdot" {
    try std.testing.expectError(error.InvalidFileName, validateImportPath(".."));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("a/.."));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("a\\.."));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("../.."));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("..\\.."));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("a/b/.."));
    try std.testing.expectError(error.InvalidFileName, validateImportPath("a\\b\\.."));
}

test "parse rejects --runtime-module with trailing dotdot" {
    const cases = [_][:0]const u8{ "..", "a/..", "a\\..", "../..", "..\\.." };
    for (cases) |path| {
        const argv = [_][:0]const u8{
            "openapi2zig",
            "generate",
            "-i",
            "openapi.json",
            "--multiple-files",
            "--runtime-module",
            path,
        };
        try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
    }
}

test "parse rejects runtime-module that collides with models via case-insensitive match" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "Types.zig",
        "--file-name",
        "models=types.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime-module that collides with client via case-insensitive match" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "API.ZIG",
        "--file-name",
        "client=api.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime-module resolved relative to client dir that collides with models" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../models.zig",
        "--file-name",
        "client=sub/client.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime-module resolved relative to backslash client dir" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../models.zig",
        "--file-name",
        "client=sub\\client.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime-module resolved with separator normalization" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "..\\models.zig",
        "--file-name",
        "client=sub/client.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime-module resolved case-insensitive collision with models" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../Types.zig",
        "--file-name",
        "models=types.zig",
        "--file-name",
        "client=sub/client.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects runtime-module resolved case-insensitive collision with client" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../sub/API.ZIG",
        "--file-name",
        "client=sub/api.zig",
    };
    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse accepts runtime-module that does not collide after resolution" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "-i",
        "openapi.json",
        "--multiple-files",
        "--runtime-module",
        "../runtime/runtime.zig",
        "--file-name",
        "client=sub/client.zig",
    };
    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("../runtime/runtime.zig", parsed.args.runtime_module.?);
}

test "importDirname handles both separators" {
    try std.testing.expectEqualStrings("a/b", importDirname("a/b/c.zig").?);
    try std.testing.expectEqualStrings("a\\b", importDirname("a\\b\\c.zig").?);
    try std.testing.expectEqualStrings("sub", importDirname("sub/client.zig").?);
    try std.testing.expect(importDirname("client.zig") == null);
    try std.testing.expectEqualStrings("a/b", importDirname("a/b\\c.zig").?);
}

test "resolveRuntimeModulePath normalizes dotdot segments" {
    const cases = [_]struct {
        client: []const u8,
        mod: []const u8,
        expected: []const u8,
    }{
        .{ .client = "sub/client.zig", .mod = "../models.zig", .expected = "models.zig" },
        .{ .client = "sub/client.zig", .mod = "..\\models.zig", .expected = "models.zig" },
        .{ .client = "a/b/client.zig", .mod = "../../shared/runtime.zig", .expected = "shared/runtime.zig" },
        .{ .client = "client.zig", .mod = "Types.zig", .expected = "Types.zig" },
        .{ .client = "sub/api.zig", .mod = "../sub/API.ZIG", .expected = "sub/API.ZIG" },
        .{ .client = "sub/client.zig", .mod = "../Types.zig", .expected = "Types.zig" },
    };
    for (cases) |c| {
        const resolved = try resolveRuntimeModulePath(std.testing.allocator, c.client, c.mod);
        defer std.testing.allocator.free(resolved);
        try std.testing.expectEqualStrings(c.expected, resolved);
    }
}

test "parse accepts --runtime-only without input" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "--runtime-only",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.args.runtime_only);
    try std.testing.expectEqualStrings("", parsed.args.input_path);
}

test "parse accepts --runtime-only with output and ignores input" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "--runtime-only",
        "-i",
        "openapi.json",
        "-o",
        "runtime.zig",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.args.runtime_only);
    try std.testing.expectEqualStrings("runtime.zig", parsed.args.output_path.?);
}

test "parse rejects --runtime-only with --models-only" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "--runtime-only",
        "--models-only",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-only with --runtime-module" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "--runtime-only",
        "--multiple-files",
        "--runtime-module",
        "../runtime.zig",
    };

    try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, &argv));
}

test "parse rejects --runtime-only with client-only options" {
    const cases = [_][]const [:0]const u8{
        &.{ "openapi2zig", "generate", "--runtime-only", "--multiple-clients" },
        &.{ "openapi2zig", "generate", "--runtime-only", "--tag", "pets" },
        &.{ "openapi2zig", "generate", "--runtime-only", "--base-url", "https://example.com" },
        &.{ "openapi2zig", "generate", "--runtime-only", "--parameters-as-struct" },
        &.{ "openapi2zig", "generate", "--runtime-only", "--resource-wrappers", "none" },
        &.{ "openapi2zig", "generate", "--runtime-only", "--multiple-files", "--file-name", "models=types.zig" },
        &.{ "openapi2zig", "generate", "--runtime-only", "--multiple-files", "--file-name", "client=api.zig" },
    };
    for (cases) |argv| {
        try std.testing.expectError(error.InvalidArguments, parse(std.testing.allocator, argv));
    }
}

test "parse accepts --runtime-only with --multiple-files and runtime file name" {
    const argv = [_][:0]const u8{
        "openapi2zig",
        "generate",
        "--runtime-only",
        "--multiple-files",
        "--file-name",
        "runtime=http.zig",
    };

    var parsed = try parse(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.args.runtime_only);
    try std.testing.expectEqualStrings("http.zig", parsed.args.file_names.runtime.?);
}
