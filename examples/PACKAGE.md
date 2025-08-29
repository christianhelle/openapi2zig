# Publishing openapi2zig as a Zig Package

This document explains how to publish and use openapi2zig as a Zig package.

## For Package Publishers (Maintainers)

### Prerequisites

1. Ensure you have Zig 0.15.1 installed
2. All tests are passing: `zig build test`
3. All builds work: `zig build -Doptimize=Debug`, `zig build -Doptimize=ReleaseFast`

### Release Process

1. **Update Version in build.zig.zon**
   ```zig
   .version = "1.0.0", // Update to new version
   ```

2. **Tag the Release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. **Create GitHub Release**
   - Go to GitHub repository
   - Create new release with tag v1.0.0
   - Include release notes and examples

4. **Test Package Installation**
   ```bash
   # In a test project
   zig fetch --save https://github.com/christianhelle/openapi2zig/archive/refs/tags/v1.0.0.tar.gz
   ```

## For Package Users (Consumers)

### Adding openapi2zig to Your Project

1. **Add to build.zig.zon dependencies**
   ```bash
   zig fetch --save https://github.com/christianhelle/openapi2zig/archive/refs/tags/v1.0.0.tar.gz
   ```

   This automatically adds to your build.zig.zon:
   ```zig
   .dependencies = .{
       .openapi2zig = .{
           .url = "https://github.com/christianhelle/openapi2zig/archive/refs/tags/v1.0.0.tar.gz",
           .hash = "1220...", // Automatically computed hash
       },
   },
   ```

2. **Update your build.zig**
   ```zig
   const openapi2zig_dep = b.dependency("openapi2zig", .{
       .target = target,
       .optimize = optimize,
   });

   exe.root_module.addImport("openapi2zig", openapi2zig_dep.module("openapi2zig"));
   ```

3. **Use in your code**
   ```zig
   const openapi2zig = @import("openapi2zig");
   ```

### Example Usage

See the main README.md for detailed usage examples.

## Package Structure

The package provides:

- **CLI executable**: Available when building the package directly
- **Library module**: Named "openapi2zig", available to dependents
- **Static library**: For linking scenarios

### What's Included in the Package

From build.zig.zon `.paths`:
- `build.zig` - Build configuration
- `build.zig.zon` - Package metadata
- `src/` - All source code including lib.zig entry point
- `LICENSE` - MIT license
- `README.md` - Documentation

### What's Excluded

- Test files in `generated/`
- Development utilities
- CI/CD configurations
- Docker files

## Version Compatibility

- **Zig Version**: Requires exactly Zig 0.15.1
- **API Stability**: The library API is considered stable as of v1.0.0
- **Semantic Versioning**: We follow semver for breaking changes

## Troubleshooting

### Common Issues

1. **Zig Version Mismatch**
   ```
   error: invalid build.zig.zon
   ```
   Solution: Use exactly Zig 0.15.1

2. **Hash Mismatch**
   ```
   error: hash mismatch
   ```
   Solution: Use `zig fetch` to get the correct hash

3. **Module Not Found**
   ```
   error: no module named 'openapi2zig'
   ```
   Solution: Ensure you added the dependency correctly in build.zig

### Getting Help

- Check the main README.md
- Review the example_usage.zig file
- Open an issue on GitHub: https://github.com/christianhelle/openapi2zig/issues
