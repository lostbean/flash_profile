#!/usr/bin/env bash
# Pre-commit script: format, check, and test all code
set -e

cd "$(dirname "$0")/.."

SCRIPTS_DIR="scripts"

echo "========================================"
echo "  Pre-commit checks"
echo "========================================"
echo

# Format all code first
echo "--- Formatting ---"
"$SCRIPTS_DIR/format-elixir.sh"
"$SCRIPTS_DIR/format-zig.sh"
echo

# Run all checks
echo "--- Checking Elixir ---"
"$SCRIPTS_DIR/check-elixir.sh"
echo

echo "--- Checking Zig ---"
"$SCRIPTS_DIR/check-zig.sh"
echo

echo "========================================"
echo "  All pre-commit checks passed!"
echo "========================================"
