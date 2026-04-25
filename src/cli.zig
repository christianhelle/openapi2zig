const std = @import("std");
const version_info = @import("build_info");

pub const CliArgs = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
};

pub const ParsedArgs = struct {
    args: CliArgs,
};

pub fn parse(args: []const [:0]const u8) !ParsedArgs {
    if (args.len < 4) {
        printUsage();
        std.debug.print("\nError: OpenAPI spec path or URL required\n", .{});
        return error.InvalidArguments;
    }

    if (!std.mem.eql(u8, args[1], "generate")) {
        printUsage();
        std.debug.print("\nError: unknown subcommand '{s}'\n", .{args[1]});
        return error.InvalidArguments;
    }

    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var base_url: ?[]const u8 = null;

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
        }
    }

    if (input_path == null) {
        printUsage();
        std.debug.print("\nError: OpenAPI spec path or URL required\n", .{});
        return error.InvalidArguments;
    }

    return .{
        .args = .{
            .input_path = input_path.?,
            .output_path = output_path,
            .base_url = base_url,
        },
    };
}

fn printUsage() void {
    std.debug.print(
        \\
        \\ Usage: openapi2zig generate [options]
        \\ Version: {s} ({s})
        \\
        \\ Options:
        \\   -i, --input <PATH_OR_URL>  OpenAPI/Swagger spec (file path or http/https URL)
        \\   -o, --output <path>        Path to the output file path for the generated Zig code
        \\                              (default: generated.zig)
        \\   --base-url <url>           Base URL for the API client.
        \\                              (default: server URL from OpenAPI Specification)
        \\
        \\ EXAMPLES:
        \\   openapi2zig generate -i ./openapi/petstore.json -o api.zig
        \\   openapi2zig generate -i https://petstore3.swagger.io/api/v3/openapi.json -o api.zig
        \\
        \\
    , .{ version_info.VERSION, version_info.GIT_COMMIT });
}
