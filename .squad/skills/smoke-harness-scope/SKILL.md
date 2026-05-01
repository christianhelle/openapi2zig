---
name: "smoke-harness-scope"
description: "How to extend smoke coverage without collapsing dynamic sweeps into the curated generated harness"
domain: "testing-architecture"
confidence: "high"
source: "lando review"
---

## Context

openapi2zig uses two smoke layers on purpose:

1. `test/smoke-tests.ps1` for broad, dynamically discovered fixture coverage
2. `build.zig` + `generated/*` for a small, stable curated harness used by normal build/test flows

When expanding coverage (for example, JSON → YAML), keep both layers, but do not merge their responsibilities.

## Patterns

### Keep the two smoke layers separate

- Put discovery, per-spec iteration, denylist handling, and matrix execution in `test/smoke-tests.ps1`
- Keep `build.zig` limited to a curated set of stable fixtures with checked-in generated outputs
- Update `generated/compile_generated.zig` and `generated/main.zig` only for those curated artifacts

### Encode source format in generated smoke filenames

If the same fixture basename exists as both JSON and YAML in the same version folder, artifact names must include the source format:

- `petstore__json__paths.zig`
- `petstore__yaml__paths.zig`

Without that segment, one format overwrites the other.

### Curated harness commits must be atomic

If `build.zig` or `generated/*` starts importing a new generated file, that same commit must also add the checked-in generated artifact. Otherwise `zig build test` breaks immediately on missing imports.

### Treat `generated/main.zig` as a sanity harness, not the final smoke authority

- `zig build run-generate` + `zig run generated/main.zig` is useful to prove curated generated modules still build, initialize, and can exercise a tiny happy path.
- Do **not** use it as the only acceptance signal for broader smoke work; it still depends on live endpoints and can print runtime errors while returning early.
- For format-expansion work (like YAML coverage), the authoritative pass/fail signal must come from `test/smoke-tests.ps1`.

### Do not use “has JSON sibling” as the YAML inclusion rule

Some valid YAML smoke candidates may be YAML-only roots. Prefer explicit inclusion plus collision-safe naming. If a file is truly non-runnable, skip or denylist it with a reason instead of silently dropping all YAML-only files.

### Denylist format-specific parse failures by exact fixture path

- If a new format expansion (such as YAML) exposes parser failures before wrapper-specific generation runs, add explicit denylist entries for the failing fixture paths instead of backing out discovery.
- Use `Mode = "*"` when every wrapper mode fails from the same pre-generation cause, and make the `Reason` describe the parser/normalization gap rather than only saying "generation failed".
- Keep the rest of the format family running so the smoke sweep still proves coverage for the supported fixtures.

## Anti-Patterns

- Moving broad fixture enumeration into `build.zig`
- Reusing the same output filename for JSON and YAML siblings
- Importing YAML harness artifacts with aliases that shadow existing JSON aliases
- Forcing version parity by inventing new canonical fixtures that do not exist in `openapi/`
