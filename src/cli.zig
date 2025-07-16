const std = @import("std");

pub const CliArgs = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
};

pub const ParsedArgs = struct {
    args: CliArgs,
    raw: [][:0]u8,
};

pub fn parse(allocator: std.mem.Allocator) !ParsedArgs {
    const args = try std.process.argsAlloc(allocator);

    if (args.len < 4) {
        std.process.argsFree(allocator, args[0..]);
        printUsage();
        return error.InvalidArguments;
    }

    if (!std.mem.eql(u8, args[1], "generate")) {
        std.process.argsFree(allocator, args[0..]);
        printUsage();
        return error.InvalidArguments;
    }

    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) {
                std.process.argsFree(allocator, args[0..]);
                printUsage();
                return error.InvalidArguments;
            }
            input_path = args[i];
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) {
                std.process.argsFree(allocator, args[0..]);
                printUsage();
                return error.InvalidArguments;
            }
            output_path = args[i];
        }
    }

    if (input_path == null) {
        std.process.argsFree(allocator, args[0..]);
        printUsage();
        return error.InvalidArguments;
    }

    return ParsedArgs{
        .args = CliArgs{
            .input_path = input_path.?,
            .output_path = output_path,
        },
        .raw = args,
    };
}

fn printUsage() void {
    std.debug.print("\nUsage: openapi2zig generate -i <path_to_openapi_json> -o <output_path (optional)>\n\n", .{});
}
