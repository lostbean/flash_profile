#!/usr/bin/env bash
# Check Elixir code: format, compile warnings, and tests
set -e

cd "$(dirname "$0")/.."

echo "=== Elixir Checks ==="

echo "Formatting..."
mix format

echo "Compiling with warnings as errors..."
mix compile --warnings-as-errors

echo "Running tests..."
mix test

echo "Elixir checks passed!"
