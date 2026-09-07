const std = @import("std");
const cli = @import("cli.zig");
const generator = @import("generator.zig");
const upgrade = @import("upgrade.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var parsed_args = cli.parse(init.arena.allocator(), args) catch std.process.exit(1);
    defer parsed_args.deinit(init.arena.allocator());
    if (parsed_args.usage_error) {
        // Usage text was printed for a bad command line. Exiting 0 here made
        // a mistyped invocation look successful to scripts and CI.
        std.process.exit(2);
    }

    if (parsed_args.help) {
        return;
    }

    if (parsed_args.upgrade) {
        upgrade.run(allocator, io, init.environ_map) catch return;
        return;
    }

    generator.generateCode(allocator, io, parsed_args.args) catch |err| {
        // Print one line and exit rather than returning the error, which makes
        // Zig dump a stack trace through std internals for ordinary mistakes.
        cli.printError("{s} ({t})\n", .{ cli.describeError(err), err });
        std.process.exit(1);
    };
}
