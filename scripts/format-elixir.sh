#!/usr/bin/env bash
# Format Elixir code
set -e

cd "$(dirname "$0")/.."

echo "Formatting Elixir code..."
mix format

echo "Elixir formatting complete!"
