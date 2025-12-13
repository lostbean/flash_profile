#!/usr/bin/env bash
# CI script: check format (no modify), compile, and test
# Fails on any error or test failure
# Runs Zig checks first (faster), then Elixir
set -e

cd "$(dirname "$0")/.."

ZIG_DIR="native/flash_profile"

echo "========================================"
echo "  CI Checks (read-only)"
echo "========================================"
echo

echo "=== Zig CI Checks ==="

echo "Checking Zig format..."
if ! zig fmt --check "$ZIG_DIR"/*.zig; then
    echo "ERROR: Zig files are not formatted!"
    exit 1
fi

echo "Running ast-check..."
for file in "$ZIG_DIR"/*.zig; do
    if ! zig ast-check "$file"; then
        echo "ERROR: ast-check failed for $file"
        exit 1
    fi
done

echo "Running Zig tests..."
if ! zig test "$ZIG_DIR/main.zig"; then
    echo "ERROR: Zig tests failed!"
    exit 1
fi

echo

echo "=== Elixir CI Checks ==="

echo "Checking Elixir format..."
if ! mix format --check-formatted; then
    echo "ERROR: Elixir files are not formatted!"
    exit 1
fi

echo "Compiling..."
if ! mix compile; then
    echo "ERROR: Compilation failed!"
    exit 1
fi

echo "Running Elixir tests..."
if ! mix test --exclude slow; then
    echo "ERROR: Elixir tests failed!"
    exit 1
fi

echo

echo "========================================"
echo "  All CI checks passed!"
echo "========================================"
