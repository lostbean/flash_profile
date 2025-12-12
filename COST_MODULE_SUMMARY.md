# FlashProfile Cost Module - Implementation Summary

## Overview

The `FlashProfile.Cost` module implements the cost function from the FlashProfile paper (Section 4.3) for evaluating and comparing pattern quality. The cost function balances pattern specificity vs simplicity using static costs and dynamic weights.

## Location

- **Module**: `/code/edgar/flash_profile/lib/flash_profile/cost.ex`
- **Tests**: `/code/edgar/flash_profile/test/flash_profile/cost_test.exs`
- **Demo**: `/code/edgar/flash_profile/examples/cost_demo.exs`

## Cost Formula

The cost function `C_FP(P, S)` is defined as:

```
C_FP(P, S) = Σ Q(αi) · W(i, S | P)
```

Where:
- `P = [α1, α2, ..., αk]` is a pattern (list of atoms)
- `Q(αi)` is the static cost of atom αi
- `W(i, S | P)` is the dynamic weight for atom i

### Dynamic Weight Formula

```
W(i, S | P) = (1/|S|) · Σ_{s∈S} (αi(si) / |s|)
```

Where:
- `s1 = s` (the original string)
- `si+1 = si[αi(si):]` (remaining suffix after matching atom αi)
- `αi(si)` is the length matched by atom i on string si
- `|s|` is the total length of the original string

The dynamic weight represents the average fraction of the original string length that each atom matches across all strings in the dataset.

## Core Functions

### 1. `calculate/2`

```elixir
@spec calculate(pattern(), [String.t()]) :: cost()
```

Calculates the cost of a pattern over a dataset.

**Returns**:
- `float()` - The cost of the pattern
- `:infinity` - If the pattern doesn't match all strings

**Examples**:
```elixir
# Simple pattern matching entirely
digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
Cost.calculate([digit], ["123"]) # => 8.2

# Pattern that doesn't match
Cost.calculate([digit], ["abc"]) # => :infinity

# Empty pattern on empty strings
Cost.calculate([], []) # => 0.0
```

### 2. `calculate_detailed/2`

```elixir
@spec calculate_detailed(pattern(), [String.t()]) ::
  {:ok, {float(), [{Atom.t(), float(), float()}]}} | {:error, term()}
```

Calculates cost with detailed breakdown per atom.

**Returns**:
- `{:ok, {total_cost, breakdown}}` - Success with detailed breakdown
  - `breakdown` is a list of `{atom, static_cost, dynamic_weight}` tuples
- `{:error, reason}` - Pattern doesn't match all strings

**Example**:
```elixir
upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
pattern = [upper, lower]

{:ok, {total, breakdown}} = Cost.calculate_detailed(pattern, ["Male", "Female"])
# breakdown => [
#   {upper_atom, 8.2, 0.2083},  # Upper matches "M"/"F"
#   {lower_atom, 9.1, 0.7917}   # Lower matches "ale"/"emale"
# ]
# total => 8.9125
```

### 3. `compare/3`

```elixir
@spec compare(pattern(), pattern(), [String.t()]) :: :lt | :eq | :gt
```

Compares two patterns by cost over the same dataset.

**Returns**:
- `:lt` - pattern1 is better (lower cost)
- `:eq` - patterns have equal cost
- `:gt` - pattern2 is better (lower cost)

**Example**:
```elixir
pattern1 = [upper, lower]
pattern2 = [alpha]
Cost.compare(pattern1, pattern2, ["Male", "Female"]) # => :lt
```

### 4. `min_cost/2`

```elixir
@spec min_cost([pattern()], [String.t()]) :: {pattern(), cost()} | nil
```

Finds the minimum cost pattern from a list.

**Returns**:
- `{pattern, cost}` - Best pattern and its cost
- `nil` - If patterns list is empty

**Example**:
```elixir
patterns = [[upper, lower], [alpha], [digit]]
{best, cost} = Cost.min_cost(patterns, ["Male", "Female"])
# Returns the pattern with lowest cost
```

## Implementation Details

### Pattern Matching Algorithm

The module includes a helper function `match_pattern_lengths/2` that:
1. Iteratively applies each atom in the pattern to the string
2. Tracks the length matched by each atom
3. Consumes the matched portion from the string
4. Returns `nil` if any atom fails to match or if there's a remainder

```elixir
# Example: [Upper, Lower] on "Male"
# Step 1: Upper matches "M" (length 1), remainder "ale"
# Step 2: Lower matches "ale" (length 3), remainder ""
# Result: [1, 3]
```

### Dynamic Weight Calculation

For each atom position, the dynamic weight is calculated as:
1. For each string in the dataset:
   - Get the length matched by the atom
   - Divide by the original string's total length
2. Average these fractions across all strings

```elixir
# Upper atom on ["Male", "Female"]
# "Male": 1/4 = 0.25
# "Female": 1/6 = 0.1667
# Average: (0.25 + 0.1667) / 2 = 0.2083
```

## Edge Cases

| Case | Pattern | Strings | Result | Reason |
|------|---------|---------|--------|--------|
| Empty/Empty | `[]` | `[]` | `0.0` | No cost for empty |
| Empty/Non-empty | `[]` | `["test"]` | `:infinity` | Can't match |
| Pattern/Empty | `[digit]` | `[]` | `0.0` | No strings to evaluate |
| No match | `[digit]` | `["abc"]` | `:infinity` | Pattern doesn't match |
| Partial match | `[digit, digit]` | `["123abc"]` | `:infinity` | Must consume entire string |

## Testing

The module includes comprehensive tests covering:

1. **Basic functionality**: Empty cases, simple matches, infinity cases
2. **Paper examples**: Male/Female example with exact cost calculations
3. **Detailed breakdown**: Verification of per-atom cost contributions
4. **Comparison**: Pattern comparison with various cost relationships
5. **Min cost**: Finding best pattern from multiple candidates
6. **Edge cases**: All boundary conditions

**Run tests**:
```bash
# Run all Cost module tests
mix test test/flash_profile/cost_test.exs

# Run with coverage
mix test --cover

# Run demonstration
mix run examples/cost_demo.exs
```

## Example from Paper

From Section 4.3 - Gender field example:

```elixir
# Define atoms
upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
alpha = Atom.char_class("Alpha", (?a..?z ++ ?A..?Z) |> Enum.to_list(), 15.0)

# Dataset
strings = ["Male", "Female"]

# Pattern 1: Upper ◇ Lower
pattern1 = [upper, lower]
cost1 = Cost.calculate(pattern1, strings)
# => 8.9125 (better - more specific)

# Pattern 2: Alpha
pattern2 = [alpha]
cost2 = Cost.calculate(pattern2, strings)
# => 15.0 (worse - too general)

# Pattern 1 is better
Cost.compare(pattern1, pattern2, strings) # => :lt
```

### Cost Breakdown

**Pattern 1 (Upper ◇ Lower)**:
- Upper atom:
  - Static cost: 8.2
  - Matches "M" in "Male" (1/4 = 0.25)
  - Matches "F" in "Female" (1/6 = 0.1667)
  - Dynamic weight: (0.25 + 0.1667) / 2 = 0.2083
  - Contribution: 8.2 × 0.2083 = 1.708

- Lower atom:
  - Static cost: 9.1
  - Matches "ale" in "Male" (3/4 = 0.75)
  - Matches "emale" in "Female" (5/6 = 0.8333)
  - Dynamic weight: (0.75 + 0.8333) / 2 = 0.7917
  - Contribution: 9.1 × 0.7917 = 7.204

- Total: 1.708 + 7.204 = **8.9125**

**Pattern 2 (Alpha)**:
- Alpha atom:
  - Static cost: 15.0
  - Matches entire "Male" (4/4 = 1.0)
  - Matches entire "Female" (6/6 = 1.0)
  - Dynamic weight: (1.0 + 1.0) / 2 = 1.0
  - Contribution: 15.0 × 1.0 = 15.0

- Total: **15.0**

Pattern 1 is better because it has lower cost (8.9125 < 15.0), capturing the specific structure (capitalized first letter followed by lowercase letters) rather than just "any letters".

## Integration

This module integrates with:
- `FlashProfile.Atom` - Uses atom matching and static cost functions
- `FlashProfile.Pattern` - Works with pattern type (list of atoms)
- `FlashProfile.Learner` - Will be used for pattern selection during learning

## Performance Considerations

- **Time Complexity**: O(|P| × |S| × avg_string_length) where |P| is pattern length and |S| is number of strings
- **Space Complexity**: O(|P| × |S|) for storing match lengths
- **Optimization**: Match lengths are computed once and reused for all atom weight calculations

## Future Enhancements

Potential improvements for the Cost module:
1. Caching of match results for repeated calculations
2. Parallel cost calculation for large datasets
3. Incremental cost updates when patterns change slightly
4. Cost normalization options for comparing across different dataset sizes
