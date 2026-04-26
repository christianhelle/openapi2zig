const std = @import("std");
const v2 = @import("generated_v2.zig");
const v3 = @import("generated_v3.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print("Generated models build and run !!\n", .{});
    std.debug.print("Testing memory management in generated functions...\n", .{});

    if (v3.getPetById(allocator, io, "1")) |pet3| {
        std.debug.print("Found Pet v3 with ID:{any}\n\n", .{pet3.id});
    } else |err| {
        std.debug.print("Failed to get Pet v3: {any}\n", .{err});
    }

    if (v2.getPetById(allocator, io, 1)) |pet2| {
        std.debug.print("Found Pet v2 with ID:{any}\n\n", .{pet2.id});
    } else |err| {
        std.debug.print("Failed to get Pet v2: {any}\n", .{err});
    }
}
