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

### 2026-04-30T16:31:22.685+02:00 — Smoke Test Architecture Investigation

**Scope:** Architectural proposal for integrating smoke tests into openapi2zig (spec generation + compilation verification across all 41 JSON specs).

**Findings:**

1. **Current Test Coverage Gap**
   - Only 4 specs are code-generation tested: petstore.json (v2.0, v3.0), webhook-example.json (v3.1), petstore.json (v3.2)
   - 37 additional JSON specs in openapi/ folders are never touched during CI
   - YAML files (8 files) are unsupported by the converter—should be skipped gracefully

2. **Build System Architecture**
   - `build.zig` uses hardcoded `run-generate-*` steps for stable reference specs
   - Generated code is tested via `generated/compile_generated.zig` test harness (imports 4 generated files, uses `std.testing.refAllDecls()` pattern)
   - This is correct for baseline reproducibility, but not scalable to 41 specs

3. **Reference Pattern from refitter**
   - Separate PowerShell script (`test/smoke-tests.ps1`) for spec enumeration, generation, and compilation
   - Sequential generation (one spec at a time) for clarity and error isolation
   - Continue-all policy: collect all failures and summarize at end (not fail-fast)
   - Pattern is cross-platform (runs on Windows, Linux, macOS via PowerShell Core)

4. **Proposed Architecture: PowerShell Script (NOT build.zig)**
   - Keep hardcoded `run-generate-*` steps in build.zig for determinism and caching
   - Add `test/smoke-tests.ps1` for integration testing (dynamically discovers .json specs, skips .yaml)
   - Script responsibility: enumerate → generate → verify compilation → collect failures → report summary
   - Each spec is compiled in isolation via `zig build-obj` to catch codegen errors
   - Clean integration point: smoke test runs *after* `zig build test` succeeds

5. **Architecture Rationale: Separation of Concerns**
   - **Zig build system** (deterministic, caching-friendly) handles unit tests and reference generation
   - **PowerShell** (workflow orchestration) handles dynamic spec enumeration and batch integration testing
   - **Decoupling** keeps build.zig focused on compilation; PowerShell handles discovery
   - Scalable: adding new specs requires only dropping files in openapi/; no build.zig changes

6. **Key Risks & Mitigations**
   - **Risk: Generated code may not compile in isolation** → Mitigate: verify compilation independently per spec, fail cleanly on errors
   - **Risk: YAML unsupported** → Mitigate: skip .yaml files, log as "skipped"
   - **Risk: Performance (41 specs × compile time)** → Sequential generation is intentional; can parallelize later if needed
   - **Risk: json-schema/ contains non-API specs** → Mitigate: filter to v2.0/, v3.0/, v3.1/, v3.2/ folders only

7. **CI Integration Recommendation**
   - Add optional `smoke-tests` job to `.github/workflows/ci.yml` that runs after core tests pass
   - Runs on PR and main branch (can be made conditional on full build if too slow)
   - Captures failures in artifact for visibility

8. **Clarifying Questions for Christian** (documented in proposal)
   - PowerShell on Linux CI (pwsh availability)?
   - Failure policy confirmed (continue-all, not fail-fast)?
   - File cleanup strategy (temp directory or in-memory)?
   - json-schema/ exclusion?
   - CI timing (every PR or only on main)?

**Architectural Decision:** Smoke test belongs in PowerShell (`test/smoke-tests.ps1`), not build.zig. This follows refitter's proven pattern and respects the unified converter → generation pipeline without coupling integration testing to the build system.

**Decision recorded:** `.squad/decisions/inbox/lando-smoke-test-plan.md`

### 2026-04-30T16:31:22.685+02:00 — Smoke Test Implementation Review (APPROVE)

- Reviewed Fenster's 	est/smoke-tests.ps1 + .gitignore and Juno's CI + README changes against the approved plan.
- Implementation matches all four confirmed decisions (temp denylist, all 4 wrapper modes, keep petstore harness, output under test/output/).
- Cross-platform handling is sound: repo-root via $PSCommandPath, $IsWindows for exe suffix, slash normalization after Resolve-Path -Relative, `shell: pwsh` in CI.
- CI scoping is correct: appended to existing smoke-tests job; artifact upload guarded by if: failure(); petstore harness preserved.
- Known limitation (acknowledged in plan): zig test relies on Zig's lazy analysis; deeply unused decls may escape compile-check. Acceptable for v1; can harden later with explicit efAllDeclsRecursive wrapper if generator gaps slip through.
- Reminder for staging: `test/smoke-tests.ps1` is currently untracked; it must be added in the same commit as the CI change.

## 2026-04-30 — Smoke-test harness shipped
- Designed/implemented/validated 	est/smoke-tests.ps1 (88 cases: 22 specs × 4 wrapper modes), CI job updated with failure-only artifact upload, README documented.
- Initial denylist: ingram-micro.json (duplicate pub const emissions in unified model generator — follow-up backend work).
- Decision recorded in decisions.md (2026-04-30 entry). Session-scoped directive: agents use Claude Opus 4.7 for this session only.
