#!/usr/bin/env bash
# Format Zig code
set -e

cd "$(dirname "$0")/.."

ZIG_DIR="native/flash_profile"

echo "Formatting Zig code..."
zig fmt "$ZIG_DIR"/*.zig

echo "Zig formatting complete!"
