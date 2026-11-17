// The OAuth runtime is copied into generated SDKs. It has its own tests, which
// run here so that a broken copy never ships.
test {
    _ = @import("../generators/sdk/auth_runtime.zig");
}
