# FlashProfile Scripts

Scripts for development, testing, and benchmarking FlashProfile.

## Quick Reference

```bash
# Format and test all code
./scripts/pre-commit.sh

# CI checks (read-only, fails on format issues)
./scripts/ci.sh

# Run benchmarks
mix run scripts/benchmark.exs           # Quick benchmark
mix run scripts/benchmark_zig.exs       # Detailed NIF benchmark

# Validate implementation
mix run scripts/validate_quality.exs    # Validate against paper
```

## Development Scripts

### `pre-commit.sh`
Formats and tests all Elixir and Zig code. Run before committing.

```bash
./scripts/pre-commit.sh
```

### `ci.sh`
Read-only CI checks. Fails if code is not formatted. Use in CI pipelines.

```bash
./scripts/ci.sh
```

### `format-elixir.sh` / `format-zig.sh`
Format code for a specific language.

```bash
./scripts/format-elixir.sh
./scripts/format-zig.sh
```

### `check-elixir.sh` / `check-zig.sh`
Format, compile, and test code for a specific language.

```bash
./scripts/check-elixir.sh
./scripts/check-zig.sh
```

## Benchmark Scripts

### `benchmark.exs`
Measures execution time for pattern learning and profiling on standard datasets.

```bash
mix run scripts/benchmark.exs
```

### `benchmark_zig.exs`
Detailed benchmark of Zig NIF functions with varying dataset sizes and types.

```bash
mix run scripts/benchmark_zig.exs
```

Tests:
- `FlashProfile.Native.learn_pattern_nif/1` - Pattern learning
- `FlashProfile.Native.dissimilarity_nif/2` - String pair dissimilarity
- `FlashProfile.Native.profile_nif/4` - Full profiling with clustering

### `validate_quality.exs`
Validates learned patterns against the FlashProfile paper's expected results.

```bash
mix run scripts/validate_quality.exs
```

Checks:
- Pattern coverage (100% for homogeneous data)
- Cost thresholds
- Required atom types (Digit, Lower, etc.)
