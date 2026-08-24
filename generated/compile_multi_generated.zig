const std = @import("std");

const multi_v3 = @import("multi/client.zig");
const multi_runtime = @import("multi/runtime.zig");
const mc_tag = @import("multiple-clients/tag/client.zig");
const mc_endpoint = @import("multiple-clients/endpoint/client.zig");
const lmstudio_multi = @import("lmstudio-multi/api.zig");

test "multi-file generated clients compile" {
    std.testing.refAllDecls(multi_v3);
    std.testing.refAllDecls(multi_runtime);
    std.testing.refAllDecls(mc_tag);
    std.testing.refAllDecls(mc_endpoint);
    std.testing.refAllDecls(lmstudio_multi);
}
