# Copilot Instructions for openapi2zig

**ALWAYS follow these instructions first. Only fallback to additional search and context gathering if the information here is incomplete or found to be in error.**

## Project Overview

This is a CLI tool written in Zig that generates type-safe Zig API client code from OpenAPI/Swagger specifications. The architecture follows a unified converter pattern that normalizes both OpenAPI v3.0 and Swagger v2.0 specs into a common intermediate representation before code generation.

## Working Effectively

### Prerequisites and Installation
Install Zig 0.14.1 exactly (other versions will NOT work):

**Option 1: GitHub Codespaces (RECOMMENDED for development)**
```bash
# Navigate to repository on GitHub → Code → Codespaces → Create codespace
# Everything is pre-configured with Zig 0.14.1, takes 2-3 minutes to set up
```

**Option 2: Dev Containers (local with Docker)**
```bash
# Install VS Code + Dev Containers extension
# Open project in VS Code → "Reopen in Container"
# Uses .devcontainer/devcontainer.json with Zig 0.14.1
```

**Option 3: Manual Installation**
```bash
# Download Zig 0.14.1 from https://ziglang.org/download/0.14.1/
# Linux x86_64:
wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz
tar -xf zig-linux-x86_64-0.14.1.tar.xz
export PATH="$PWD/zig-linux-x86_64-0.14.1:$PATH"

# Verify installation
zig version  # Must output "0.14.1"
```

### Bootstrap, Build, and Test the Repository
Run these commands in order. NEVER CANCEL long-running operations:

```bash
# 1. Verify Zig installation
zig version

# 2. Build project (takes 2-5 minutes first time, NEVER CANCEL)
zig build -Doptimize=Debug  # Set timeout to 10+ minutes

# 3. Run comprehensive test suite (takes 1-3 minutes, NEVER CANCEL)
zig build test  # Set timeout to 10+ minutes

# 4. Test code generation with sample OpenAPI specs
zig build run-generate  # Generates both v2.0 and v3.0 samples, takes 30 seconds

# 5. Validate generated code compiles and runs
zig run generated/main.zig  # Should output "Generated models build and run !!"
```

### Validation Scenarios
ALWAYS run these validation steps after making any changes:

```bash
# Format check (REQUIRED before commits or CI fails)
zig fmt --check src/
zig fmt --check build.zig

# Build with all optimization levels (CI requirement)
zig build -Doptimize=Debug      # Development builds, 2-5 minutes
zig build -Doptimize=ReleaseFast  # Performance builds, 2-5 minutes  
zig build -Doptimize=ReleaseSafe  # Safe optimized builds, 2-5 minutes
zig build -Doptimize=ReleaseSmall # Size-optimized builds, 2-5 minutes

# Test the actual CLI functionality with sample specs
zig build run-generate-v3  # Generate from OpenAPI v3.0, 30 seconds
zig build run-generate-v2  # Generate from Swagger v2.0, 30 seconds
zig run generated/main.zig  # Test generated code, should output "Generated models build and run !!"

# Manual CLI testing with custom specs
./zig-out/bin/openapi2zig generate -i openapi/v3.0/petstore.json -o /tmp/test_output.zig
zig run /tmp/test_output.zig  # Verify custom generated code works

# Cross-compilation validation (1-2 minutes each)
zig build -Dtarget=x86_64-windows   # Windows x64
zig build -Dtarget=x86_64-macos     # macOS x64  
zig build -Dtarget=aarch64-linux    # Linux ARM64
```

## Key Architecture Patterns

### Multi-Version Support via Unified Document
- **Source specs**: Parsed into version-specific models (`src/models/v2.0/`, `src/models/v3.0/`)
- **Converters**: Transform version-specific models to unified representation (`src/generators/converters/`)
- **Unified generators**: Generate Zig code from unified document (`src/generators/unified/`)

Example flow: `Swagger 2.0 JSON → SwaggerDocument → SwaggerConverter → UnifiedDocument → UnifiedModelGenerator + UnifiedApiGenerator → Zig code`

### Memory Management Convention
All structs with dynamic allocations implement `deinit(allocator)` method. ALWAYS call `defer parsed.deinit(allocator)` after parsing operations. The `UnifiedDocument` owns all converted data and handles cleanup.

### CLI Pattern
- `src/cli.zig`: Argument parsing with structured `CliArgs` and `ParsedArgs` types
- `src/generator.zig`: Main orchestration - detects spec version, calls appropriate converter, generates output
- `src/detector.zig`: Version detection by parsing JSON for `openapi` or `swagger` fields

## Development Workflows

### Core Commands with Timeouts
```bash
# Development build with debug info (2-5 minutes, timeout: 10 minutes)
zig build -Doptimize=Debug

# Run comprehensive test suite (1-3 minutes, timeout: 10 minutes) 
zig build test

# Generate code from sample specs (30 seconds each, timeout: 2 minutes)
zig build run-generate-v3  # Uses openapi/v3.0/petstore.json
zig build run-generate-v2  # Uses openapi/v2.0/petstore.json
zig build run-generate     # Runs both

# Format check (5 seconds, REQUIRED before commits)
zig fmt --check src/
zig fmt --check build.zig

# Install test artifacts for debugging (30 seconds)
zig build install_test -Doptimize=Debug
```

### Version Information
The build system auto-generates `src/version_info.zig` from git tags/commits. Never edit this file manually.

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

## Key Projects and Navigation

### Repository Structure
```
openapi2zig/
├── src/
│   ├── main.zig              # CLI entry point
│   ├── cli.zig               # Command-line argument parsing
│   ├── generator.zig         # Main code generation orchestrator
│   ├── detector.zig          # OpenAPI/Swagger version detection
│   ├── models/               # Data structures for parsing specs
│   │   ├── common/           # Unified/shared model definitions
│   │   ├── v2.0/            # Swagger 2.0 specific models
│   │   └── v3.0/            # OpenAPI 3.0 specific models
│   ├── generators/           # Code generation modules
│   │   ├── converters/      # Version-specific to unified conversion
│   │   ├── unified/         # Unified generators (preferred)
│   │   ├── v2.0/           # Legacy Swagger 2.0 generators
│   │   └── v3.0/           # Legacy OpenAPI 3.0 generators
│   └── tests/               # Test suite
├── openapi/                 # Sample OpenAPI specifications
│   ├── v2.0/               # Swagger 2.0 test specs  
│   └── v3.0/               # OpenAPI 3.0 test specs
├── generated/              # Output directory for test generation
├── .devcontainer/         # Development container configuration
└── .github/workflows/     # CI/CD pipelines
```

### Key Projects in Codebase

**Core CLI (`src/main.zig`, `src/cli.zig`)**
- Entry point and command-line interface
- Argument parsing and validation
- Integration point for all functionality

**Version Detection (`src/detector.zig`)**
- Auto-detects OpenAPI vs Swagger specifications
- Parses JSON to identify version fields
- Routes to appropriate parsers

**Data Models (`src/models/`)**
- `v2.0/`: Complete Swagger 2.0 specification models
- `v3.0/`: Complete OpenAPI 3.0 specification models  
- `common/`: Unified document representation for code generation

**Converters (`src/generators/converters/`)**
- `swagger_converter.zig`: Converts Swagger 2.0 → Unified Document
- `openapi_converter.zig`: Converts OpenAPI 3.0 → Unified Document
- **IMPORTANT**: This is the preferred architecture, not legacy generators

**Unified Generators (`src/generators/unified/`)**
- `model_generator.zig`: Creates Zig structs from unified schemas
- `api_generator.zig`: Creates HTTP client functions from unified operations
- **ALWAYS** use these instead of version-specific generators

**Test Suite (`src/tests/`)**
- `test_utils.zig`: Shared testing utilities and allocator helpers
- Version-specific tests for parsing and conversion
- Comprehensive converter tests with real-world specifications

### Frequently Visited Files

**When modifying parsing logic:**
- `src/models/v2.0/swagger.zig` - Root Swagger document structure
- `src/models/v3.0/openapi.zig` - Root OpenAPI document structure  
- `src/detector.zig` - Version detection logic

**When modifying code generation:**
- `src/generators/unified/model_generator.zig` - Struct generation
- `src/generators/unified/api_generator.zig` - API client generation
- `src/generator.zig` - Main generation orchestration

**When adding new OpenAPI features:**
- Add to appropriate `src/models/v?.?/` files first
- Update converters in `src/generators/converters/`
- Enhance unified generators in `src/generators/unified/`
- Add tests in `src/tests/`

**When debugging issues:**
- `src/tests/comprehensive_converter_tests.zig` - End-to-end testing
- `openapi/v?.?/petstore.json` - Known-good test specifications
- `generated/main.zig` - Example of expected output structure

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

## Critical Build and Test Information

## Critical Build and Test Information

### Timing Expectations and Timeouts
**NEVER CANCEL these operations - they can take much longer on slower systems:**

- **Initial build**: 2-5 minutes (subsequent: 30 seconds - 2 minutes)
  - `zig build -Doptimize=Debug` - Set timeout: 10+ minutes
  - `zig build -Doptimize=ReleaseFast` - Set timeout: 10+ minutes  
  - `zig build -Doptimize=ReleaseSafe` - Set timeout: 10+ minutes
  - `zig build -Doptimize=ReleaseSmall` - Set timeout: 10+ minutes

- **Test suite**: 1-3 minutes for full test run
  - `zig build test` - Set timeout: 10+ minutes
  - `zig build test -Doptimize=ReleaseFast` - Set timeout: 10+ minutes

- **Code generation**: 30 seconds per spec  
  - `zig build run-generate-v3` - Set timeout: 2+ minutes
  - `zig build run-generate-v2` - Set timeout: 2+ minutes
  - `zig build run-generate` - Set timeout: 5+ minutes

- **Cross-compilation**: 1-2 minutes per target
  - `zig build -Dtarget=x86_64-windows` - Set timeout: 5+ minutes
  - `zig build -Dtarget=x86_64-macos` - Set timeout: 5+ minutes  
  - `zig build -Dtarget=aarch64-linux` - Set timeout: 5+ minutes

- **Format checking**: 5-10 seconds
  - `zig fmt --check src/` - Set timeout: 30 seconds
  - `zig fmt --check build.zig` - Set timeout: 30 seconds

### Memory and Performance
- Use `test_utils.createTestAllocator()` in all tests for leak detection
- Generated code includes memory leak detection in main functions
- All parsers and generators implement proper `deinit()` cleanup

### CI Requirements  
The `.github/workflows/ci.yml` will fail if you don't:
- Run `zig fmt --check src/` and `zig fmt --check build.zig` before committing
- Ensure all builds pass for Debug, ReleaseFast, ReleaseSafe, ReleaseSmall
- Ensure tests pass for all optimization levels
- Maintain cross-compilation compatibility

## Common Tasks

### Frequently Run Commands (Reference Output)

**Repository Root (`ls -la`):**
```
.devcontainer/    # Development container config
.git/            # Git repository  
.github/         # GitHub workflows and settings
build.zig        # Main build configuration
build.zig.zon    # Zig package manager config  
generated/       # Test generation output
openapi/         # Sample OpenAPI specifications
src/             # Source code
```

**Source Directory (`ls src/`):**
```
cli.zig          # Command-line parsing
detector.zig     # Version detection
generator.zig    # Main orchestration
generators/      # Code generation modules
main.zig         # CLI entry point
models/          # Data structures
tests/           # Test suite
tests.zig        # Test module aggregator
```

**OpenAPI Samples (`ls openapi/`):**
```
v2.0/           # Swagger 2.0 specifications
v3.0/           # OpenAPI 3.0 specifications
json-schema/    # JSON Schema specifications
v3.1/           # OpenAPI 3.1 specifications (future)
```

**Generated Output Structure:**
```
generated/
├── main.zig           # Test harness that imports both versions
├── generated_v2.zig   # Swagger 2.0 generated API client
└── generated_v3.zig   # OpenAPI 3.0 generated API client
```

## Troubleshooting

### Installation Issues
- **"zig: command not found"**: Install Zig 0.14.1 exactly using methods above
- **Wrong Zig version**: Uninstall other versions, install 0.14.1 specifically  
- **Build failures**: Ensure you're using Zig 0.14.1, not 0.13.x or 0.15.x
- **Docker issues**: Use GitHub Codespaces or dev containers instead

### Build and Test Issues  
- **"error: FileNotFound"**: Run from repository root directory
- **Memory leaks in tests**: Always use `defer document.deinit(allocator)` pattern
- **Test failures**: Check that sample OpenAPI specs haven't been modified
- **Build timeouts**: Increase timeout values, builds can take 5+ minutes
- **Cross-compilation errors**: Verify target triplet format matches CI examples

### CI/CD Issues
- **Format check failures**: Run `zig fmt src/` and `zig fmt build.zig` to auto-fix
- **Test failures in CI**: Run exact same commands locally with same optimization level
- **Cross-compilation failures**: Test locally with `-Dtarget=` flags before pushing

### Code Generation Issues
- **Empty output files**: Check input OpenAPI spec is valid JSON/YAML
- **Compilation errors in generated code**: Test with known-good specs first (petstore.json)
- **Missing API methods**: Verify input spec has operationId fields
- **Type errors**: Check that OpenAPI schemas use supported data types

### Memory Management Issues
- **Memory leaks**: All parsers must call `defer parsed.deinit(allocator)`
- **Segmentation faults**: Use `test_utils.createTestAllocator()` in tests for better debugging
- **Double-free errors**: Check that `deinit()` is only called once per allocation

### Development Environment Issues
- **ZLS not working**: Restart language server, check VS Code output panel
- **IntelliSense missing**: Verify `.vscode/settings.json` has proper Zig configuration
- **Dev container rebuild needed**: Use "Dev Containers: Rebuild Container" command

## Current Development Focus

The project is transitioning to the unified converter architecture. When adding features:
1. Implement in unified generators rather than version-specific ones
2. Add comprehensive test coverage for both v2.0 and v3.0 inputs
3. Ensure memory cleanup with proper `deinit()` implementations
4. Follow the established JSON parsing patterns for new models
