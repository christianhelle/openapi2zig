## Project Context

**Project:** openapi2zig — CLI tool for generating type-safe Zig API clients from OpenAPI/Swagger specs  
**User:** Christian Helle  
**Tech Stack:** Zig v0.15.2, OpenAPI v3.0, Swagger v2.0  
**Architecture:** Unified converter pattern (parse → normalize → generate)

## CLI & UX

- **Entry point:** `src/main.zig` with `src/cli.zig` for argument parsing
- **Main command:** `generate -i <input-spec> -o <output-file>`
- **Version detection:** Auto-detects Swagger v2.0 vs. OpenAPI v3.0 by parsing JSON
- **Generated output:** Zig code with API models and client functions, ready to compile
- **Sample usage:** `zig build run-generate-v3` and `zig build run-generate-v2` generate from petstore specs

## Key Contexts

- Sample specs in `openapi/v2.0/petstore.json` and `openapi/v3.0/petstore.json`
- Generated code output to `generated/main.zig` (test harness)
- Error handling and validation in CLI for input spec paths and arguments

## Learnings

### Remote URL Support Implementation

**Feature Overview:**
Users can now provide OpenAPI specs via remote URLs in addition to local file paths. The `-i`/`--input` flag accepts both formats:
- Local file: `openapi2zig generate -i ./openapi/petstore.json -o api.zig`
- Remote URL: `openapi2zig generate -i https://petstore3.swagger.io/api/v3/openapi.json -o api.zig`

**CLI Changes Made:**
1. **Help text updated** (`src/cli.zig`):
   - Changed `-i, --input <path>` to `-i, --input <PATH_OR_URL>`
   - Updated description to "OpenAPI/Swagger spec (file path or http/https URL)"
   - Added EXAMPLES section showing both local and remote usage

2. **Error messages improved** (`src/cli.zig`):
   - "OpenAPI spec path or URL required" when input is missing
   - Clearer feedback when argument values are missing

3. **URL detection function** (`src/cli.zig`):
   - Added `isRemoteUrl()` function to detect http:// and https:// prefixes
   - Ready for use by Fenster's `input_loader.zig` for network vs filesystem routing

4. **README updated** (`README.md`):
   - Updated usage table with new `<PATH_OR_URL>` parameter
   - Added "Examples" section with local file and remote URL examples

**Backwards Compatibility:**
- All existing file path usage continues to work unchanged
- No breaking changes to command structure or argument parsing
- Network fetching delegated to backend (Fenster's input_loader)

**Notes for Implementation:**
- URL detection is simple string matching on protocol prefix
- HTTP client errors will be handled by Fenster's input_loader module
- File-not-found errors still need to be handled by file system operations

### PR #46 Documentation Sync (2026-04-28T23:01:58.137+02:00)

- **User preference:** commit documentation updates in small logical groups and stage only intentional files; leave other agents' `.squad` changes untouched.
- **CLI state:** `openapi2zig generate` accepts `-i/--input <PATH_OR_URL>`, `-o/--output <path>`, `--base-url <url>`, and `--resource-wrappers none|tags|paths|hybrid` with default `paths`.
- **Generated samples:** `zig build run-generate` now produces `generated/generated_v2.zig`, `generated/generated_v3.zig`, `generated/generated_v31.zig`, and `generated/generated_v32.zig`.
- **Generated client shape:** current output includes `Client`, `Owned(T)`, `RawResponse`, `ApiResult(T)`, raw/result endpoint helpers, bounded SSE helpers, and path-based resource wrappers.
- **Docs touched:** `README.md`, `docs/index.html`, `docs/json-value-typing-policy.md`, and `docs/openai-generation-issues.md` were updated to match PR #46 behavior.
- **Validation note:** local `zig.exe` was present only as a broken WinGet link, so validation was static against source, build targets, and generated files rather than executing Zig commands.

### Lando/Fenster Handoff Follow-up (2026-04-28T23:01:58.137+02:00)

- Read `.squad/decisions/inbox/lando-pr46-doc-impact.md` and `.squad/decisions/inbox/fenster-pr46-codegen-docs.md` before finalizing docs.
- Added remaining docs gaps from handoff: query percent-encoding, borrowed `default_headers`, OpenAI stream helper names, resource wrapper naming caveat, validation commands, and OpenAPI 3.1 composite-schema caveat.
- Kept documentation scoped to README and `docs/`; did not stage other agents' `.squad` history changes.

### Smoke Test Investigation (2026-04-30T16:31:22.685+02:00)

**Scope:** User wants comprehensive smoke tests (`test/smoke-tests.ps1`) to generate + compile all 24 OpenAPI specs, integrated into PR verification.

**Key findings:**
- **24 specs available** across v2.0 (8), v3.0 (9), v3.1 (2), v3.2 (2); exclude json-schema/ utilities
- **Current test coverage:** Only v2.0 + v3.0 petstore (2 specs); too narrow
- **Refitter reference:** 880-line PowerShell script with phase-based generation/build pattern; proves approach works at scale
- **CLI is mature:** Already supports `-i <PATH|URL>`, `-o <file>`, `--base-url`, `--resource-wrappers`; **no changes needed** for smoke testing
- **No UX issues:** Script can use existing CLI as-is

**Recommendation (MVP):**
1. Create `test/smoke-tests.ps1` (~250 lines): discover specs, generate sequentially, compile each with `zig run`, report per-spec pass/fail
2. Call from `.github/workflows/ci.yml` or new `smoke-tests-comprehensive.yml` 
3. Output format: `[PASS]/[FAIL] <spec>` per line, summary, exit code 0/1
4. Update README with smoke test docs
5. **No CLI modifications required**

**Clarifying questions for Christian:**
- Test `--resource-wrappers` variants (4× tests) or single mode?
- Skip json-schema/ utilities?
- Block PR on failures or warnings?
- Sequential or parallel generation?
- Temp file location: `generated/smoke-test/` or elsewhere?

**Detailed plan:** `.squad/decisions/inbox/juno-smoke-test-plan.md`

### Smoke Test CI + Docs Wiring (2026-04-30T16:31:22.685+02:00)

**Scope:** Wired the approved broad smoke-test plan into CI and README without touching `test/smoke-tests.ps1` (Fenster owns that script).

**CI changes (`.github/workflows/ci.yml` smoke-tests job):**
- Kept the existing petstore harness step (`zig build run-generate` + `zig run generated/main.zig`) untouched.
- Added a step `Run broad smoke-test script` mirroring Refitter's style: `run: ./smoke-tests.ps1`, `working-directory: test`, `shell: pwsh`.
- Added a final step `Upload smoke-test outputs on failure` gated on `if: failure()`, uploading `test/output/` as artifact `smoke-test-output` with 7-day retention (matches existing `test-binaries` retention).
- Job still gated on PR or `main`; no change to triggers, runner, caches, or `needs`.

**README changes:**
- Added a new `### Smoke tests` subsection under `## Quick Start` → `### Development`, between formatting and cross-compilation.
- Documented: `pwsh test/smoke-tests.ps1`, scope (v2.0/v3.0/v3.1/v3.2 JSON), four resource-wrapper modes, YAML/json-schema exclusions, output to `test/output/`, continue-through-failure with summary, temporary denylist, and CI behavior + artifact upload.

**Conventions reused from Refitter (`christianhelle/refitter/.github/workflows/smoke-tests.yml`):**
- `working-directory: test` + relative `./smoke-tests.ps1` invocation, `shell: pwsh`.

**Validation:**
- YAML parsed cleanly via Python `yaml.safe_load`.
- Did not run the smoke script (Fenster's `test/smoke-tests.ps1` not yet on disk at task time).
- Did not touch `.gitignore` — task said the plan adds `test/output/` to gitignore, but coordinating that lives with Fenster's script PR.

**Coordination notes:**
- Smoke job assumes script path `test/smoke-tests.ps1` and output dir `test/output/`; if Fenster picks different paths, both the CI step's `working-directory` and the artifact `path` need to match.
- Artifact upload `path: test/output/` is relative to repo root (correct for `actions/upload-artifact`), even though the run step uses `working-directory: test`.

## 2026-04-30 — Smoke-test harness shipped
- Designed/implemented/validated 	est/smoke-tests.ps1 (88 cases: 22 specs × 4 wrapper modes), CI job updated with failure-only artifact upload, README documented.
- Initial denylist: ingram-micro.json (duplicate pub const emissions in unified model generator — follow-up backend work).
- Decision recorded in decisions.md (2026-04-30 entry). Session-scoped directive: agents use Claude Opus 4.7 for this session only.

## 2026-05-01T11:50:14.189+02:00 — YAML smoke docs alignment
- Broad smoke coverage lives in `test/smoke-tests.ps1`; it should treat YAML as first-class input and encode source format in artifact names such as `__json__` / `__yaml__` to avoid sibling collisions.
- README smoke docs should distinguish the broad PowerShell sweep from the smaller curated sample harness in `build.zig` and `generated/main.zig`; broad discovery must not imply JSON/YAML twin files are required, and the curated harness should call out that `v3.2` is still JSON-only because the repo has no `v3.2` YAML root fixture.
- Useful review paths for this topic: `README.md`, `test/smoke-tests.ps1`, `build.zig`, `generated/main.zig`, and YAML fixture roots like `openapi/v2.0/petstore.yaml`, `openapi/v3.0/petstore.yaml`, `openapi/v3.1/webhook-example.yaml`, `openapi/v3.0/bot.paths.yaml`.
