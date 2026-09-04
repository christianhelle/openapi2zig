const std = @import("std");

const github_client = @import("github/client.zig");
const github_models = @import("github/models.zig");
const github_runtime = @import("github/runtime.zig");

/// Reference every declaration, descending into nested containers. Generated
/// resource wrappers put their functions inside nested structs, and a
/// non-recursive pass stops at the top level and leaves those bodies unchecked.
fn refAllDeclsRecursive(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        const field = @field(T, decl.name);
        if (@TypeOf(field) == type) {
            switch (@typeInfo(field)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(field),
                else => {},
            }
        }
        _ = &field;
    }
}

test "example clients compile" {
    @setEvalBranchQuota(10_000_000);
    refAllDeclsRecursive(github_client);
    refAllDeclsRecursive(github_models);
    refAllDeclsRecursive(github_runtime);
}
