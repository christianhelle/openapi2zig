#!/bin/bash

# openapi2zig - Installation Script
# This script downloads and installs the latest release of openapi2zig

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="christianhelle/openapi2zig"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BINARY_NAME="openapi2zig"

# Functions
log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}" >&2
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}" >&2
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

log_error() {
  echo -e "${RED}❌ $1${NC}" >&2
}

detect_platform() {
  local os=$(uname -s | tr '[:upper:]' '[:lower:]')
  local arch=$(uname -m)

  case "$os" in
  linux*)
    os="linux"
    ;;
  darwin*)
    os="macos"
    ;;
  *)
    log_error "Unsupported operating system: $os"
    exit 1
    ;;
  esac

  case "$arch" in
  x86_64 | amd64)
    arch="x86_64"
    ;;
  aarch64 | arm64)
    arch="aarch64"
    ;;
  esac

  echo "${os}-${arch}"
}

check_dependencies() {
  local deps=("curl" "tar")

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_error "Required dependency '$dep' not found. Please install it first."
      exit 1
    fi
  done
}

get_latest_release() {
  log_info "Fetching latest release information..."
  local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

  if ! curl -s "$api_url" | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$'; then
    log_error "Failed to fetch release information"
    exit 1
  fi
}

download_and_install() {
  local platform="$1"
  local version="$2"
  local archive_name="openapi2zig-${platform}.tar.gz"
  local download_url="https://github.com/$GITHUB_REPO/releases/download/$version/$archive_name"
  local temp_dir=$(mktemp -d)

  log_info "Downloading openapi2zig $version for $platform..."

  if ! curl -L -o "$temp_dir/$archive_name" "$download_url"; then
    log_error "Failed to download openapi2zig"
    rm -rf "$temp_dir"
    exit 1
  fi

  log_info "Extracting archive..."
  if ! tar -xzf "$temp_dir/$archive_name" -C "$temp_dir"; then
    log_error "Failed to extract archive"
    rm -rf "$temp_dir"
    exit 1
  fi

  log_info "Installing to $INSTALL_DIR..."

  # Check if we need sudo
  if [ ! -w "$INSTALL_DIR" ]; then
    if command -v sudo >/dev/null 2>&1; then
      log_warning "Installing with sudo (directory not writable by current user)"
      sudo cp "$temp_dir/$BINARY_NAME" "$INSTALL_DIR/"
      sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"
    else
      log_error "Cannot write to $INSTALL_DIR and sudo is not available"
      log_info "Try setting INSTALL_DIR to a writable directory:"
      log_info "  INSTALL_DIR=\$HOME/.local/bin curl -fsSL https://christianhelle.com/openapi2zig/install | bash"
      rm -rf "$temp_dir"
      exit 1
    fi
  else
    cp "$temp_dir/$BINARY_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
  fi

  # Cleanup
  rm -rf "$temp_dir"

  log_success "openapi2zig $version installed successfully!"
}

verify_installation() {
  if command -v "$BINARY_NAME" >/dev/null 2>&1; then
    local installed_version=$($BINARY_NAME --version 2>/dev/null | head -n1 || echo "unknown")
    log_success "Installation verified: $installed_version"
    log_info "You can now run: $BINARY_NAME --help"
  else
    log_warning "Binary installed but not found in PATH"
    log_info "Make sure $INSTALL_DIR is in your PATH"
    log_info "Add this to your shell profile: export PATH=\"$INSTALL_DIR:\$PATH\""
  fi
}

show_usage() {
  echo "openapi2zig installation script"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help      Show this help message"
  echo "  -d, --dir DIR   Set installation directory (default: /usr/local/bin)"
  echo ""
  echo "Environment variables:"
  echo "  INSTALL_DIR     Installation directory (default: /usr/local/bin)"
  echo ""
  echo "Examples:"
  echo "  # Install to default location"
  echo "  curl -fsSL https://christianhelle.com/openapi2zig/install | bash"
  echo ""
  echo "  # Install to custom directory"
  echo "  INSTALL_DIR=\$HOME/.local/bin curl -fsSL https://christianhelle.com/openapi2zig/install | bash"
  echo ""
  echo "  # Install to custom directory using flag"
  echo "  curl -fsSL https://christianhelle.com/openapi2zig/install | bash -s -- --dir \$HOME/.local/bin"
}

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
      show_usage
      exit 0
      ;;
    -d | --dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
    esac
  done

  log_info "Starting openapi2zig installation..."
  log_info "Target directory: $INSTALL_DIR"

  # Detect platform
  local platform=$(detect_platform)
  log_info "Detected platform: $platform"

  # Check dependencies
  check_dependencies

  # Get latest release
  local version=$(get_latest_release)
  log_info "Latest version: $version"

  # Create install directory if it doesn't exist
  if [ ! -d "$INSTALL_DIR" ]; then
    log_info "Creating installation directory: $INSTALL_DIR"
    if ! mkdir -p "$INSTALL_DIR" 2>/dev/null; then
      if command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$INSTALL_DIR"
      else
        log_error "Cannot create directory $INSTALL_DIR"
        exit 1
      fi
    fi
  fi

  # Download and install
  download_and_install "$platform" "$version"

  # Verify installation
  verify_installation

  echo ""
  log_success "🎉 Installation complete!"
  log_info "Get started with: $BINARY_NAME --help"
  log_info "Documentation: https://christianhelle.com/openapi2zig/"
}

# Run main function with all arguments
main "$@"
