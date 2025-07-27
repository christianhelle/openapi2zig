# Copilot Instructions for openapi2zig

## Project Overview

This is a CLI tool written in Zig that generates type-safe Zig API client code from OpenAPI/Swagger specifications. The architecture follows a unified converter pattern that normalizes both OpenAPI v3.0 and Swagger v2.0 specs into a common intermediate representation before code generation.

## Key Architecture Patterns

### Multi-Version Support via Unified Document
- **Source specs**: Parsed into version-specific models (`src/models/v2.0/`, `src/models/v3.0/`)
- **Converters**: Transform version-specific models to unified representation (`src/generators/converters/`)
- **Unified generators**: Generate Zig code from unified document (`src/generators/unified/`)

Example flow: `Swagger 2.0 JSON → SwaggerDocument → SwaggerConverter → UnifiedDocument → UnifiedModelGenerator + UnifiedApiGenerator → Zig code`

### Memory Management Convention
All structs with dynamic allocations implement `deinit(allocator)` method. Always call `defer parsed.deinit(allocator)` after parsing operations. The `UnifiedDocument` owns all converted data and handles cleanup.

### CLI Pattern
- `src/cli.zig`: Argument parsing with structured `CliArgs` and `ParsedArgs` types
- `src/generator.zig`: Main orchestration - detects spec version, calls appropriate converter, generates output
- `src/detector.zig`: Version detection by parsing JSON for `openapi` or `swagger` fields

## Development Workflows

### Building and Testing
```bash
# Development build with debug info
zig build -Doptimize=Debug

# Run comprehensive test suite
zig build test

# Generate code from sample specs (useful for testing)
zig build run-generate-v3  # Uses openapi/v3.0/petstore.json
zig build run-generate-v2  # Uses openapi/v2.0/petstore.json
zig build run-generate     # Runs both

# Format check (required before commits)
zig fmt --check src/
zig fmt --check build.zig
```

### Version Information
The build system auto-generates `src/version_info.zig` from git tags/commits. Never edit this file manually.

## Code Generation Patterns

### Two-Phase Generation
1. **Model Generation** (`UnifiedModelGenerator`): Creates Zig structs from OpenAPI schemas
2. **API Generation** (`UnifiedApiGenerator`): Creates HTTP client functions for operations

### Generated Code Structure
```zig
// Models section
pub const Pet = struct {
    name: []const u8,
    id: ?i64 = null,
    // Optional fields use ?T = null pattern
};

// API section  
pub fn getPetById(allocator: std.mem.Allocator, petId: i64) !void {
    var client = std.http.Client.init(allocator);
    defer client.deinit();
    // Standard HTTP client pattern with proper cleanup
}
```

## Testing Conventions

### Test Organization
- `src/tests.zig`: Test module aggregator (imports all test files)
- `src/tests/`: Individual test files by feature area
- `src/tests/test_utils.zig`: Shared test utilities including `createTestAllocator()`

### Test Pattern
```zig
test "descriptive test name" {
    var gpa = test_utils.createTestAllocator();
    const allocator = gpa.allocator();
    
    // Test implementation with proper cleanup
    var document = try loadDocument(allocator, "path/to/spec.json");
    defer document.deinit(allocator);
}
```

### Sample Specifications
Use files in `openapi/` directory for testing:
- `openapi/v3.0/petstore.json` - Basic OpenAPI v3 spec
- `openapi/v2.0/petstore.json` - Basic Swagger v2 spec
- Various other specs in subdirectories for edge cases

## File Patterns and Conventions

### Model Files
- Version-specific models in `src/models/v2.0/` and `src/models/v3.0/`
- Common unified models in `src/models/common/`
- Each model implements JSON parsing: `parseFromJson(allocator, json_string)`

### Generator Organization
- `src/generators/converters/`: Version-specific to unified conversion
- `src/generators/unified/`: Unified document to Zig code generation
- `src/generators/v2.0/` and `src/generators/v3.0/`: Legacy version-specific generators (being phased out)

### Error Handling
Use Zig error sets and `catch |err|` pattern. Print meaningful error messages with context before returning errors.

## Current Development Focus

The project is transitioning to the unified converter architecture. When adding features:
1. Implement in unified generators rather than version-specific ones
2. Add comprehensive test coverage for both v2.0 and v3.0 inputs
3. Ensure memory cleanup with proper `deinit()` implementations
4. Follow the established JSON parsing patterns for new models
