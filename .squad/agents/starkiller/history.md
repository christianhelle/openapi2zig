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

### Smoke Test Coverage Design (2026-04-30)

**Task:** Design `test/smoke-tests.ps1` for PR verification — enumerate all specs under `openapi/`, generate code, compile-check each.

**Key findings:**

**Spec inventory:** 22 JSON specs are eligible: 8 in `v2.0/`, 10 in `v3.0/`, 2 in `v3.1/`, 2 in `v3.2/`. Total spec count across all YAML equivalents is ~40 files.

**Skip rules (hard):**
- All `*.yaml` / `*.yml` — YAML returns `UnsupportedExtension` from `generator.zig`; would produce 100% false failures.
- `openapi/json-schema/**` — JSON Schema meta-documents, not OpenAPI/Swagger specs.

**Compile check technique:** Generated files are library-style (no `main`). Use `zig build-lib <file> -fno-emit-bin` — compiles as static lib, skips output emit, catches type/semantic errors. Does not require a `main` function.

**CI integration note:** The existing `smoke-tests` job already exists in `.github/workflows/ci.yml` (lines 127–160) but only tests the petstore pair via `zig build run-generate`. The new script augments it — keep the petstore pair as a fast sanity check and add the PS script as a spec sweep step. `pwsh` is available on `ubuntu-latest` without extra setup.

**Risk specs:**
- `v3.0/ingram-micro.json` (755 KB) — may expose large-spec codegen edge cases
- `v3.0/callback-example.json` — callbacks may not be fully supported
- `v3.0/link-example.json` — link objects may produce incomplete output

**Open question for Christian:** start with a denylist (skip known-broken, keep CI green) or allowlist (only known-passing, add others as fixed)? This is the primary governance question.

**Proposal written:** `.squad/decisions/inbox/starkiller-smoke-test-plan.md`

### Smoke Test Validation — Fenster's `test/smoke-tests.ps1` (2026-04-30)

**Outcome: PASS** (script behavior). Generator gap surfaced on `openapi/v3.0/ingram-micro.json` is a separate triage item, not a script defect.

**Static review against the approved plan — every requirement met:**
- Repo root resolution: uses `$PSCommandPath` → `Split-Path -Parent` → `Resolve-Path "$ScriptDir/.."` and `Set-Location $RepoRoot`, so it runs correctly regardless of caller's CWD (CI uses `working-directory: test`).
- Zig version check: `Find-Zig` resolves `Get-Command zig`, prints `zig version` before build; missing zig → red error + `exit 1`.
- ReleaseFast build: default `-Optimize ReleaseFast`, invoked as `zig build -Doptimize=$Optimize`, build failure → `exit 1`.
- Spec discovery: enumerates only `openapi/v2.0`, `v3.0`, `v3.1`, `v3.2`. `json-schema/` correctly excluded by not being in `$IncludedDirs`. YAML is filtered via lowercased extension check and counted into `$SkippedYaml` for the summary.
- Sequential matrix: nested `foreach ($spec) { foreach ($mode) }`, indices `[idx/total]`, colored case labels.
- Output dir: `$OutputDir = test/output`, wiped unless `-KeepOutput`, parent directories auto-created per (version, base, mode).
- Compile check: `zig test <generated.zig>` — correct technique because generated files are library modules without `main()`. (Cleaner than `build-lib -fno-emit-bin`; `zig test` reports "All 0 tests passed" on success.)
- Continue-all summary: per-case results stored in `$results`, summary prints Pass/Fail/Skip/Total + a failing-cases list grouped by phase (`generate`/`compile`).
- Denylist: `Test-Denylisted` with `Spec` (path or `*`) × `Mode` (name or `*`) × `Reason`; intentionally empty with explanatory comment.
- Non-zero exit: `exit 1` iff any non-denylisted case fails.

**PowerShell parse check:** `[System.Management.Automation.Language.Parser]::ParseFile()` → no errors.

**Focused run** (`-Filter "petstore" -Modes paths`, 9 cases): 9 PASS / 0 FAIL, exit 0.

**Full sweep** (`pwsh test/smoke-tests.ps1`, 88 cases = 22 specs × 4 modes, ~5m14s on Windows + Zig 0.16.0):
- 84 PASS / 4 FAIL / 0 SKIP, exit 1.
- All 4 failures are `openapi/v3.0/ingram-micro.json` × {none,tags,paths,hybrid}, all in the `compile` phase.
- Root cause is generator-side: emits multiple `pub const <SameName> = struct { ... }` declarations in the same Zig file (duplicate struct member name errors). Names like `QuoteDetailsRequestQuoteProductsRequestRetrieveQuoteProductsRequest` collide because the inline-schema name composer produces the same identifier from different schema sites. This is the exact "huge spec" risk I called out in the pre-plan inventory.
- Same pattern across all four resource-wrapper modes → bug is in the unified model generator's name-uniquing, not the API/wrapper layer.

**Governance call (open question for Lando + Christian):** the script is correct and the bug is real, so CI will go red on this PR. Three options: (a) Fenster fixes the duplicate-name path in `src/generators/unified/model_generator.zig` before merge; (b) populate `$Denylist` with the four ingram-micro entries, link a tracking issue, ship the script; (c) restrict full sweep to a curated allowlist for now. Recommendation: (b) — the smoke harness is valuable signal *now*, and the duplicate-name fix is its own focused PR.

**CI integration (`.github/workflows/ci.yml`):**
- Workflow file is `./smoke-tests.ps1` with `working-directory: test` and `shell: pwsh` → resolves to `test/smoke-tests.ps1` ✓.
- `pwsh` is preinstalled on `ubuntu-latest` GitHub runners ✓.
- Linux binary path: script uses `$IsWindows` to pick `openapi2zig` vs `openapi2zig.exe` ✓.
- `actions/upload-artifact@v4` path `test/output/` matches `$OutputDir` ✓; `if: failure()` only — good, keeps green runs lean.
- Job depends on `lint-and-format` and is gated on PR or `main`, alongside the existing `zig build run-generate` + `zig run generated/main.zig` petstore harness — that's the right layering: fast petstore sanity first, broad sweep second.
- `.gitignore` correctly adds `test/output/`.
- README "Smoke tests" section accurately describes the pwsh invocation and CI behavior.

**No script defects found.** Validation artifacts (`test/output/`, `test/smoke-full.log`) cleaned up.

### Smoke Test Final Gate — Post-Denylist (2026-04-30T16:31:22+02:00)

**Outcome: PASS.** Final validation gate after Fenster added the `ingram-micro` denylist entry.

**Denylist scoping check (static, `test/smoke-tests.ps1` lines 67–84):**
- Single entry: `Spec="openapi/v3.0/ingram-micro.json"` (literal, slash-normalized) × `Mode="*"` × clear reason.
- `Test-Denylisted` requires both `specMatch` AND `modeMatch`; literal spec string only matches that exact relpath, so other v3.0 specs are unaffected. `Mode="*"` correctly fans out across `none|tags|paths|hybrid`.
- Reason string includes "(all wrapper modes)" — explicit and audit-friendly.
- Comment block above the entry explains the generator gap and merge gate intent.

**Focused runs (Windows + Zig 0.16.0, ReleaseFast):**
- `pwsh -NoProfile -File test/smoke-tests.ps1 -Filter "v3.0/ingram-micro.json"` → 0 pass / 0 fail / 4 skip, **exit 0**. All four modes correctly skipped with denylist reason.
- `pwsh -NoProfile -File test/smoke-tests.ps1 -Filter "v3.0/petstore.json" -Modes paths` → 1 pass / 0 fail / 0 skip, **exit 0**. Denylist does not bleed into unrelated specs.

**Docs/CI alignment:**
- `.github/workflows/ci.yml` smoke-tests job (lines 127–172) unchanged and still correct: invokes `./smoke-tests.ps1` from `test/`, uploads `test/output/` on failure only.
- `README.md` (lines 177–194) already documents the denylist mechanism: "Honors a temporary denylist for known-unsupported spec/mode combinations so the PR gate can stay green while generator gaps are tracked explicitly." No doc drift.
- `.gitignore` still covers `test/output/`.

**No script defects, no doc drift, no CI drift.** Validation artifacts cleaned up.

**Follow-up (separate work, not blocking this gate):** the duplicate `pub const` emission in `src/generators/unified/model_generator.zig` for `openapi/v3.0/ingram-micro.json` remains a real generator bug. Recommend a tracking issue so the denylist entry has a clear retire-when condition; until then the entry self-documents the gap.

*To be updated as the team works.*

## 2026-04-30 — Smoke-test harness shipped
- Designed/implemented/validated 	est/smoke-tests.ps1 (88 cases: 22 specs × 4 wrapper modes), CI job updated with failure-only artifact upload, README documented.
- Initial denylist: ingram-micro.json (duplicate pub const emissions in unified model generator — follow-up backend work).
- Decision recorded in decisions.md (2026-04-30 entry). Session-scoped directive: agents use Claude Opus 4.7 for this session only.
