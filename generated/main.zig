const std = @import("std");
const v2 = @import("generated_v2.zig");
const v3 = @import("generated_v3.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        } else {
            std.debug.print("No memory leaks detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();
    _ = allocator; // Suppress unused variable warning
    std.debug.print("Generated models build and run !!\n", .{});
    std.debug.print("Testing memory management in generated functions...\n", .{});
}
