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

