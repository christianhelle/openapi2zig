## Project Context

**Project:** openapi2zig — CLI tool for generating type-safe Zig API clients from OpenAPI/Swagger specs  
**User:** Christian Helle  
**Tech Stack:** Zig v0.15.2, OpenAPI v3.0, Swagger v2.0  
**Architecture:** Unified converter pattern (parse → normalize → generate)

## Testing Focus

- **Test framework:** xUnit v3 style with `test_utils.createTestAllocator()`
- **Memory validation:** All tests use allocator that detects leaks
- **Both-spec coverage:** Tests MUST work with BOTH Swagger v2.0 AND OpenAPI v3.0
- **Sample fixtures:** `openapi/v2.0/petstore.json` and `openapi/v3.0/petstore.json`
- **Generated code validation:** `zig run generated/main.zig` must output "Generated models build and run !!"
- **Memory cleanup pattern:** Always `defer parsed.deinit(allocator)` after parsing

## Test Infrastructure

- Test file locations: `src/tests/` directory structure
- Coverage areas: Parsing, conversion, code generation, both spec versions
- Edge cases: Optional fields, required fields, different data types, nested schemas

## Learnings

*To be updated as the team works.*
