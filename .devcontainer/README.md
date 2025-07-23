# Dev Container for openapi2zig

This directory contains the development container configuration for the openapi2zig project, designed to work seamlessly with GitHub Codespaces and VS Code Dev Containers.

## What's Included

### Software
- **Zig 0.14.1** - The Zig programming language compiler
- **ZLS (Zig Language Server)** - Language server for Zig with IntelliSense support
- **Git** - Version control
- **Build tools** - Essential build utilities
- **Zsh** - Enhanced shell with Oh My Zsh

### VS Code Extensions
- **ziglang.vscode-zig** - Official Zig language support
- **ms-vscode.vscode-json** - JSON language support
- **redhat.vscode-yaml** - YAML language support  
- **GitHub.copilot** - AI pair programmer (if you have access)
- **GitHub.copilot-chat** - AI chat assistant (if you have access)

### Configuration
- Pre-configured ZLS settings for optimal Zig development
- Proper file associations for `.zig` files
- Terminal defaults to Zsh for better development experience

## Usage

### With GitHub Codespaces
1. Navigate to the repository on GitHub
2. Click the green "Code" button
3. Select "Codespaces" tab
4. Click "Create codespace on main" (or your current branch)
5. Wait for the environment to set up (usually 2-3 minutes)

### With VS Code Dev Containers (Local)
1. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open the project in VS Code
3. When prompted, click "Reopen in Container" or use Command Palette: "Dev Containers: Reopen in Container"
4. Wait for the container to build and configure

## Quick Start

Once your dev container is running:

```bash
# Build the project
zig build

# Run tests
zig build test

# Run the application
zig build run

# Install the binary locally
zig build install
```

## Development Workflow

The dev container provides a complete Zig development environment with:
- Syntax highlighting and IntelliSense
- Error checking and diagnostics
- Code formatting
- Integrated terminal with Zig and ZLS available
- Git integration

## Troubleshooting

### ZLS Not Working
If the Zig Language Server isn't providing IntelliSense:
1. Check VS Code Output panel for ZLS logs
2. Restart the language server: Command Palette → "Zig Language Server: Restart"
3. Verify ZLS config at `~/.config/zls/zls.json`

### Zig Version Issues
The container is configured for Zig 0.14.1. If you need a different version:
1. Modify `ZIG_VERSION` in `.devcontainer/setup.sh`
2. Rebuild the container: Command Palette → "Dev Containers: Rebuild Container"

### Permission Issues
If you encounter permission issues with files:
```bash
sudo chown -R vscode:vscode /workspaces/openapi2zig
```

## Configuration Files

- `devcontainer.json` - Main dev container configuration
- `setup.sh` - Setup script that installs Zig, ZLS, and other tools
- This `README.md` - Documentation

## Contributing

When making changes to the dev container configuration:
1. Test your changes by rebuilding the container
2. Update this README if you add new features or change requirements
3. Ensure the setup script remains idempotent (safe to run multiple times)
