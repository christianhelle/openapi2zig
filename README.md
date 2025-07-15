# openapi2zig

[![CI](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml/badge.svg)](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml)
[![Zig Version](https://img.shields.io/badge/zig-0.14.1+-orange.svg)](https://ziglang.org/download/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A CLI tool written in Zig that generates API client code in Zig from OpenAPI specifications.

> **Note**: This is a new project and its direction may evolve, but the current goal is to provide a CLI tool that can generate type-safe Zig client code from OpenAPI 3.x specifications.

## Features

- Parse OpenAPI v3.0 specifications (JSON format)
- Generate type-safe Zig client code
- Support for complex OpenAPI schemas and operations
- Cross-platform support (Linux, macOS, Windows)

## Prerequisites

- [Zig](https://ziglang.org/download/) 0.14.1 or later

## Quick Start

### Building from Source

1. Clone the repository:

   ```bash
   git clone https://github.com/christianhelle/openapi2zig.git
   cd openapi2zig
   ```

2. Build the project:

   ```bash
   zig build
   ```

3. Run tests to verify everything works:

   ```bash
   zig build test
   ```

4. The compiled binary will be available in `zig-out/bin/openapi2zig`

### Development

For development builds with debug information:

```bash
zig build -Doptimize=Debug
```

To run tests during development:

```bash
zig build test
```

To check code formatting:

```bash
zig fmt --check src/
zig fmt --check build.zig
```

### Cross-compilation

Build for different targets:

```bash
# Windows
zig build -Dtarget=x86_64-windows

# macOS
zig build -Dtarget=x86_64-macos

# Linux ARM64
zig build -Dtarget=aarch64-linux
```

## Usage

> **Note**: The CLI interface is currently under development. The tool currently includes OpenAPI parsing functionality and will be extended with code generation capabilities.

Basic usage (planned):

```bash
# Generate Zig client code from OpenAPI specification
openapi2zig generate -i api-spec.json -o generated/
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and ensure they pass (`zig build test`)
5. Check code formatting (`zig fmt --check src/`)
6. Commit your changes (`git commit -am 'Add some amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Code Style

This project follows standard Zig formatting. Use `zig fmt` to format your code before committing.

## Project Status

🚧 **Under Active Development** 🚧

This project is in early development. Current capabilities include:

- OpenAPI v3.0 specification parsing
- Basic data model structures for OpenAPI components
- Comprehensive test suite for parsing functionality

Planned features:

- CLI interface for code generation
- Zig client code generation
- Support for various OpenAPI features (authentication, complex schemas, etc.)
- Documentation generation

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions, please [open an issue](https://github.com/christianhelle/openapi2zig/issues) on GitHub.
