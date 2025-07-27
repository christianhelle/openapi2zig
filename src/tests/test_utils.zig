const std = @import("std");
pub fn createTestAllocator() std.heap.GeneralPurposeAllocator(.{}) {
    return std.heap.GeneralPurposeAllocator(.{}){};
}
