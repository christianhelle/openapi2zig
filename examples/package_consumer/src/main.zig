const openapi2zig = @import("openapi2zig");

pub fn main() void {
    const args = openapi2zig.CliArgs{
        .input_path = "api.json",
        .output_path = null,
        .base_url = null,
    };

    _ = args;
    _ = openapi2zig.version_info.VERSION;
}
