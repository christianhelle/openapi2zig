# openapi2zig

[![CI](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml/badge.svg)](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml)
[![Zig Version](https://img.shields.io/badge/zig-0.15.2-orange.svg)](https://ziglang.org/download/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A CLI tool and Zig library that generates type-safe API client code from OpenAPI specifications.

> **Note**: This project provides both a CLI tool for generating Zig code from OpenAPI specs and a library for parsing and working with OpenAPI documents programmatically in Zig.

## Features

- Parse OpenAPI v2.0, v3.0, and v3.2 specifications (JSON format)
- Generate type-safe Zig client code
- Support for complex OpenAPI schemas and operations
- Cross-platform support (Linux, macOS, Windows)
- Available as both CLI tool and Zig library
- Unified document representation for both OpenAPI and Swagger specs

## Prerequisites

- [Zig](https://ziglang.org/download/) v0.15.2

## Development Environment

### Option 1: GitHub Codespaces (Recommended for Contributors)

The fastest way to get started with development is using GitHub Codespaces, which provides a pre-configured development environment with Zig, ZLS (Zig Language Server), and all necessary VS Code extensions.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/christianhelle/openapi2zig)

1. Click the badge above or navigate to the repository on GitHub
2. Click "Code" → "Codespaces" → "Create codespace"
3. Wait for the environment to set up (2-3 minutes)
4. Start coding! Everything is pre-configured.

### Option 2: VS Code Dev Containers (Local)

If you prefer local development with Docker:

1. Install [VS Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Clone the repository and open it in VS Code
3. When prompted, click "Reopen in Container"
4. VS Code will build and configure the development environment automatically

### Option 3: Manual Setup

Install Zig locally following the official [installation guide](https://ziglang.org/download/).

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

Make sure you have Zig installed (version 0.15.2 exactly).

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

| Flag                    | Description                                                                           |
| :---------------------- | :------------------------------------------------------------------------------------ |
| `-i`, `--input <path>`  | Path to the OpenAPI Specification file (JSON or YAML).                                |
| `-o`, `--output <path>` | Path to the output directory for the generated Zig code (default: current directory). |
| `--base-url <url>`      | Base URL for the API client (default: server URL from OpenAPI Specification).         |

## Using as a Library

openapi2zig can also be used as a Zig library for parsing OpenAPI/Swagger specifications and generating code programmatically.

### Adding as a Dependency

Add openapi2zig to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .openapi2zig = .{
            .url = "https://github.com/christianhelle/openapi2zig/archive/refs/tags/v1.0.0.tar.gz",
            .hash = "12345...", // Replace with actual hash from `zig fetch`
        },
    },
}
```

Then in your `build.zig`:

```zig
const openapi2zig_dep = b.dependency("openapi2zig", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("openapi2zig", openapi2zig_dep.module("openapi2zig"));
```

### Library Usage Example

```zig
const std = @import("std");
const openapi2zig = @import("openapi2zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read OpenAPI specification
    const content = try std.fs.cwd().readFileAlloc(allocator, "api.json", 1024 * 1024);
    defer allocator.free(content);

    // Detect version
    const version = try openapi2zig.detectVersion(allocator, content);
    std.debug.print("Detected version: {}\n", .{version});

    // Parse to unified document representation
    var unified_doc = try openapi2zig.parseToUnified(allocator, content);
    defer unified_doc.deinit(allocator);

    std.debug.print("API: {s} v{s}\n", .{ unified_doc.info.title, unified_doc.info.version });

    // Generate Zig code
    const args = openapi2zig.CliArgs{
        .input_path = "api.json",
        .output_path = null,
        .base_url = "https://api.example.com",
    };

    const generated_code = try openapi2zig.generateCode(allocator, unified_doc, args);
    defer allocator.free(generated_code);

    // Write generated code to file
    try std.fs.cwd().writeFile(.{ .sub_path = "generated.zig", .data = generated_code });
}
```

### Library API Reference

#### Version Detection

- `detectVersion(allocator, json_content)` - Detect OpenAPI/Swagger version
- `ApiVersion` - Enum representing supported API versions (.v2_0, .v3_0, .v3_1, .v3_2, .Unsupported)

#### Parsing Functions

- `parseToUnified(allocator, json_content)` - Parse any supported version to unified representation
- `parseOpenApi(allocator, json_content)` - Parse OpenAPI v3.0 specifically
- `parseOpenApi32(allocator, json_content)` - Parse OpenAPI v3.2 specifically
- `parseSwagger(allocator, json_content)` - Parse Swagger v2.0 specifically

#### Code Generation

- `generateCode(allocator, unified_doc, args)` - Generate complete Zig code (models + API)
- `generateModels(allocator, unified_doc)` - Generate only model structs
- `generateApi(allocator, unified_doc, args)` - Generate only API client functions

#### Conversion Functions

- `convertOpenApiToUnified(allocator, openapi_doc)` - Convert OpenAPI v3.0 to unified format
- `convertOpenApi32ToUnified(allocator, openapi_doc)` - Convert OpenAPI v3.2 to unified format
- `convertSwaggerToUnified(allocator, swagger_doc)` - Convert Swagger v2.0 to unified format

#### Data Types

- `UnifiedDocument` - Common document representation for both OpenAPI and Swagger
- `OpenApiDocument` - OpenAPI v3.0 specific document structure
- `OpenApi32Document` - OpenAPI v3.2 specific document structure
- `SwaggerDocument` - Swagger v2.0 specific document structure
- `DocumentInfo`, `Schema`, `Operation`, etc. - Various OpenAPI components

## Example Generated Code

Below is an example of the Zig code generated from an OpenAPI specification.

### Models

```zig
const std = @import("std");

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

    var str = std.ArrayList(u8).init(allocator);
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
pub fn getPetById(allocator: std.mem.Allocator, petId: []const u8) !Pet {
    var client = std.http.Client { .allocator = allocator };
    defer client.deinit();

    var header_buffer: [8192]u8 = undefined;
    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet/{s}", .{petId});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.open(std.http.Method.GET, uri, .{ .server_header_buffer = &header_buffer, .extra_headers = headers });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    const response = req.response;
    if (response.status != .ok) {
        return error.ResponseError;
    }

    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024 * 4);
    defer allocator.free(body);

    const parsed = try std.json.parseFromSlice(Pet, allocator, body, .{});
    defer parsed.deinit();

    return parsed.value;
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

- OpenAPI v2.0, v3.0, and v3.2 specification parsing
- Basic data model structures for OpenAPI components
- Generate API client code using `std.http.Client`
- Comprehensive test suite for parsing functionality

Planned features:

- Improved CLI interface for code generation
- Authentication / Authorization support
- Documentation generation

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions, please [open an issue](https://github.com/christianhelle/openapi2zig/issues) on GitHub.
