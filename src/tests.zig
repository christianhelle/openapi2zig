const openapi_v3_tests = @import("tests/openapi_v3_tests.zig");
const openapi_v31_tests = @import("tests/openapi_v31_tests.zig");
const openapi_v32_tests = @import("tests/openapi_v32_tests.zig");
const swagger_v2_tests = @import("tests/swagger_v2_tests.zig");
const unified_converter_tests = @import("tests/unified_converter_tests.zig");
const comprehensive_converter_tests = @import("tests/comprehensive_converter_tests.zig");
const identifier_generation_tests = @import("tests/identifier_generation_tests.zig");
const test_input_loader = @import("tests/test_input_loader.zig");
comptime {
    _ = openapi_v3_tests;
    _ = openapi_v31_tests;
    _ = openapi_v32_tests;
    _ = swagger_v2_tests;
    _ = unified_converter_tests;
    _ = comprehensive_converter_tests;
    _ = identifier_generation_tests;
    _ = test_input_loader;
}
