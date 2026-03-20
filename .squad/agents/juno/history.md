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

*To be updated as the team works.*
