const std = @import("std");

// Helper function to create a test allocator for each test
pub fn createTestAllocator() std.heap.GeneralPurposeAllocator(.{}) {
    return std.heap.GeneralPurposeAllocator(.{}){};
}
