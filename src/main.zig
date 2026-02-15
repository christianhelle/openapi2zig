const std = @import("std");
const cli = @import("cli.zig");
const generator = @import("generator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed_args = cli.parse(allocator) catch return;
    defer std.process.argsFree(allocator, parsed_args.raw[0..]);

    generator.generateCode(allocator, parsed_args.args) catch |err| {
        std.debug.print("Error generating OpenAPI code: {}\n", .{err});
        return err;
    };
}
