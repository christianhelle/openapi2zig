# Squad Decisions

## Active Decisions

### 2026-03-20: Team Structure & Casting

- **Roster established:** Lando (Lead), Fenster (Backend), Juno (Frontend), Starkiller (Tester), Scribe, Ralph (Work Monitor)
- **Universe:** Star Wars Extended Universe — emphasizes function, pressure, and consequence
- **Squad structure:** `.squad/` initialized with agents, decisions, orchestration logs, casting registry
- **Key principle:** Unified converter pattern is the spine — all work must respect parse → normalize → generate flow

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

### 2025-01-17 / 2026-03-20: Remote URL input support

- **Decision:** openapi2zig generate supports local JSON files and remote http:// / https:// OpenAPI or Swagger JSON inputs.
- **Architecture:** URL/file loading is centralized in src/input_loader.zig via an input-source abstraction, preserving the existing parse → normalize → generate flow and caller-owned buffers.
- **Scope:** HTTP/HTTPS GET only for MVP; no auth, proxy, cache, custom timeout, or YAML URL support.
- **CLI contract:** -i, --input <PATH_OR_URL> accepts local paths or URLs without breaking existing file workflows.
- **Testing policy:** Use fast local/unit coverage for URL detection, file loading, error handling, and memory cleanup; use skippable integration coverage for public petstore endpoints when network access is available.
- **Sources merged:** scribe-remote-url-support.md, fenster-http-url-support.md, juno-remote-url-support.md, starkiller-hybrid-testing-http.md.

### 2026-04-28: PR #46 generated runtime documentation sync

- **Decision:** Documentation must present the post-PR #46 generated runtime as the current public output shape: Client, Owned(T), RawResponse, ParseErrorResponse, ApiResult(T), raw/result endpoint helpers, bounded SSE helpers, OpenAI stream helpers when applicable, and resource wrappers.
- **Architecture:** Docs should reinforce the unified converter/generator path and avoid showing legacy per-function std.http.Client snippets as current behavior.
- **CLI/docs contract:** Generation writes one Zig output file; JSON file/URL input is supported, YAML remains unsupported; supported detector routes include Swagger 2.0 and OpenAPI 3.0/3.1/3.2; --resource-wrappers none|tags|paths|hybrid defaults to paths.
- **Model/runtime policy:** Object schemas become structs, arrays become typed slices where known, required fields are non-nullable, nullable unions collapse to ?T, safe unions preserve raw fallbacks, and open or ambiguous schemas remain std.json.Value.
- **Verification note:** Starkiller accepted the docs with snippet fixes; Zig validation was blocked by a broken local WinGet zig.exe, so verification was static against current source/generated fixtures.
- **Sources merged:** lando-pr46-doc-impact.md, fenster-pr46-codegen-docs.md, juno-pr46-docs.md.

### 2026-04-30: Smoke-test harness for code generation

- **Decision:** Add a PowerShell-driven smoke-test harness that runs the full spec × resource-wrapper matrix and validates that generated Zig compiles, integrated into the existing `smoke-tests` CI job.
- **Script contract (`test/smoke-tests.ps1`, owned by Fenster):** Lives at `test/smoke-tests.ps1`; resolves repo root from `$PSCommandPath` (CWD-independent); builds once with `-Doptimize=ReleaseFast`; enumerates JSON specs under `openapi/v2.0`, `v3.0`, `v3.1`, `v3.2`; skips `openapi/json-schema/` and counts YAML files as a single skip total; iterates 22 specs × 4 wrapper modes (`none`, `tags`, `paths`, `hybrid`) = 88 cases sequentially; writes outputs to `test/output/<version>/<basename>__<mode>.zig` (cleared per run unless `-KeepOutput`); exposes `-Filter` glob and `-Modes` selector for focused runs; exits non-zero only when non-denylisted failures occur.
- **Compile-check method:** Use `zig test <generated.zig>` — generated files are library modules with no `main()`, so `zig run`/`build-exe` cannot work. `zig test` compiles + type-checks all decls and exits cleanly with "All 0 tests passed."
- **Denylist policy:** Inline `@{ Spec; Mode; Reason }` table in the script. `Mode = "*"` wildcards mode-independent failures. Denylisted cases report as `SKIP` with reason and do not influence exit code. Each entry must reference the underlying generator gap and be removed when fixed. Initial entry: `openapi/v3.0/ingram-micro.json` × `*` — duplicate `pub const X = struct` emissions from `src/generators/unified/model_generator.zig` (all wrapper modes fail compile identically).
- **CI wiring (`.github/workflows/ci.yml`, owned by Juno):** Existing `smoke-tests` job keeps its `zig build run-generate` + `zig run generated/main.zig` petstore step, then adds `Run broad smoke-test script` (`run: ./smoke-tests.ps1`, `working-directory: test`, `shell: pwsh`) and `Upload smoke-test outputs on failure` (`actions/upload-artifact@v4`, `path: test/output/`, `retention-days: 7`, `if: failure()`). No trigger/runner/cache changes.
- **README:** New Development → Smoke tests subsection documenting `pwsh test/smoke-tests.ps1`, scope (JSON specs across v2.0–v3.2), skips (YAML, `json-schema/`), wrapper-mode matrix, output layout, denylist behavior, and CI behavior.
- **`.gitignore`:** Excludes `test/output/`.
- **Validation results:** PowerShell parse clean. Focused run (petstore × paths, 9 cases) 9/9 green. Full sweep (88 cases, ~5m14s on Zig 0.16.0) was 84/88 PASS pre-denylist; all 4 failures were `ingram-micro.json` compile-phase across all wrapper modes. Post-denylist: ingram-micro reports SKIP, petstore-only run still PASS, exit 0 — denylist does not leak.
- **Follow-up (out of scope):** Track and fix the unified model generator's duplicate `pub const` emission for shared/nested schemas; remove the ingram-micro denylist entry in the same PR.
- **Session-scoped directive (2026-04-30T16:31:22.685+02:00, Christian Helle via Copilot):** All agents use Claude Opus 4.7 for the rest of this session only.
- **Sources merged:** lando-smoke-test-plan.md, starkiller-smoke-test-plan.md, juno-smoke-test-plan.md, juno-smoke-ci-docs.md, fenster-smoke-test-plan.md, fenster-smoke-implementation.md, fenster-smoke-denylist-ingram-micro.md, starkiller-smoke-validation.md, copilot-directive-2026-04-30T16-31-22-685+02-00.md.
