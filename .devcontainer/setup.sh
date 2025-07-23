#!/bin/bash
set -e

echo "🚀 Setting up Zig development environment..."

# Install required packages
sudo apt-get update
sudo apt-get install -y \
    curl \
    wget \
    xz-utils \
    build-essential \
    git

# Zig version to install
ZIG_VERSION="0.14.1"
ZIG_ARCH="x86_64-linux"

echo "📦 Installing Zig ${ZIG_VERSION}..."

# Download and install Zig
cd /tmp
wget -q "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz"
tar -xf "zig-linux-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz"
sudo mv "zig-linux-${ZIG_ARCH}-${ZIG_VERSION}" /usr/local/zig
sudo ln -sf /usr/local/zig/zig /usr/local/bin/zig

# Verify Zig installation
echo "✅ Zig version:"
zig version

# Install ZLS (Zig Language Server)
echo "📦 Installing ZLS (Zig Language Server)..."
cd /tmp
ZLS_VERSION="0.14.0"
wget -q "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-${ZIG_ARCH}-linux.tar.gz"
tar -xzf "zls-${ZIG_ARCH}-linux.tar.gz"
sudo mv zls /usr/local/bin/zls
sudo chmod +x /usr/local/bin/zls

# Verify ZLS installation
echo "✅ ZLS installed successfully"
which zls

# Create ZLS config
mkdir -p /home/vscode/.config/zls
cat > /home/vscode/.config/zls/zls.json << 'EOF'
{
    "enable_snippets": true,
    "enable_ast_check_diagnostics": true,
    "enable_autofix": true,
    "enable_import_embedfile_argument_completions": true,
    "warn_style": true,
    "highlight_global_var_declarations": true,
    "dangerous_comptime_experiments_do_not_enable": false,
    "skip_std_references": false,
    "prefer_ast_check_as_child_process": true,
    "record_session": false,
    "record_session_path": null,
    "replay_session_path": null,
    "builtin_path": null,
    "zig_lib_path": null,
    "zig_exe_path": "/usr/local/bin/zig",
    "build_runner_path": null,
    "global_cache_path": null,
    "build_runner_global_cache_path": null,
    "completion_label_details": true
}
EOF

# Set proper ownership
sudo chown -R vscode:vscode /home/vscode/.config

# Clean up
rm -rf /tmp/zig-linux-* /tmp/zls-*

echo "🎉 Zig development environment setup complete!"
echo "🔧 Zig version: $(zig version)"
echo "🔧 ZLS location: $(which zls)"
echo ""
echo "You can now:"
echo "  - Build the project: zig build"
echo "  - Run tests: zig build test"
echo "  - Run the application: zig build run"
