# FlashProfile Scripts

Scripts for development, testing, and benchmarking FlashProfile.

## Quick Reference

```bash
# Format and test all code
./scripts/pre-commit.sh

# CI checks (read-only, fails on format issues)
./scripts/ci.sh

# Run benchmarks
mix run scripts/benchmark.exs                            # Quick benchmark
FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark_elixir.exs  # Detailed Elixir benchmark
mix run scripts/benchmark_comparison.exs                 # Compare Zig vs Elixir
mix run scripts/compare.exs                              # Compare backends

# Validate implementations
mix run scripts/compare_results.exs                      # Verify Zig NIF vs Elixir equivalence
mix run scripts/validate_quality.exs                     # Validate against paper
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
Measures execution time for pattern learning and profiling.

```bash
# Run with Zig backend (default)
mix run scripts/benchmark.exs

# Run with pure Elixir backend
FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark.exs
```

### `benchmark_elixir.exs`
Detailed benchmark of pure Elixir implementation functions.

```bash
FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark_elixir.exs
```

Tests:
- `FlashProfile.Learner.learn_best_pattern/2` - Pattern learning
- `FlashProfile.Clustering.Dissimilarity.compute/3` - String pair dissimilarity
- `FlashProfile.Profile.profile/4` - Full profiling with clustering

Output includes:
- Average execution time (10 iterations)
- Learned patterns and costs
- Dissimilarity values

### `benchmark_comparison.exs`
Compares Zig and Elixir backends head-to-head on the same operations.

```bash
mix run scripts/benchmark_comparison.exs
```

Output includes:
- Side-by-side execution times
- Speedup ratios
- Overall statistics

### `validate_quality.exs`
Validates learned patterns against the FlashProfile paper's expected results.

```bash
mix run scripts/validate_quality.exs
```

Checks:
- Pattern coverage (100% for homogeneous data)
- Cost thresholds
- Required atom types (Digit, Lower, etc.)

### `compare.exs`
Compares Zig and pure Elixir backends side-by-side.

```bash
mix run scripts/compare.exs
```

Output includes:
- Performance comparison (execution time)
- Quality comparison (cost values, coverage)
- Whether results are identical

### `compare_results.exs`
Comprehensive verification that Zig NIF and Elixir implementations produce equivalent results.

```bash
mix run scripts/compare_results.exs
```

Tests 5 key areas:
1. **learn_pattern** - Pattern learning produces same/similar patterns and costs
2. **dissimilarity** - Pairwise string dissimilarity matches (within FP tolerance)
3. **profile** - Dataset profiling produces same number of clusters
4. **calculate_cost** - Cost calculation matches for given patterns
5. **matches** - Pattern matching behavior is identical

Output includes:
- PASS/FAIL status for each test case
- Detailed comparison when results differ
- Core functionality vs enhanced features breakdown
- Summary statistics

See `/code/edgar/flash_profile/scripts/COMPARISON_RESULTS.md` for latest results.

## Backend Configuration

Set the backend via environment variable:

```bash
# Use Zig NIFs (default)
FLASH_PROFILE_BACKEND=zig mix run scripts/benchmark.exs

# Use pure Elixir
FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark.exs
```

Or in `config/config.exs`:

```elixir
config :flash_profile, :backend, :zig  # or :elixir
```
