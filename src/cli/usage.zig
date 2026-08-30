const std = @import("std");
const version_info = @import("build_info");

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
