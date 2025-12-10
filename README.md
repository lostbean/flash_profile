# FlashProfile for Elixir

An Elixir implementation of Microsoft's FlashProfile algorithm for automatic
regex pattern discovery in string data.

> **Note:** This is a pure Elixir implementation with no native dependencies and
> not optimized for performance. For very large sets, consider sampling or
> batching your data for optimal performance.

## Overview

Given a column of string values from a database table, FlashProfile
automatically discovers regex patterns that accurately describe the structural
format of the data. It helps users understand:

- What format(s) their data follows
- Whether values are consistent or contain anomalies
- What constraints could be applied for data validation

## Installation

Add `flash_profile` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flash_profile, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Basic profiling
{:ok, profile} = FlashProfile.profile(["ACC-001", "ACC-002", "ORG-003", "ORG-004"])

# View the discovered pattern
IO.puts(hd(profile.patterns).regex)
# => "(ACC|ORG)-\d{3}"

# Validate new values against the profile
FlashProfile.validate(profile, "ACC-999")  # => :ok
FlashProfile.validate(profile, "INVALID")  # => {:error, :no_match}

# Get a human-readable summary
IO.puts(FlashProfile.summary(profile))
```

## Core Concepts

### Pattern Discovery

FlashProfile uses a two-stage process:

1. **Clustering**: Groups strings by structural similarity (delimiter patterns,
   token types)
2. **Synthesis**: For each cluster, generates an optimal regex pattern using
   cost-based optimization

### When to Enumerate vs. Generalize

The key insight is knowing when to enumerate specific values vs. use character
classes:

| Scenario                      | Approach   | Example                                   |
| ----------------------------- | ---------- | ----------------------------------------- |
| 4 status values, 10k rows     | Enumerate  | `(active\|pending\|completed\|cancelled)` |
| 1000 UUIDs                    | Generalize | `[a-f0-9]{8}-[a-f0-9]{4}-...`             |
| 4 prefixes, variable suffixes | Hybrid     | `(ACC\|ORG)-\d{5}`                        |

FlashProfile automatically makes this decision based on:

- Distinct value count vs. total count
- Repetition patterns (categorical data repeats)
- Cost model balancing specificity and generality

## Examples

### Categorical Enumeration

```elixir
# Status column with few distinct values
data = ["active", "pending", "completed", "cancelled"]
        |> List.duplicate(2500)
        |> List.flatten()

{:ok, profile} = FlashProfile.profile(data)
IO.puts(hd(profile.patterns).regex)
# => "(active|cancelled|completed|pending)"
```

### Structured Identifiers with Prefix Enumeration

```elixir
# Account references with known prefixes
data = [
  "ACC-00043", "ORG-00131", "ACCT-00055", "ACME-00107",
  "ACC-00044", "ORG-00132", "ACCT-00056", "ACME-00108"
]

{:ok, profile} = FlashProfile.profile(data)
IO.puts(hd(profile.patterns).regex)
# => "(ACC|ACCT|ACME|ORG)-\d{5}"
```

### Email Addresses

```elixir
data = ["alice.jones@company.org", "bob@test.io", "admin@company.org"]

{:ok, profile} = FlashProfile.profile(data)
IO.puts(hd(profile.patterns).regex)
# => "[a-z]+(\.[a-z]+)?@[a-z]+\.[a-z]+"
```

### Date/Time Patterns

```elixir
data = ["2024-Q1", "2024-Q2", "2024-Q3", "2024-Q4", "2025-Q1"]

{:ok, profile} = FlashProfile.profile(data)
IO.puts(hd(profile.patterns).regex)
# => "\d{4}-(Q1|Q2|Q3|Q4)"
```

### Anomaly Detection

```elixir
# 99% normal data + 1% anomalies
data = (for i <- 1..99, do: "ID-#{String.pad_leading(to_string(i), 3, "0")}") ++
       ["TOTALLY_DIFFERENT", "weird_value"]

{:ok, profile} = FlashProfile.profile(data)
IO.inspect(profile.anomalies)
# => ["TOTALLY_DIFFERENT", "weird_value"]
```

## API Reference

### Main Functions

#### `FlashProfile.profile/2`

Profiles a list of strings and returns discovered patterns.

```elixir
@spec profile([String.t()], keyword()) :: {:ok, profile()} | {:error, term()}

# Options:
# - :max_clusters - Maximum number of pattern clusters (default: 5)
# - :min_coverage - Minimum coverage for a pattern (default: 0.01)
# - :enum_threshold - Max distinct values before generalizing (default: 10)
# - :detect_anomalies - Whether to identify anomalies (default: true)
```

#### `FlashProfile.validate/2`

Validates a value against profile patterns.

```elixir
@spec validate(profile(), String.t()) :: :ok | {:error, :no_match}
```

#### `FlashProfile.infer_regex/2`

Quick function to get a regex for a list of strings.

```elixir
@spec infer_regex([String.t()], keyword()) :: String.t()

regex = FlashProfile.infer_regex(["A-1", "B-2", "C-3"])
# => "(A|B|C)-\d"
```

#### `FlashProfile.anomalies/1`

Returns values that don't match any discovered pattern.

```elixir
@spec anomalies(profile()) :: [String.t()]
```

### Pattern Module

Build patterns programmatically:

```elixir
alias FlashProfile.Pattern

# Create pattern elements
p = Pattern.seq([
  Pattern.enum(["ACC", "ORG"]),
  Pattern.literal("-"),
  Pattern.char_class(:digit, 3, 5)
])

# Convert to regex
Pattern.to_regex(p)
# => "(ACC|ORG)-\d{3,5}"

# Check if a pattern matches
Pattern.matches?(p, "ACC-1234")  # => true

# Get pattern cost (lower is better)
Pattern.cost(p)  # => 4.7

# Human-readable representation
Pattern.pretty(p)
# => "{ACC|ORG} \"-\" <digit{3-5}>"
```

### Tokenizer Module

Analyze string structure:

```elixir
alias FlashProfile.Tokenizer

# Tokenize a string
tokens = Tokenizer.tokenize("ACC-00123")
# => [%Token{type: :upper, value: "ACC"},
#     %Token{type: :delimiter, value: "-"},
#     %Token{type: :digits, value: "00123"}]

# Get structural signature
Tokenizer.signature("ACC-00123")
# => "UUU-DDDDD"

# Get compact signature (for clustering)
Tokenizer.compact_signature("ACC-00123")
# => "U-D"
```

## Architecture

```
flash_profile/
├── lib/
│   ├── flash_profile.ex           # Main API
│   └── flash_profile/
│       ├── token.ex               # Token data structures
│       ├── tokenizer.ex           # String → Token sequences
│       ├── pattern.ex             # Pattern DSL/AST
│       ├── clustering.ex          # Structural clustering
│       ├── pattern_synthesizer.ex # Pattern generation
│       └── cost_model.ex          # Quality evaluation
```

### How It Works

1. **Tokenization**: Strings are broken into tokens (digits, letters,
   delimiters)
2. **Signature Generation**: Tokens are converted to structural signatures
3. **Clustering**: Strings with similar structures are grouped
4. **Pattern Synthesis**: For each cluster:
   - Align tokens across all strings
   - For each position, decide: enumerate or generalize?
   - Apply cost model to choose optimal pattern
5. **Optimization**: Merge adjacent similar elements, simplify

### Cost Model

Patterns are evaluated on:

| Metric        | Definition               | Goal      |
| ------------- | ------------------------ | --------- |
| Coverage      | % of values matched      | ≥95%      |
| Precision     | Specificity of pattern   | ≥80%      |
| Complexity    | Pattern cost/readability | Low       |
| Cluster Count | Number of patterns       | 1-3 ideal |

## Configuration

### Enum Threshold

Controls when to enumerate vs. generalize:

```elixir
# Enumerate up to 20 distinct values
FlashProfile.profile(data, enum_threshold: 20)

# Only enumerate very small sets
FlashProfile.profile(data, enum_threshold: 5)
```

### Max Clusters

Limits the number of patterns:

```elixir
# Allow more patterns for complex data
FlashProfile.profile(data, max_clusters: 10)

# Force single unified pattern
FlashProfile.profile(data, max_clusters: 1)
```

## Use Cases

- **Data Validation**: Generate validation rules for form inputs
- **Data Quality**: Identify malformed or anomalous values
- **Schema Discovery**: Understand undocumented data formats
- **ETL Pipelines**: Create data transformation rules
- **Documentation**: Auto-generate format documentation

## Comparison with Alternatives

| Feature                  | FlashProfile | Simple Regex | Manual Rules |
| ------------------------ | ------------ | ------------ | ------------ |
| Automatic discovery      | ✓            | ✗            | ✗            |
| Handles multiple formats | ✓            | ✗            | ✓            |
| Anomaly detection        | ✓            | ✗            | ✓            |
| Cost-optimized           | ✓            | ✗            | ✗            |
| No training needed       | ✓            | ✓            | ✓            |

## Development

### Mix Commands

```bash
# Run before committing: format, compile with warnings-as-errors, test
mix precommit

# Run in CI: format, compile with warnings-as-errors, test, dialyzer
mix ci
```

### Running Tests

```bash
mix test
```

### Static Analysis

```bash
mix dialyzer
```

## References

- [FlashProfile Paper](https://www.microsoft.com/en-us/research/publication/flashprofile-interactive-synthesis-of-syntactic-profiles/) -
  Microsoft Research
- [PROSE SDK](https://microsoft.github.io/prose/) - Microsoft's Program
  Synthesis framework

## License

MIT License
