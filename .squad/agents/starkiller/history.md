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

### Historical summary (archived 2026-05-01T09:50:14Z)

- **PR #46 documentation verification (2026-04-28T23:01:58.137+02:00):** README and docs now match the current generated runtime shape after a small correction. Static checks compared `README.md` and `docs/index.html` against `src/cli.zig`, `src/generator.zig`, `generated/generated_v2.zig`, `generated/generated_v3.zig`, `generated/generated_v31.zig`, `generated/generated_v32.zig`, `generated/compile_generated.zig`, and `generated/main.zig`.
- **Input Loader Testing Strategy (2026-03-20):** `src/tests/test_input_loader.zig`
- **Smoke Test Coverage Design (2026-04-30):** Design `test/smoke-tests.ps1` for PR verification — enumerate all specs under `openapi/`, generate code, compile-check each.
- **Smoke Test Validation — Fenster's `test/smoke-tests.ps1` (2026-04-30):** (script behavior). Generator gap surfaced on `openapi/v3.0/ingram-micro.json` is a separate triage item, not a script defect.
- **Smoke Test Final Gate — Post-Denylist (2026-04-30T16:31:22+02:00):** Final validation gate after Fenster added the `ingram-micro` denylist entry.
- **YAML smoke coverage review (2026-05-01T11:50:14.189+02:00):** `test/smoke-tests.ps1` now discovers both JSON and YAML specs and writes outputs as `<basename>__<format>__<mode>.zig`, which is required because 15 fixture basenames exist in both JSON and YAML form across `openapi/v2.0`, `openapi/v3.0`, and `openapi/v3.1`.

## 2026-04-30 — Smoke-test harness shipped
- Designed/implemented/validated 	est/smoke-tests.ps1 (88 cases: 22 specs × 4 wrapper modes), CI job updated with failure-only artifact upload, README documented.
- Initial denylist: ingram-micro.json (duplicate pub const emissions in unified model generator — follow-up backend work).
- Decision recorded in decisions.md (2026-04-30 entry). Session-scoped directive: agents use Claude Opus 4.7 for this session only.

### 2026-05-01T11:50:14.189+02:00 — Scribe closeout

- Scribe recorded Starkiller's final gate: JSON/YAML naming and generated-import collision protections are in place, but broad YAML smoke still needs normalization/denylist work before sign-off.
- The closeout preserves the testing rule that `generated/main.zig` is only a compile/init sanity check; the PowerShell sweep remains the authoritative YAML acceptance gate.

### 2026-05-01T11:50:14.189+02:00 — Reviewer verdict on YAML smoke scope

- Verdict for the user request **"Update smoke tests to also test YAML files"**: **approve**.
- Reason: YAML is now exercised in both smoke layers, curated YAML artifacts for v2/v3/v3.1 are checked in, `v3.2` correctly stays JSON-only, collision-safe smoke filenames prevent JSON/YAML overwrites, alias names stay distinct in generated harness imports, and smoke discovery still includes YAML-only roots such as `openapi/v3.0/bot.paths.yaml`.
- Remaining denylisted YAML parser/normalization gaps are acceptable for this request because they are explicitly tracked as unsupported smoke cases rather than silently skipped, and the reported green validation (`14 pass / 2 skip / 0 fail` focused, `128 pass / 28 skip / 0 fail` full) matches the scoped acceptance criteria.

### 2026-05-01T09:50:14Z — Scribe closeout

- Scribe recorded Starkiller's acceptance gate: YAML is exercised in both smoke layers, `openapi/v3.2` remains JSON-only, and the remaining denylisted YAML parser/normalization gaps are follow-up backend work rather than blockers for this scoped smoke-coverage release.
