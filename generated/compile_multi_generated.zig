const std = @import("std");

const multi_v3 = @import("multi/client.zig");
const mc_tag = @import("multiple-clients/tag/client.zig");
const mc_endpoint = @import("multiple-clients/endpoint/client.zig");

test "multi-file generated clients compile" {
    std.testing.refAllDecls(multi_v3);
    std.testing.refAllDecls(mc_tag);
    std.testing.refAllDecls(mc_endpoint);
}
