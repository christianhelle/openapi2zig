const std = @import("std");

const per_tag = @import("generated_v3_per_tag.zig");
const per_endpoint = @import("generated_v3_per_endpoint.zig");

test "multiple-clients generated files compile" {
    std.testing.refAllDecls(per_tag);
    std.testing.refAllDecls(per_endpoint);
}
