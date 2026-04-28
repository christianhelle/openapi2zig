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

### 2026-04-28T23:01:58.137+02:00 — PR #46 generated-output docs impact

- PR #46 (`Fix real-world OpenAPI code generation`) materially changed generated public API shape: generated clients now expose a `Client` object, `Owned(T)`, `RawResponse`, `ApiResult(T)`, parse-error raw preservation, raw/result endpoint helpers, default headers, query encoding, resource wrappers, and SSE helpers.
- README snippets around CLI output and generated API usage are architecturally stale. Docs must show `Client.init(...)`/`deinit`, passing `*Client` into operations, `Owned(T).deinit()`, and the `{operation}`, `{operation}Raw`, `{operation}Result` trio instead of old per-call `std.http.Client` examples.
- The unified converter pattern remains the documentation spine: version-specific parsers/converters normalize into `src/models/common/document.zig`, then `src/generators/unified/model_generator.zig` and `src/generators/unified/api_generator.zig` emit all current output.
- Docs must not overclaim YAML support. Current behavior is JSON file/URL support; YAML extension handling reports unsupported.
- OpenAPI 3.1 composite schema typing is currently richer than v3.0/v3.2: `allOf` merge plus preserved `oneOf`/`anyOf`/discriminator metadata. Docs should describe this as current behavior without implying full parity across all spec versions.
- Key files for review: `README.md`, `docs/index.html`, `docs/json-value-typing-policy.md`, `docs/openai-generation-issues.md`, `src/cli.zig`, `src/generator.zig`, `src/generators/unified/api_generator.zig`, `src/generators/unified/model_generator.zig`, `generated/generated_v3.zig`, `generated/compile_generated.zig`.
- User preference from this task: use GPT-5.5 for team agents during this session only; commit docs work in small logical groups, but Lando must not stage or commit for this review task.
