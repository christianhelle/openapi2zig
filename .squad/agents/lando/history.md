## Project Context

**Project:** openapi2zig — CLI tool for generating type-safe Zig API clients from OpenAPI/Swagger specs  
**User:** Christian Helle  
**Tech Stack:** Zig v0.15.2, OpenAPI v3.0, Swagger v2.0  
**Architecture:** Unified converter pattern (parse → normalize → generate)

## Key Architecture

- **Specs supported:** Swagger v2.0, OpenAPI v3.0
- **Parsing:** Version-specific models in `src/models/v2.0/` and `src/models/v3.0/`
- **Converters:** `src/generators/converters/` transforms version-specific → unified document
- **Generation:** `src/generators/unified/` generates Zig code from unified representation
- **Memory model:** Every dynamic struct has `deinit(allocator)`. **Always use `defer parsed.deinit(allocator)`.**
- **Testing:** xUnit-style with `test_utils.createTestAllocator()`, test against both v2.0 and v3.0

## Known Patterns

- Version detection happens in `src/detector.zig` by parsing JSON for `openapi` or `swagger` fields
- CLI routing in `src/cli.zig` and `src/generator.zig`
- Sample specs in `openapi/v2.0/petstore.json` and `openapi/v3.0/petstore.json` for testing
- Generated code output to `generated/main.zig` (test harness imports both versions)

## Learnings

*To be updated as the team works.*
