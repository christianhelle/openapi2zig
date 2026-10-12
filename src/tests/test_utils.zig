const std = @import("std");

pub fn createTestAllocator() std.heap.DebugAllocator(.{}) {
    return std.heap.DebugAllocator(.{}){};
}

/// Forwards allocations to `child` but never resizes or remaps in place.
///
/// `std.testing.checkAllAllocationFailures` requires every run to make the
/// same number of allocations. Whether the testing allocator can grow a
/// buffer in place differs from run to run, which changes how often
/// containers fall back to a fresh allocation; refusing in-place growth keeps
/// the allocation count deterministic.
pub const NoResizeAllocator = struct {
    child: std.mem.Allocator,

    pub fn allocator(self: *NoResizeAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = std.mem.Allocator.noResize,
                .remap = std.mem.Allocator.noRemap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *NoResizeAllocator = @ptrCast(@alignCast(ctx));
        return self.child.rawAlloc(len, alignment, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *NoResizeAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
    }
};
