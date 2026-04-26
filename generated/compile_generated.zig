const std = @import("std");

const v2 = @import("generated_v2.zig");
const v3 = @import("generated_v3.zig");
const v31 = @import("generated_v31.zig");
const v32 = @import("generated_v32.zig");

test "generated clients compile" {
    std.testing.refAllDecls(v2);
    std.testing.refAllDecls(v3);
    std.testing.refAllDecls(v31);
    std.testing.refAllDecls(v32);
}
