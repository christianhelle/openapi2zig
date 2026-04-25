const std = @import("std");
const cli = @import("cli.zig");
const generator = @import("generator.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const parsed_args = cli.parse(args) catch std.process.exit(1);

    generator.generateCode(allocator, io, parsed_args.args) catch |err| {
        std.debug.print("Error generating OpenAPI code: {}\n", .{err});
        return err;
    };
}
