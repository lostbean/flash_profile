# FlashProfile

High-performance syntactic pattern discovery for string data.

FlashProfile learns regex-like patterns that describe the syntactic structure of
string collections. Given a column of data, it automatically discovers what
formats are present and how strings are structured.

> **Note:** This implementation uses a Zig NIF backend for high performance. The
> Zig code is compiled automatically via
> [Zigler](https://github.com/ityonemo/zigler) during `mix compile`.

## Overview

Given a column of string values, FlashProfile automatically discovers patterns
that describe the data:

- What format(s) the data follows
- Whether values are consistent or contain anomalies
- What structure could be used for validation

This is an implementation of the FlashProfile algorithm from the paper
["FlashProfile: A Framework for Synthesizing Data Profiles"](https://doi.org/10.1145/3276520)
by Saswat Padhi et al.

## Installation

Add `flash_profile` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flash_profile, "~> 0.1.0"}
  ]
end
```

**Requirements:**

- Elixir ~> 1.14
- Zig is downloaded automatically by Zigler during compilation

## Quick Start

```elixir
# Profile a dataset - automatically discovers patterns
profile = FlashProfile.profile(["PMC1234567", "PMC9876543", "PMC1111111"])
# => [%ProfileEntry{pattern: [Const("PMC"), Digit+], cost: 12.3, data: [...]}]

# Learn a single pattern for similar strings
{pattern, cost} = FlashProfile.learn_pattern(["2024-01-15", "2023-12-31", "2025-06-20"])
# => {[Digit+, Const("-"), Digit+, Const("-"), Digit+], 15.2}

# Check if a pattern matches a string
FlashProfile.matches?(pattern, "2024-12-13")
# => true

# Profile large datasets efficiently with BigProfile
large_data = for i <- 1..10000, do: "ID-#{String.pad_leading(to_string(i), 5, "0")}"
profile = FlashProfile.big_profile(large_data)
```

## Core Concepts

### Atoms

Atomic patterns that match string prefixes:

- **Character classes**: `Digit`, `Lower`, `Upper`, `Alpha`, `AlphaDigit`,
  `Space`, etc.
- **Constants**: Literal strings like `"PMC"`, `"-"`, `"@"`
- **Special classes**: `Hex`, `Base64`, `Any`

### Patterns

Sequences of atoms that describe strings:

- `[Const("PMC"), Digit+]` matches "PMC1234567"
- `[Digit×4, Const("-"), Digit×2, Const("-"), Digit×2]` matches "2024-12-13"
- Patterns match greedily from left to right

### Profiles

Collections of pattern entries, each describing a cluster of similar strings:

- Automatically determines optimal number of patterns
- Uses hierarchical clustering based on syntactic dissimilarity
- Returns patterns sorted by cost (lowest = best)

### Cost Function

Measures pattern quality using:

- **Static cost**: Inherent complexity of atoms (from paper Figure 6)
- **Dynamic cost**: Variability in how atoms match the data
- Lower cost = better, more specific pattern

## Examples

### PMC IDs

```elixir
data = ["PMC1234567", "PMC9876543", "PMC5555555"]
profile = FlashProfile.profile(data)

# Pattern learned: "PMC" followed by digits
hd(profile).pattern |> FlashProfile.pattern_to_string()
# => "\"PMC\" ◇ Digit+"
```

### Date Formats

```elixir
dates = ["2024-01-15", "2023-12-31", "2025-06-20"]
{pattern, _cost} = FlashProfile.learn_pattern(dates)

FlashProfile.pattern_to_string(pattern)
# => "Digit+ ◇ \"-\" ◇ Digit+ ◇ \"-\" ◇ Digit+"

FlashProfile.matches?(pattern, "2024-12-13")
# => true
```

### Mixed Data with Multiple Patterns

```elixir
# Data with different formats
data = [
  "PMC123", "PMC456", "PMC789",           # PMC IDs
  "2024-01-01", "2024-02-15",             # Dates
  "user@example.com", "admin@test.org"    # Emails
]

profile = FlashProfile.profile(data, min_patterns: 2, max_patterns: 5)

# Profile discovers multiple patterns automatically
Enum.each(profile, fn entry ->
  IO.puts("Pattern: #{FlashProfile.pattern_to_string(entry.pattern)}")
  IO.puts("  Matches: #{length(entry.data)} strings")
  IO.puts("  Cost: #{entry.cost}")
end)
```

### Computing Dissimilarity

```elixir
# Similar strings have low dissimilarity
FlashProfile.dissimilarity("ABC123", "DEF456")
# => 17.3 (same structure)

# Different structures have higher dissimilarity
FlashProfile.dissimilarity("ABC123", "hello-world")
# => 25.8 (different structure)
```

## API Reference

### Main Functions

| Function              | Description                                     |
| --------------------- | ----------------------------------------------- |
| `profile/2`           | Profile dataset with automatic cluster count    |
| `profile/4`           | Profile with specific min/max pattern bounds    |
| `big_profile/2`       | Profile large datasets using sampling           |
| `learn_pattern/2`     | Learn single best pattern for strings           |
| `dissimilarity/3`     | Compute syntactic dissimilarity between strings |
| `matches?/2`          | Check if pattern matches string                 |
| `pattern_to_string/1` | Convert pattern to human-readable string        |
| `default_atoms/0`     | Get all 17 default atoms                        |

### Options

| Option          | Default | Description                         |
| --------------- | ------- | ----------------------------------- |
| `:min_patterns` | 1       | Minimum patterns in profile         |
| `:max_patterns` | 10      | Maximum patterns in profile         |
| `:theta`        | 1.25    | Pattern sampling factor             |
| `:mu`           | 4.0     | String sampling factor (BigProfile) |

## Performance

This implementation uses a Zig NIF backend that provides significant performance
improvements over pure Elixir:

- **6-77x faster** than equivalent Elixir implementation
- Efficient memory usage with arena allocators
- Optimized character class matching using 128-bit bitmaps

See the [scalability report](12-2025-scalability-report.md) for detailed
benchmarks.

### Recommendations

| Dataset Size            | Recommended Function               |
| ----------------------- | ---------------------------------- |
| < 1,000 strings         | `profile/2`                        |
| 1,000 - 100,000 strings | `big_profile/2`                    |
| > 100,000 strings       | Sample first, then `big_profile/2` |

## Architecture

```
flash_profile/
├── lib/
│   ├── flash_profile.ex           # Main API
│   └── flash_profile/
│       ├── atom.ex                # Atom definitions
│       ├── pattern.ex             # Pattern operations
│       ├── profile_entry.ex       # Profile entry struct
│       ├── native.ex              # Zig NIF bindings
│       └── atoms/                 # Default atom implementations
├── native/flash_profile/          # Zig implementation
│   ├── atom.zig                   # Atom matching
│   ├── pattern.zig                # Pattern operations
│   ├── cost.zig                   # Cost calculations
│   ├── learner.zig                # Pattern learning
│   ├── hierarchy.zig              # Hierarchical clustering
│   ├── profile.zig                # Profile/BigProfile algorithms
│   └── nif.zig                    # NIF interface
```

## References

- [FlashProfile Paper](https://doi.org/10.1145/3276520) - Original research
  paper
- [arXiv preprint](https://arxiv.org/abs/1709.05725) - Extended version

## Development

```bash
# Run tests
mix test

# Format code
mix format

# Pre-commit checks (format + compile + test)
mix precommit

# CI checks (format check + compile + test)
mix ci

# Generate documentation
mix docs
```

## License

MIT License - see [LICENSE](LICENSE) for details.
