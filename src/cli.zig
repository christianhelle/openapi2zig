const std = @import("std");
const version_info = @import("build_info");

pub const ResourceWrapperMode = enum {
    none,
    tags,
    paths,
    hybrid,
};

pub const CliArgs = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    resource_wrappers: ResourceWrapperMode = .paths,
    models_only: bool = false,
};

pub const ParsedArgs = struct {
    args: CliArgs,
    upgrade: bool = false,
    help: bool = false,
};

pub fn parse(args: []const [:0]const u8) !ParsedArgs {
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--upgrade")) {
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
            .resource_wrappers = resource_wrappers,
            .models_only = models_only,
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
        \\   -o, --output <path>        Path to the output file path for the generated Zig code
        \\                              (default: generated.zig)
        \\   --base-url <url>           Base URL for the API client.
        \\                              (default: server URL from OpenAPI Specification)
        \\   --resource-wrappers <mode> Generate resource wrappers: none, tags, paths, hybrid.
        \\                              (default: paths)
        \\   --models-only              Generate only Zig models, skipping the API client.
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
