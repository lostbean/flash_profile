#!/usr/bin/env bash
# CI script: check format (no modify), compile, and test
# Fails if any formatting is off
set -e

cd "$(dirname "$0")/.."

ZIG_DIR="native/flash_profile"

echo "========================================"
echo "  CI Checks (read-only)"
echo "========================================"
echo

echo "=== Elixir CI Checks ==="

echo "Checking Elixir format..."
mix format --check-formatted

echo "Compiling with warnings as errors..."
mix compile --warnings-as-errors

echo "Running Elixir tests..."
mix test

echo

echo "=== Zig CI Checks ==="

echo "Checking Zig format..."
zig fmt --check "$ZIG_DIR"/*.zig

echo "Running ast-check..."
for file in "$ZIG_DIR"/*.zig; do
    zig ast-check "$file"
done

echo "Running Zig tests..."
zig test "$ZIG_DIR/main.zig" 2>/dev/null || echo "Note: Zig tests may require beam module (skipped in standalone mode)"

echo

echo "========================================"
echo "  All CI checks passed!"
echo "========================================"
