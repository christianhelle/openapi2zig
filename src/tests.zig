const openapi_v3_tests = @import("tests/openapi_v3_tests.zig");
const swagger_v2_tests = @import("tests/swagger_v2_tests.zig");
const unified_converter_tests = @import("tests/unified_converter_tests.zig");
const comprehensive_converter_tests = @import("tests/comprehensive_converter_tests.zig");
comptime {
    _ = openapi_v3_tests;
    _ = swagger_v2_tests;
    _ = unified_converter_tests;
    _ = comprehensive_converter_tests;
}
