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

### PR #46 documentation verification (2026-04-28T23:01:58.137+02:00)

**Verification result:** README and docs now match the current generated runtime shape after a small correction. Static checks compared `README.md` and `docs/index.html` against `src/cli.zig`, `src/generator.zig`, `generated/generated_v2.zig`, `generated/generated_v3.zig`, `generated/generated_v31.zig`, `generated/generated_v32.zig`, `generated/compile_generated.zig`, and `generated/main.zig`.

**Blocked validations:** `zig version`, `zig build run-generate`, `zig build test`, `zig test generated\compile_generated.zig`, and `zig build-exe generated\main.zig -fno-emit-bin` are blocked locally because `C:\Users\chris\AppData\Local\Microsoft\WinGet\Links\zig.exe` fails to start with "No application is associated with the specified file for this operation."

**Docs fixed:** `README.md` had invalid Zig string literals in the generated-code calling example because `\n` escapes had become literal line breaks inside strings. `docs/index.html` now names `ParseErrorResponse` and describes raw/typed SSE plus OpenAI stream helpers consistently with the PR #46 acceptance criteria.

### Input Loader Testing Strategy (2026-03-20)

**Test File:** `src/tests/test_input_loader.zig`

**Hybrid Testing Approach (Per Lando's Architecture):**
- **Unit tests:** Fast, deterministic, no network dependencies
  - Mock/error scenarios with unreachable IPs (192.0.2.1 - RFC 5737)
  - File path validation and error handling
  - Memory leak detection on all code paths
- **Integration tests:** Validate real-world HTTP functionality
  - Marked to skip in development via `SKIP_INTEGRATION_TESTS` env var
  - Test against public OpenAPI endpoints (petstore3.swagger.io, petstore.swagger.io)
  - Verify full pipeline: fetch → parse → convert → generate

**Both-Spec Validation:**
- Every test covers BOTH v2.0 (Swagger) AND v3.0 (OpenAPI)
- File-based and URL-based loading tested for both versions
- Side-by-side comparison ensures consistency between file and URL sources
- Full pipeline tests: load → detect version → parse → validate structure

**HTTP Client API (Zig 0.15.2):**
- Uses `std.http.Client.request()` API (not `.fetch()`)
- Pattern: `client.request()` → `sendBodiless()` → `receiveHead()` → `reader.readAlloc()`
- Proper error handling for: invalid URL, connection failure, 404, timeouts
- Memory ownership: caller owns returned body, must free with `allocator.free()`

**Memory Management:**
- All tests use `test_utils.createTestAllocator()` for leak detection
- Comprehensive `defer` cleanup on all code paths
- Tests verify no leaks even on error paths
- Switch statements must handle `.Unsupported` version case

**Edge Cases Covered:**
- Large file handling (api-with-examples.json ~6KB)
- Non-existent files and URLs
- Invalid URL schemes (ftp://, file://)
- Connection timeouts (unreachable IPs)
- HTTP 404 responses
- Malformed URLs
- Empty response bodies

**Integration Test Design:**
- Tests skip via environment variable: `SKIP_INTEGRATION_TESTS=1`
- Real endpoints tested:
  - `https://petstore3.swagger.io/api/v3/openapi.json` (v3.0)
  - `https://petstore.swagger.io/v2/swagger.json` (v2.0)
- Verify network fetch produces same parseable structure as file load
- Full validation chain ensures end-to-end correctness

**Test Organization:**
- Logical sections with clear comments
- Unit tests first (fast feedback)
- Integration tests last (skip in dev)
- Each test has descriptive name and focused scope
- Tests validate both positive and negative cases

*To be updated as the team works.*
