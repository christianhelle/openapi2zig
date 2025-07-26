const std = @import("std");
const v2 = @import("generated_v2.zig");
const v3 = @import("generated_v3.zig");

pub fn main() !void {
    std.debug.print("Generated models build and run !!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    try v3.getPetById(allocator, 0);
}
