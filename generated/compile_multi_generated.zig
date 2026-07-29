const std = @import("std");

const multi_v3 = @import("multi/client.zig");

test "multi-file generated clients compile" {
    std.testing.refAllDecls(multi_v3);
}
