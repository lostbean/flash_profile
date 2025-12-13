#!/usr/bin/env bash
# Check Elixir code: format, compile, and tests
# Fails on any error, warning, or test failure
set -e

cd "$(dirname "$0")/.."

echo "=== Elixir Checks ==="

# Check formatting (--check-formatted returns non-zero if files need formatting)
echo "Checking format..."
if ! mix format --check-formatted; then
    echo "ERROR: Elixir files are not formatted. Run: mix format"
    exit 1
fi

# Compile with warnings as errors (warnings MUST fail the build)
echo "Compiling (warnings as errors)..."
if ! mix compile --warnings-as-errors; then
    echo "ERROR: Compilation failed or has warnings!"
    exit 1
fi

# Run tests with warnings as errors (catches warnings in test files too)
# Note: capture_log is configured in test_helper.exs for clean output
echo "Running tests (warnings as errors)..."
if ! mix test --exclude slow --warnings-as-errors; then
    echo "ERROR: Elixir tests failed or have warnings!"
    exit 1
fi

echo "All Elixir checks passed!"
