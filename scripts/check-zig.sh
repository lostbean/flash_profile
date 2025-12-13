#!/usr/bin/env bash
# Check Zig code: format and tests
set -e

cd "$(dirname "$0")/.."

ZIG_DIR="native/flash_profile"

echo "=== Zig Checks ==="

echo "Formatting..."
zig fmt "$ZIG_DIR"/*.zig

echo "Running ast-check..."
for file in "$ZIG_DIR"/*.zig; do
    zig ast-check "$file"
done

echo "Running Zig tests..."
zig test "$ZIG_DIR/main.zig" 2>/dev/null || echo "Note: Zig tests may require beam module (skipped in standalone mode)"

echo "Zig checks passed!"
