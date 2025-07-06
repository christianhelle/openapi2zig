# CI/CD Pipeline

This repository includes a comprehensive CI/CD pipeline that automatically builds and tests the codebase on every commit and pull request.

## Pipeline Overview

The CI pipeline consists of three main jobs:

### 1. Lint and Format Check
- Checks code formatting with `zig fmt --check`
- Ensures consistent code style across the project
- Runs on every push and pull request

### 2. Build and Test
- Builds the project with multiple optimization levels (Debug, ReleaseFast, ReleaseSafe, ReleaseSmall)
- Runs all unit tests to ensure functionality
- Caches Zig dependencies for faster builds
- Uploads test artifacts for debugging purposes

### 3. Cross-compile Check
- Verifies the project can be compiled for multiple targets:
  - x86_64-windows
  - x86_64-macos  
  - aarch64-linux
- Only runs on pull requests and main branch pushes
- Uploads cross-compiled binaries as artifacts

## Extensibility

The pipeline is designed to be easily extensible:

- **Environment Variables**: Zig version is centralized in the `ZIG_VERSION` environment variable
- **Matrix Builds**: Easy to add new optimization levels or target platforms
- **Conditional Jobs**: Cross-compilation only runs when necessary
- **Artifact Management**: Build outputs are preserved for download and debugging
- **Placeholder for Deployment**: Commented deployment stage ready to be activated

## Adding New Stages

To add new pipeline stages:

1. **Testing**: Add new test types by extending the build-and-test job
2. **Security**: Add security scanning as a new job
3. **Documentation**: Add documentation generation/validation
4. **Deployment**: Uncomment and configure the deployment stage

## Local Development

To run the same checks locally:

```bash
# Format check
zig fmt --check src/
zig fmt --check build.zig

# Build and test
zig build
zig build test

# Cross-compile
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-linux
```