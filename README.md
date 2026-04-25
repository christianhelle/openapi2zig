# openapi2zig

[![CI](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml/badge.svg)](https://github.com/christianhelle/openapi2zig/actions/workflows/ci.yml)
[![Zig Version](https://img.shields.io/badge/zig-0.16.0%2B-orange.svg)](https://ziglang.org/download/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A CLI tool and Zig library that generates type-safe API client code from OpenAPI specifications.

> **Note**: This project provides both a CLI tool for generating Zig code from OpenAPI specs and a library for parsing and working with OpenAPI documents programmatically in Zig.

## Supported Specifications

This tool supports the following OpenAPI and Swagger specifications:
- **Swagger v2.0** - Full support
- **OpenAPI v3.0** - Full support
- **OpenAPI v3.1** - Full support
- **OpenAPI v3.2** - Full support

All specifications are supported in JSON format. YAML support may be added in future releases.

## Features

- Parse and generate from Swagger v2.0, OpenAPI v3.0, v3.1, and v3.2 specifications
- Generate type-safe Zig client code
- Support for complex OpenAPI schemas and operations
- Cross-platform support (Linux, macOS, Windows)
- Available as both CLI tool and Zig library
- Unified document representation for all OpenAPI and Swagger versions

## Prerequisites

- [Zig](https://ziglang.org/download/) v0.16.0 or newer

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

Make sure you have Zig installed (version 0.16.0 or newer).

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

| Flag                           | Description                                                                           |
| :----------------------------- | :------------------------------------------------------------------------------------ |
| `-i`, `--input <PATH_OR_URL>`  | OpenAPI/Swagger spec (file path or http/https URL).                                   |
| `-o`, `--output <path>`        | Path to the output directory for the generated Zig code (default: current directory). |
| `--base-url <url>`             | Base URL for the API client (default: server URL from OpenAPI Specification).         |

### Examples

**From a local file:**
```bash
openapi2zig generate -i ./openapi/petstore.json -o api.zig
```

**From a remote URL:**
```bash
openapi2zig generate -i https://petstore3.swagger.io/api/v3/openapi.json -o api.zig
```

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

The repository includes a minimal downstream consumer fixture in `examples/package_consumer/`, and `zig build test-package` builds it against a clean package snapshot so ignored local files cannot mask packaging issues.

### Library Usage Example

```zig
const std = @import("std");
const openapi2zig = @import("openapi2zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Read OpenAPI specification
    const content = try std.Io.Dir.cwd().readFileAlloc(io, "api.json", allocator, .limited(1024 * 1024));
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
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "generated.zig", .data = generated_code });
}
```

### Library API Reference

#### Version Detection

- `detectVersion(allocator, json_content)` - Detect OpenAPI/Swagger version
- `ApiVersion` - Enum representing supported API versions (.v2_0, .v3_0, .v3_1, .v3_2, .Unsupported)

#### Parsing Functions

- `parseToUnified(allocator, json_content)` - Parse any supported version (v2.0, v3.0, v3.1, v3.2) to unified representation
- `parseOpenApi(allocator, json_content)` - Parse OpenAPI v3.0 specifically
- `parseOpenApi31(allocator, json_content)` - Parse OpenAPI v3.1 specifically
- `parseOpenApi32(allocator, json_content)` - Parse OpenAPI v3.2 specifically
- `parseSwagger(allocator, json_content)` - Parse Swagger v2.0 specifically

#### Code Generation

- `generateCode(allocator, unified_doc, args)` - Generate complete Zig code (models + API)
- `generateModels(allocator, unified_doc)` - Generate only model structs
- `generateApi(allocator, unified_doc, args)` - Generate only API client functions

#### Conversion Functions

- `convertSwaggerToUnified(allocator, swagger_doc)` - Convert Swagger v2.0 to unified format
- `convertOpenApiToUnified(allocator, openapi_doc)` - Convert OpenAPI v3.0 to unified format
- `convertOpenApi31ToUnified(allocator, openapi_doc)` - Convert OpenAPI v3.1 to unified format
- `convertOpenApi32ToUnified(allocator, openapi_doc)` - Convert OpenAPI v3.2 to unified format

#### Data Types

- `UnifiedDocument` - Common document representation for all OpenAPI and Swagger versions
- `SwaggerDocument` - Swagger v2.0 specific document structure
- `OpenApiDocument` - OpenAPI v3.0 specific document structure
- `OpenApi31Document` - OpenAPI v3.1 specific document structure
- `OpenApi32Document` - OpenAPI v3.2 specific document structure
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
pub fn placeOrder(allocator: std.mem.Allocator, io: std.Io, requestBody: Order) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse("https://petstore.swagger.io/api/v3/store/order");
    var req = try client.request(.POST, uri, .{});
    defer req.deinit();

    var str: std.Io.Writer.Allocating = .init(allocator);
    defer str.deinit();

    try std.json.Stringify.value(requestBody, .{}, &str.writer);
    const body = str.written();

    try req.sendBodyComplete(body);
}

/////////////////
// Summary:
// Find pet by ID
//
// Description:
// Returns a single pet
//
pub fn getPetById(allocator: std.mem.Allocator, io: std.Io, petId: []const u8) !Pet {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const headers = &[_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    };

    const uri_str = try std.fmt.allocPrint(allocator, "https://petstore3.swagger.io/api/v3/pet/{s}", .{petId});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(std.http.Method.GET, uri, .{ .extra_headers = headers });
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buffer: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);
    if (response.head.status != .ok) {
        return error.ResponseError;
    }

    var reader_buffer: [100]u8 = undefined;
    const body_reader = response.reader(&reader_buffer);
    const body = try body_reader.readAlloc(allocator, response.head.content_length orelse 1024 * 1024 * 4);
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

🚀 **Active Development** 🚀

This project is in active development with solid foundation for OpenAPI/Swagger support. Current capabilities include:

- Full parsing support for Swagger v2.0, OpenAPI v3.0, v3.1, and v3.2 specifications
- Comprehensive data model structures for all OpenAPI versions
- Generate type-safe API client code using `std.http.Client`
- Extensive test suite covering all specification versions
- Cross-compilation support (Linux, macOS, Windows)
- Both CLI tool and Zig library interfaces

Planned features and enhancements:

- YAML specification format support
- Enhanced authentication/authorization client support
- Automatic API documentation generation
- Performance optimizations for large specifications

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions, please [open an issue](https://github.com/christianhelle/openapi2zig/issues) on GitHub.
