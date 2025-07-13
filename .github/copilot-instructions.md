# Copilot Instructions for openapi2zig

## Project Overview
This is a Zig-based CLI tool that generates type-safe API client code from OpenAPI 3.x specifications. The project is in early development, currently focused on robust OpenAPI parsing with code generation capabilities planned.

## Architecture

### Core Components
- **`src/models.zig`** (1366 lines): Complete OpenAPI 3.x specification models with JSON parsing/serialization
- **`src/main.zig`**: Entry point with primary test demonstrating petstore.json parsing
- **`openapi/`**: Test OpenAPI specifications (petstore.json, v30-json-schema.json)

### Key Patterns

#### Memory Management
All structs follow strict manual memory management:
```zig
pub fn deinit(self: *OpenApiDocument, allocator: std.mem.Allocator) void {
    allocator.free(self.openapi);
    self.info.deinit(allocator);
    // ... recursively free all allocated fields
}
```
- **Critical**: Every `parse()` method allocates, every struct needs `deinit()`
- Use `allocator.dupe(u8, string)` for persistent string copies from JSON
- HashMap cleanup requires iterating and freeing individual entries

#### JSON Parsing Architecture
Consistent pattern across all OpenAPI models:
```zig
pub fn parse(allocator: std.mem.Allocator, value: json.Value) anyerror!StructName {
    const obj = value.object;
    return StructName{
        .field = if (obj.get("field")) |val| try allocator.dupe(u8, val.string) else null,
    };
}
```

#### Error Handling
Uses Zig's `anyerror!` return types for all parsing operations. No custom error types defined yet.

## Development Workflow

### Build Commands
```bash
# Standard build
zig build

# Debug build with symbols
zig build -Doptimize=Debug

# Cross-compilation
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-linux
```

### Testing
```bash
# Run all tests
zig build test

# Install test binaries for debugging
zig build install_test
```

**Key Test**: The main test in `src/main.zig` parses `openapi/petstore.json` and validates the OpenAPI document structure.

### Code Quality
```bash
# Format check (required by CI)
zig fmt --check src/
zig fmt --check build.zig

# Auto-format
zig fmt src/
```

## CI/CD Pipeline
GitHub Actions with matrix builds across:
- **Optimization levels**: Debug, ReleaseFast, ReleaseSafe, ReleaseSmall  
- **Cross-compilation targets**: x86_64-windows, x86_64-macos, aarch64-linux
- **Zig version**: 0.14.1 (pinned in workflow)

## Implementation Guidelines

### Adding New OpenAPI Models
1. Follow the existing pattern in `models.zig`
2. Implement both `parse()` and `deinit()` methods
3. Handle optional fields with null coalescing: `if (obj.get("field")) |val| ... else null`
4. For collections, use `std.ArrayList` during parsing, then `toOwnedSlice()`

### String Handling
- Always use `allocator.dupe(u8, source_string)` for persistent copies
- Never store direct references to JSON string values (they're freed after parsing)

### HashMap Usage
```zig
var map = std.StringHashMap(ValueType).init(allocator);
// ... populate map
return if (map.count() > 0) map else null; // Avoid empty maps
```

### Testing Strategy
- Primary test parses the complete petstore.json specification
- Tests validate both parsing success and specific field values
- Use `std.testing.expectEqualStrings` for string comparisons

## Dependencies
- **Zig 0.14.1+** (no external dependencies)
- Build system uses only Zig's standard build system (`build.zig`)
- JSON parsing via `std.json` (built-in)

## Future Architecture Notes
The project is designed for extensibility toward code generation:
- Models are complete representations of OpenAPI 3.x spec
- CLI interface structure planned but not yet implemented
- Consider the parsing foundation as stable, generation layer as next milestone
