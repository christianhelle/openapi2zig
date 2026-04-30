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

All specifications are supported in JSON and YAML format.

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

```bash
openapi2zig generate [options]
```

The `generate` command reads a JSON OpenAPI/Swagger document from a local file or `http`/`https` URL, auto-detects the spec version, and writes one Zig source file containing models, runtime helpers, and API functions.

### Options

| Flag | Description |
| :--- | :--- |
| `-i`, `--input <PATH_OR_URL>` | OpenAPI/Swagger JSON or YAML spec from a file path or `http`/`https` URL. Required. |
| `-o`, `--output <path>` | Output file for the generated Zig code. Defaults to `generated.zig`. Parent directories are created when needed. |
| `--base-url <url>` | Base URL baked into the generated `Client`. Defaults to the server URL from the OpenAPI/Swagger document. |
| `--resource-wrappers <mode>` | Generate resource wrapper namespaces. Modes: `none`, `tags`, `paths`, `hybrid`. Defaults to `paths`. |

### Examples

**From a local file:**
```bash
openapi2zig generate -i openapi/v3.0/petstore.json -o api.zig
```

**From a local YAML file:**
```bash
openapi2zig generate -i openapi/v3.0/petstore.yaml -o api.zig
```

**From a remote URL:**
```bash
openapi2zig generate -i https://petstore3.swagger.io/api/v3/openapi.json -o api.zig
```

**Override the generated client's base URL:**
```bash
openapi2zig generate -i openapi/v3.0/petstore.json -o api.zig --base-url https://petstore3.swagger.io/api/v3
```

**Disable resource wrapper namespaces and keep only flat endpoint functions:**
```bash
openapi2zig generate -i openapi/v3.0/petstore.json -o api.zig --resource-wrappers none
```

### Generated sample files

The build script includes sample generation targets used by the test suite:

```bash
zig build run-generate-v2   # openapi/v2.0/petstore.json  -> generated/generated_v2.zig
zig build run-generate-v3   # openapi/v3.0/petstore.json  -> generated/generated_v3.zig
zig build run-generate-v31  # openapi/v3.1/webhook-example.json -> generated/generated_v31.zig
zig build run-generate-v32  # openapi/v3.2/petstore.json  -> generated/generated_v32.zig
zig build run-generate      # runs all of the above
```

`generated/main.zig` imports the v2 and v3 petstore outputs, initializes `Client` values, and exercises memory-managed endpoint calls. When Zig is available, validate generated examples with:

```bash
zig build run-generate
zig build test
zig test generated/compile_generated.zig
zig build-exe generated/main.zig -fno-emit-bin
zig build test-package
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

- `detectVersion(allocator, json_content)` - Detect OpenAPI/Swagger version from JSON
- `detectVersionFromYaml(allocator, yaml_content)` - Detect OpenAPI/Swagger version from YAML
- `ApiVersion` - Enum representing supported API versions (.v2_0, .v3_0, .v3_1, .v3_2, .Unsupported)

#### Parsing Functions

- `parseToUnified(allocator, json_content)` - Parse any supported JSON version (v2.0, v3.0, v3.1, v3.2) to unified representation
- `parseOpenApi(allocator, json_content)` - Parse OpenAPI v3.0 specifically
- `parseOpenApiYaml(allocator, yaml_content)` - Parse OpenAPI v3.0 YAML specifically
- `parseOpenApi31(allocator, json_content)` - Parse OpenAPI v3.1 specifically
- `parseOpenApi31Yaml(allocator, yaml_content)` - Parse OpenAPI v3.1 YAML specifically
- `parseOpenApi32(allocator, json_content)` - Parse OpenAPI v3.2 specifically
- `parseOpenApi32Yaml(allocator, yaml_content)` - Parse OpenAPI v3.2 YAML specifically
- `parseSwagger(allocator, json_content)` - Parse Swagger v2.0 specifically
- `parseSwaggerYaml(allocator, yaml_content)` - Parse Swagger v2.0 YAML specifically

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

## Generated Output Structure

Generated files are self-contained Zig source files. The current unified generator emits:

- Schema declarations such as `Pet`, `Order`, and nested helper types.
- A reusable `Client` struct with allocator, `std.Io`, `std.http.Client`, API key, base URL, optional organization/project headers, and borrowed `default_headers`. `default_headers` and all header name/value storage must stay alive while requests use them.
- Memory-safe response wrappers: `Owned(T)`, `RawResponse`, `ParseErrorResponse`, and `ApiResult(T)`.
- Endpoint triplets when a response schema is known:
  - `operation(...) !Owned(T)` for convenience parsed responses.
  - `operationRaw(...) !RawResponse` for status/body inspection.
  - `operationResult(...) !ApiResult(T)` for parsed success plus preserved API/parse-error bodies.
- Generic helpers such as `requestRaw`, `getRaw`, `postJsonRaw`, `getJsonResult`, and `postJsonResult`.
- Query parameter helpers that percent-encode names and string values with `std.Uri.Component.percentEncode`; optional query parameters are nullable.
- Bounded SSE parsing helpers: `parseSseBytes`, `parseSseReader`, `parseSseBytesTyped`, and `parseSseReaderTyped`. OpenAI-style stream helpers such as `streamChatCompletion`, `streamChatCompletionEvents`, `streamResponse`, and `streamResponseEvents` are generated when matching operation IDs exist in the input spec.
- Resource wrapper namespaces by default, for example `pet.get(...)` and `store.order.get(...)`, derived from paths unless `--resource-wrappers` changes the mode. Wrapper names are sanitized generated conveniences, not hand-designed SDK names.

Parsed JSON responses use `.ignore_unknown_fields = true` so compatible providers can add response fields without breaking callers. Ambiguous or intentionally open-ended schemas use `std.json.Value`; see [`docs/json-value-typing-policy.md`](docs/json-value-typing-policy.md) for the current policy. For OpenAPI 3.1, the converter has stronger composite-schema handling for object/ref `allOf`, preserved `oneOf`/`anyOf` metadata, and nullable type arrays; do not assume every converter has identical composite support.

## Example Generated Code

The snippets below reflect the current output from `zig build run-generate-v3`.

### Models

```zig
pub const Tag = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
};

pub const Category = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
};

pub const Pet = struct {
    status: ?[]const u8 = null,
    tags: ?[]const Tag = null,
    category: ?Category = null,
    id: ?i64 = null,
    name: []const u8,
    photoUrls: []const []const u8,
};
```

### Client and response wrappers

```zig
pub fn Owned(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        body: []u8,
        parsed: std.json.Parsed(T),

        pub fn deinit(self: *@This()) void {
            self.parsed.deinit();
            self.allocator.free(self.body);
        }

        pub fn value(self: *@This()) *T {
            return &self.parsed.value;
        }
    };
}

pub const RawResponse = struct {
    allocator: std.mem.Allocator,
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.body);
    }
};

pub fn ApiResult(comptime T: type) type {
    return union(enum) {
        ok: Owned(T),
        api_error: RawResponse,
        parse_error: ParseErrorResponse,

        pub fn deinit(self: *@This()) void {
            switch (self.*) {
                .ok => |*value| value.deinit(),
                .api_error => |*value| value.deinit(),
                .parse_error => |*value| value.raw.deinit(),
            }
        }
    };
}

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    http: std.http.Client,
    api_key: []const u8,
    base_url: []const u8 = "https://petstore3.swagger.io/api/v3",
    organization: ?[]const u8 = null,
    project: ?[]const u8 = null,
    default_headers: []const std.http.Header = &.{},

    pub fn init(allocator: std.mem.Allocator, io: std.Io, api_key: []const u8) Client {
        return .{
            .allocator = allocator,
            .io = io,
            .http = .{ .allocator = allocator, .io = io },
            .api_key = api_key,
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
    }

    pub fn withBaseUrl(self: *Client, base_url: []const u8) void {
        self.base_url = base_url;
    }
};
```

### Endpoint functions

```zig
pub fn getPetById(client: *Client, petId: i64) !Owned(Pet) {
    var result = try getPetByIdResult(client, petId);
    switch (result) {
        .ok => |ok| return ok,
        .api_error => |*err| {
            err.deinit();
            return error.ResponseError;
        },
        .parse_error => |*err| {
            err.raw.deinit();
            return error.ResponseParseError;
        },
    }
}

pub fn getPetByIdRaw(client: *Client, petId: i64) !RawResponse {
    const allocator = client.allocator;
    var uri_buf: std.Io.Writer.Allocating = .init(allocator);
    defer uri_buf.deinit();
    try uri_buf.writer.print("{s}/pet/{d}", .{ client.base_url, petId });
    const payload: ?[]const u8 = null;

    return requestRaw(client, std.http.Method.GET, uri_buf.written(), payload);
}

pub fn getPetByIdResult(client: *Client, petId: i64) !ApiResult(Pet) {
    return parseRawResponse(Pet, try getPetByIdRaw(client, petId));
}
```

### Calling generated code

```zig
var client = api.Client.init(allocator, io, "");
defer client.deinit();
client.withBaseUrl("https://petstore3.swagger.io/api/v3");

var pet = try api.getPetById(&client, 1);
defer pet.deinit();
std.debug.print("pet name: {s}\n", .{pet.value().name});

var result = try api.getPetByIdResult(&client, 1);
defer result.deinit();
switch (result) {
    .ok => |*ok| std.debug.print("pet id: {?}\n", .{ok.value().id}),
    .api_error => |raw| std.debug.print("HTTP status: {}\n{s}\n", .{ raw.status, raw.body }),
    .parse_error => |parse| std.debug.print("parse error: {s}\n{s}\n", .{ parse.error_name, parse.raw.body }),
}

// Default path resource wrappers are also exported:
var wrapped = try api.pet.get(&client, 1);
defer wrapped.deinit();
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
