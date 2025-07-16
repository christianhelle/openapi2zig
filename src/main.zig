const cli = @import("cli.zig");
const generator = @import("generator.zig");
const models = @import("models.zig");

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parsed_args = cli.parse(allocator) catch {
        return;
    };
    defer std.process.argsFree(allocator, parsed_args.raw[0..]);

    generator.generateCode(allocator, parsed_args.args.input_path, parsed_args.args.output_path) catch |err| {
        std.debug.print("Error generating OpenAPI code: {any}\n", .{err});
        return err;
    };
}
