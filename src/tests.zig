// Import all test modules to ensure they're included in the test suite
const openapi_v3_tests = @import("tests/openapi_v3_tests.zig");
const swagger_v2_tests = @import("tests/swagger_v2_tests.zig");
const unified_converter_tests = @import("tests/unified_converter_tests.zig");
const comprehensive_converter_tests = @import("tests/comprehensive_converter_tests.zig");

// This file serves as the main test entry point that imports all test modules.
// All tests from the imported modules will be discovered and run by `zig build test`.

comptime {
    // Force inclusion of test modules
    _ = openapi_v3_tests;
    _ = swagger_v2_tests;
    _ = unified_converter_tests;
    _ = comprehensive_converter_tests;
}
