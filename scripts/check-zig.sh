#!/usr/bin/env bash
# Check Zig code: format, ast-check, and tests
# Fails on any error, warning, or test failure
set -e

cd "$(dirname "$0")/.."

ZIG_DIR="native/flash_profile"

echo "=== Zig Checks ==="

# Check formatting (--check flag returns non-zero if files need formatting)
echo "Checking format..."
if ! zig fmt --check "$ZIG_DIR"/*.zig; then
    echo "ERROR: Zig files are not formatted. Run: zig fmt $ZIG_DIR/*.zig"
    exit 1
fi

# Run ast-check on all files (catches syntax errors and some warnings)
echo "Running ast-check..."
for file in "$ZIG_DIR"/*.zig; do
    if ! zig ast-check "$file"; then
        echo "ERROR: ast-check failed for $file"
        exit 1
    fi
done

# Run Zig tests - this MUST fail if tests fail
echo "Running Zig tests..."
if ! zig test "$ZIG_DIR/main.zig"; then
    echo "ERROR: Zig tests failed!"
    exit 1
fi

echo "All Zig checks passed!"
