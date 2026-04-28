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
