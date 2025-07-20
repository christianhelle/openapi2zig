# openapi2zig

[![CI](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml/badge.svg)](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml)
[![Zig Version](https://img.shields.io/badge/zig-0.14.1-orange.svg)](https://ziglang.org/download/)
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

## Installation

### Option 1: Quick Install Script (Recommended)

**Linux/macOS:**

```bash
curl -fsSL https://christianhelle.com/openapi2zig/install | bash
```

**Windows (PowerShell):**

```powershell
irm https://christianhelle.com/openapi2zig/install.ps1 | iex
```

The install scripts will:

- Automatically detect your platform and architecture
- Download the latest release from GitHub
- Install the binary to an appropriate location
- Add it to your PATH (if desired)

**Custom installation directory:**

```bash
# Linux/macOS
INSTALL_DIR=$HOME/.local/bin curl -fsSL https://christianhelle.com/openapi2zig/install | bash

# Windows
irm https://christianhelle.com/openapi2zig/install.ps1 | iex -InstallDir "C:\Tools"
```

### Option 2: Manual Download

Download the latest release for your platform from the [GitHub Releases page](https://github.com/christianhelle/openapi2zig/releases/latest):

- **Linux x86_64:** `openapi2zig-linux-x86_64.tar.gz`
- **macOS x86_64:** `openapi2zig-macos-x86_64.tar.gz`
- **macOS ARM64:** `openapi2zig-macos-aarch64.tar.gz`
- **Windows x86_64:** `openapi2zig-windows-x86_64.zip`

Extract the archive and add the binary to your PATH.

### Option 3: Install from Snap Store

Install the latest build for Linux from the Snap Store:

```bash
snap install --edge openapi2zig
```

### Option 4: Build from Source

Make sure you have Zig installed (version 0.14 or later).

```bash
git clone https://github.com/christianhelle/openapi2zig.git
cd openapi2zig
zig build
```

### Option 5: Use Docker

The openapi2zig is available as a Docker image on Docker Hub at `christianhelle/openapi2zig`.

```bash
# Pull the latest image
docker pull christianhelle/openapi2zig
```

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

```bash
openapi2zig generate [options]
```

### Options

| Flag | Description |
| :--- | :--- |
| `-i`, `--input <path>` | Path to the OpenAPI Specification file (JSON or YAML). |
| `-o`, `--output <path>`| Path to the output directory for the generated Zig code (default: current directory). |
| `--base-url <url>` | Base URL for the API client (default: server URL from OpenAPI Specification). |

## Example Generated Code

Below is an example of the Zig code generated from an OpenAPI specification.

### Models

```zig
///////////////////////////////////////////
// Generated Zig structures from OpenAPI
///////////////////////////////////////////

pub const Order = struct {
    status: ?[]const u8 = null,
    petId: ?i64 = null,
    complete: ?bool = null,
    id: ?i64 = null,
    quantity: ?i64 = null,
    shipDate: ?[]const u8 = null,
};

pub const Pet = struct {
    status: ?[]const u8 = null,
    tags: ?[]const u8 = null,
    category: ?[]const u8 = null,
    id: ?i64 = null,
    name: []const u8,
    photoUrls: []const u8,
};
```

### API Client

```zig
///////////////////////////////////////////
// Generated Zig API client from OpenAPI
///////////////////////////////////////////

const std = @import("std");

/////////////////
// Summary:
// Place an order for a pet
//
// Description:
// Place a new order in the store
//
pub fn placeOrder(allocator: std.mem.Allocator, requestBody: Order) !void {
    var client = std.http.Client.init(allocator);
    defer client.deinit();

    const uri = try std.Uri.parse("https://petstore.swagger.io/api/v3/store/order");
    const buf = try allocator.alloc(u8, 1024 * 8);
    defer allocator.free(buf);

    var req = try client.open(.POST, uri, .{
        .server_header_buffer = buf,
    });
    defer req.deinit();

    try req.send();

    var str = std.ArrayList(u8).init(allocator());
    defer str.deinit();

    try std.json.stringify(requestBody, .{}, str.writer());
    const body = try std.mem.join(allocator, "", str.items);

    req.transfer_encoding = .{ .content_length = body.len };
    try req.writeAll(body);

    try req.finish();
    try req.wait();
}

/////////////////
// Summary:
// Find pet by ID
//
// Description:
// Returns a single pet
//
pub fn getPetById(allocator: std.mem.Allocator, petId: i64) !void {
    var client = std.http.Client.init(allocator);
    defer client.deinit();

    const uri = try std.Uri.parse("https://petstore.swagger.io/api/v3/pet");
    const uri = try std.Uri.parse(uri_str);
    const buf = try allocator.alloc(u8, 1024 * 8);
    defer allocator.free(buf);

    var req = try client.open(.GET, uri, .{
        .server_header_buffer = buf,
    });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();
}
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
