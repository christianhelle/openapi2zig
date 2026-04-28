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
- Code generation patterns: Structs with optional fields use `?T = null` pattern; standard HTTP client with proper cleanup

## Learnings

### HTTP Client Integration in Zig 0.15.2 (2025-01-17)

**HTTP Request Pattern:**
- Use `std.http.Client{ .allocator = allocator }` for initialization
- Call `client.request(method, uri, options)` to create a request (takes 3 args, not 4)
- Use `req.sendBodiless()` for GET requests
- Call `req.receiveHead(&redirect_buffer)` to get response headers
- Access status via `response.head.status`
- Get reader with `response.reader(&transfer_buffer)` for body reading

**Response Body Reading:**
- `reader.allocRemaining(allocator, std.io.Limit.limited(max_bytes))` for bounded allocation
- Returns `[]const u8` owned by allocator - caller must free
- `std.io.Limit.limited(n)` wraps a size limit, NOT a raw integer
- Transfer buffer size (4096 bytes) balances memory vs performance

**Memory Safety:**
- All HTTP allocations go through provided allocator (no global state)
- Body ownership transferred to caller via return value
- No cleanup needed on error paths (allocator handles failed allocations)
- Existing `defer allocator.free(contents)` pattern in generator.zig remains unchanged

**Edge Cases:**
- OpenAPI specs from public URLs may be updated (version strings change)
- Test brittleness: external API tests should use version-agnostic assertions
- 10MB size limit reasonable for OpenAPI specs (typical: 10-500KB)


### PR #46 generated-code documentation brief (2026-04-28T23:01:58.137+02:00)

- PR #46 (`Fix real-world OpenAPI code generation`, merge `4e8bc19`) substantially changed the generated output contract: generated files now start with `const std = @import("std");`, model declarations, then a reusable API runtime and endpoint/resource wrappers.
- Current CLI usage is `openapi2zig generate -i <PATH_OR_URL> [-o <file>] [--base-url <url>] [--resource-wrappers none|tags|paths|hybrid]`; default output file is `generated.zig`, and resource wrappers default to `paths`.
- Build sample generation now emits four files: `generated/generated_v2.zig`, `generated/generated_v3.zig`, `generated/generated_v31.zig`, and `generated/generated_v32.zig`; `generated/compile_generated.zig` refAllDecls all four and tests generated runtime helpers.
- Generated clients use `Client.init(allocator, io, api_key)`, borrowed `default_headers`, optional `organization`/`project`, bearer auth, and `withBaseUrl()` override. Endpoint calls take `client: *Client`, not allocator/io directly.
- Successful parsed responses return `Owned(T)` with `deinit()` and `value()`; low-level `RawResponse`, `ParseErrorResponse`, and `ApiResult(T)` preserve response status/body and parse failures. Endpoint families are `op()`, `opRaw()`, and `opResult()` when a return type exists.
- Generated runtime includes percent-encoded query helper functions, optional query params as nullable `?T`, `.ignore_unknown_fields = true` response parsing, dynamic raw JSON helpers, and bounded SSE parsing plus typed SSE callbacks.
- Generated models now quote invalid/reserved Zig identifiers, emit object schemas as structs, required fields without defaults, optional fields as `?T = null`, arrays as `[]const T` when known, and `std.json.Value` only for genuinely ambiguous/open JSON shapes.
- OpenAPI 3.1 conversion merges `allOf` object/ref object properties, preserves `oneOf`/`anyOf` variants/discriminators in the unified schema, and supports nullable unions collapsing to `?T`.
- Union output can be `union(enum)` with typed variants and `raw: std.json.Value` fallback, including discriminator unions, structural trial-parse unions, primitive mixed unions, and string enum variants. Unsafe discriminator cases still fall back with a comment.
- OpenAI-specific generation hooks exist for `extra_body` flattening on `CreateResponse`/`CreateChatCompletionRequest`, `reasoning_details` on assistant messages, JSON-value-backed schema unions, typed filters/tools/annotations/audio, and stream helpers `streamChatCompletion`/`streamResponse`.
- README is stale around usage and examples: it still says CLI generation is under development, describes `-o` as output directory, and shows old no-Client API examples returning bare values/dangling parsed data.
- Current local environment cannot run Zig because `C:\Users\chris\AppData\Local\Microsoft\WinGet\Links\zig.exe` fails to launch; source inspection and checked-in generated files were used instead of regenerating locally.
