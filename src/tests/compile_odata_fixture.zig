const std = @import("std");
const sdk = @import("odata_fixture");

/// Reference every declaration, descending into nested containers. Generated
/// resource wrappers put their functions inside nested structs, and a
/// non-recursive pass stops at the top level and leaves those bodies unchecked.
fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        const field = @field(T, decl);
        if (@TypeOf(field) == type) {
            switch (@typeInfo(field)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(field),
                else => {},
            }
        }
        _ = &field;
    }
}

test "OData-shaped description generates code that compiles" {
    @setEvalBranchQuota(50_000_000);
    refAllDeclsRecursive(sdk);
}
