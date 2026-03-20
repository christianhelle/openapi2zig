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
