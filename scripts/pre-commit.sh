#!/usr/bin/env bash
# Pre-commit script: format, check, and test all code
# This script MUST fail if any check fails
# Runs Zig checks first (faster), then Elixir
set -e

cd "$(dirname "$0")/.."

SCRIPTS_DIR="scripts"

echo "========================================"
echo "  Pre-commit checks"
echo "========================================"
echo

# Format all code first
echo "--- Formatting ---"
"$SCRIPTS_DIR/format-zig.sh"
"$SCRIPTS_DIR/format-elixir.sh"
echo

# Run Zig checks first (faster feedback)
echo "--- Checking Zig ---"
if ! "$SCRIPTS_DIR/check-zig.sh"; then
    echo ""
    echo "========================================"
    echo "  FAILED: Zig checks failed!"
    echo "========================================"
    exit 1
fi
echo

# Run Elixir checks (format, compile, tests)
echo "--- Checking Elixir ---"
if ! "$SCRIPTS_DIR/check-elixir.sh"; then
    echo ""
    echo "========================================"
    echo "  FAILED: Elixir checks failed!"
    echo "========================================"
    exit 1
fi
echo

echo "========================================"
echo "  All pre-commit checks passed!"
echo "========================================"
