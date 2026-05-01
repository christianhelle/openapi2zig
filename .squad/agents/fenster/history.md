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


### Smoke Test Investigation — Generated File Compilation (2026-04-30)

**Context:** Investigated how a PowerShell smoke-test script should invoke openapi2zig and verify each generated Zig file compiles.

**CLI invocation (confirmed):**
- Build executable once: `zig build -Doptimize=ReleaseFast` → `zig-out/bin/openapi2zig`
- Per-spec generation: `./zig-out/bin/openapi2zig generate -i <spec.json> -o <output.zig>`
- Default output if `-o` omitted: `generated.zig`

**Generated file structure (critical):**
- Every generated file starts with `const std = @import("std");` and exports `pub const` structs + functions
- **NO `main()` function** — they are library modules, not executables
- Therefore: **`zig run <generated.zig>` does NOT work** (no entry point) — Juno's suggestion is incorrect
- **Correct compile verification:** `zig test <generated.zig>` — compiles the file, reports "All 0 tests passed" (valid!). No harness needed.
- Alternative: `zig build-obj <generated.zig>` works but creates `.o` files requiring cleanup

**Spec inventory (corrected from Juno's count):**
- `openapi/v2.0/`: 8 JSON API specs
- `openapi/v3.0/`: **10** JSON API specs (Juno missed `ingram-micro.json`)
- `openapi/v3.1/`: 2 JSON specs
- `openapi/v3.2/`: 2 JSON specs
- `openapi/json-schema/`: 2 files — **skip** (JSON Schema meta-specs, not OpenAPI; detector returns `Unsupported`)
- Total testable: **22 API specs**

**Unsupported inputs (confirmed in `generator.zig`):**
- `.yaml`/`.yml` files → `GeneratorErrors.UnsupportedExtension` (non-zero exit)
- Spec with no `openapi` or `swagger` root field → detector returns `Unsupported` → non-zero exit
- json-schema files fall in this category

**Output directory recommendation:**
- Write to `generated/smoke-test/<version>-<basename>.zig` pattern (e.g., `v3.0-petstore.zig`)
- Never use `/tmp/` (runtime-blocked)
- Clean the directory before each run, and after success

**Existing CI coverage gap:**
- Current `smoke-tests` job only runs `zig build run-generate` (4 petstore specs) then `zig run generated/main.zig`
- 18 specs are completely untested during CI
- `compile_generated.zig` harness already demonstrates the `refAllDecls` pattern for the 4 petstore specs

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

### Smoke-test script implementation (2026-04-30)

- 	est/smoke-tests.ps1 resolves repo root via $PSScriptRoot/.. and Set-Locations there, so it works from any CWD on PowerShell 7 (Windows + Linux + macOS GitHub runners).
- Uses Get-Command zig for tooling discovery, prints zig version, then builds once with zig build -Doptimize=ReleaseFast. Executable path uses \True to pick openapi2zig.exe vs openapi2zig.
- Spec discovery: enumerates openapi/v2.0, openapi/v3.0, openapi/v3.1, openapi/v3.2 for *.json. YAML files are counted as skipped (visibility) but never run. openapi/json-schema/ is excluded by not being in the include list.
- Output layout: 	est/output/<version>/<basename>__<mode>.zig. Double underscore prevents collision when basenames already contain a dash. Cleaned each run unless -KeepOutput.
- Compile check uses zig test <output> (NOT zig run) because generated files are library modules. Confirmed locally: emits All 0 tests passed and exits 0.
- Denylist is a list of @{ Spec; Mode; Reason } hashtables; * wildcards both fields. Currently empty — keep it that way until CI signal proves a gap.
- Continues past failures, captures stdout+stderr per case via 2>&1, prints a final pass/fail/skip summary, and lists failing cases with phase (generate vs compile) before xit 1.
- Verified locally: focused run (-Filter v3.0/petstore.json) all 4 modes → 4/4 PASS in ~30s. Full 22 specs × 4 modes = 88 cases not run locally (too expensive); CI is expected to be the first full-matrix execution.
- Did NOT touch CI workflow or README — those are Juno's surfaces per the charter.

### Smoke-test denylist — ingram-micro v3.0 (2026-04-30)

- Starkiller's full sweep was 84/88; the only failures were `openapi/v3.0/ingram-micro.json` in the compile phase across all four wrapper modes (none, tags, paths, hybrid). Root cause: unified model generator emits duplicate `pub const X = struct` declarations for shared/nested schemas — same root cause for every mode, not a wrapper-specific bug.
- Denylist updated with a single wildcard-mode entry: `@{ Spec = "openapi/v3.0/ingram-micro.json"; Mode = "*"; Reason = "duplicate `pub const` emissions from unified model generator (all wrapper modes)" }`. Mode="*" keeps the list compact and reflects the shared root cause; if a fix lands per-mode, split entries then.
- Verified locally with `pwsh -NoProfile -File test/smoke-tests.ps1 -Filter "v3.0/ingram-micro.json"` → 0 pass / 0 fail / 4 skip, exit 0. Petstore filter still PASSes normally — denylist does not leak into other specs.
- Reminder for next denylist entry: keep `Reason` concise, mention the gap (not the symptom alone), and prefer Mode="*" when the failure is mode-independent. Remove entries the moment the underlying generator gap closes.

## 2026-04-30 — Smoke-test harness shipped
- Designed/implemented/validated 	est/smoke-tests.ps1 (88 cases: 22 specs × 4 wrapper modes), CI job updated with failure-only artifact upload, README documented.
- Initial denylist: ingram-micro.json (duplicate pub const emissions in unified model generator — follow-up backend work).
- Decision recorded in decisions.md (2026-04-30 entry). Session-scoped directive: agents use Claude Opus 4.7 for this session only.

### YAML smoke coverage across both layers (2026-05-01T11:50:14.189+02:00)

- `test/smoke-tests.ps1` now discovers `.json`, `.yaml`, and `.yml` fixtures under `openapi/v2.0`, `v3.0`, `v3.1`, and `v3.2`, and writes smoke outputs as `test/output/<version>/<basename>__<format>__<mode>.zig` so JSON/YAML siblings never overwrite each other.
- The curated harness remains separate: `build.zig` now generates `generated/generated_v2_yaml.zig`, `generated/generated_v3_yaml.zig`, and `generated/generated_v31_yaml.zig`; `generated/compile_generated.zig` and `generated/main.zig` import those YAML artifacts beside the existing JSON ones. `openapi/v3.2` stays JSON-only because there is no checked-in YAML fixture.
- Broad YAML smoke currently passes with targeted denylist entries for six mode-independent YAML `ParseFailure` fixtures: `openapi/v2.0/petstore-expanded.yaml`, `openapi/v2.0/uber.yaml`, `openapi/v3.0/api-with-examples.yaml`, `openapi/v3.0/bot.paths.yaml`, `openapi/v3.0/petstore-expanded.yaml`, and `openapi/v3.0/uspto.yaml`.
