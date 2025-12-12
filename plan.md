# FlashProfile Implementation Plan - Elixir

## Execution Workflow

1. **First**: Write this plan as `plan.md` in `/code/edgar/flash_profile/plan.md`
2. **For each task**: Launch a subagent with full context to implement
3. **After each implementation task**: Run tests to verify correctness
4. **Coordinator role**: Pass all necessary context (algorithms, data structures, dependencies) to subagents

## Overview

Implement the FlashProfile algorithm from the paper "FlashProfile: A Framework for Synthesizing Data Profiles" in Elixir. The system learns syntactic profiles for string collections - regex-like patterns that describe syntactic variations in strings.

## Project Structure

```
flash_profile/
├── mix.exs
├── lib/
│   ├── flash_profile.ex                    # Main API
│   ├── flash_profile/
│   │   ├── atom.ex                         # Atomic pattern definitions
│   │   ├── pattern.ex                      # Pattern composition & matching
│   │   ├── learner.ex                      # Pattern synthesis (LearnBestPattern)
│   │   ├── cost.ex                         # Cost function implementation
│   │   ├── clustering/
│   │   │   ├── hierarchy.ex                # Hierarchical clustering (AHC)
│   │   │   ├── dissimilarity.ex            # Dissimilarity matrix & sampling
│   │   │   └── linkage.ex                  # Complete-linkage criterion
│   │   ├── profile.ex                      # Profile generation (Profile algorithm)
│   │   ├── big_profile.ex                  # Large dataset profiling (BigProfile)
│   │   └── compress.ex                     # Profile compression (CompressProfile)
│   └── flash_profile/atoms/
│       ├── constant.ex                     # Const_s atom
│       ├── char_class.ex                   # Class^z_c atom
│       ├── regex.ex                        # RegEx_r atom
│       └── defaults.ex                     # Default atoms (Digit, Upper, Lower, etc.)
└── test/
    ├── test_helper.exs
    ├── flash_profile_test.exs
    ├── atom_test.exs
    ├── pattern_test.exs
    ├── learner_test.exs
    └── clustering_test.exs
```

## Implementation Tasks

### Task 1: Project Setup
Create the Mix project structure with mix.exs and basic configuration.

### Task 2: Atom Module (`lib/flash_profile/atom.ex`)
Define the atom behaviour and base types:
- `@callback match(string) :: non_neg_integer()` - returns length of matched prefix (0 = no match)
- `@callback cost() :: float()` - static cost of the atom
- Struct: `%Atom{type: atom_type, matcher: function, static_cost: float, params: map}`

### Task 3: Default Atoms (`lib/flash_profile/atoms/`)
Implement all default atoms from Figure 6 of the paper:
- **Character Classes**: Lower `[a-z]`, Upper `[A-Z]`, Digit `[0-9]`, Alpha `[a-zA-Z]`, etc.
- **Fixed-width variants**: `Class^z_c` that matches exactly z characters
- **Constant strings**: `Const_s` matching literal string s
- **Regex atoms**: `RegEx_r` for custom regex patterns

Default atoms with their regex patterns:
```
Lower: [a-z]              Bin: [01]
Upper: [A-Z]              Digit: [0-9]
TitleCaseWord: Upper◇Lower+   Hex: [a-fA-F0-9]
Alpha: [a-zA-Z]           AlphaDigit: [a-zA-Z0-9]
Space: \s                 AlphaDigitSpace: [a-zA-Z0-9\s]
DotDash: [.-]             Punct: [.,:?/-]
AlphaDash: [a-zA-Z-]      Symb: [-.,://@#$%&...]
AlphaSpace: [a-zA-Z\s]    Base64: [a-zA-Z0-9+=]
Any: . (matches any char)
```

### Task 4: Pattern Module (`lib/flash_profile/pattern.ex`)
Implement pattern composition and matching:
- Pattern is a list of atoms: `[atom1, atom2, ...]`
- `matches?(pattern, string)` - returns true if pattern describes string
- `match_with_positions(pattern, string)` - returns match positions for each atom
- Empty pattern matches only empty string ""

Matching semantics (from paper Section 4.1):
```
Pattern P describes string s iff atoms in P match contiguous non-empty
substrings of s, ultimately matching s in its entirety.
```

### Task 5: Cost Function (`lib/flash_profile/cost.ex`)
Implement the cost function C_FP from Section 4.3:
```
C_FP(P, S) = Σ Q(α_i) · W(i, S | P)
```
Where:
- `Q(α)` = static cost of atom α
- `W(i, S | P)` = dynamic weight = (1/|S|) · Σ_{s∈S} (α_i(s_i) / |s|)
- Dynamic weight is average fraction of string length matched by atom

Static costs (from paper):
- Const_s: proportional to 1/|s|
- Class^z_c (z ≥ 1): proportional to Q(Class^0_c) / z
- Default atoms: seeded by estimated size, penalized empirically

### Task 6: Pattern Learner (`lib/flash_profile/learner.ex`)
Implement LearnBestPattern algorithm:

```
func LearnBestPattern(S: String[])
  V ← L(S)  // Learn all consistent patterns
  if V = {} then return {Pattern: ⊥, Cost: ∞}
  P ← argmin_{P∈V} C(P, S)
  return {Pattern: P, Cost: C(P, S)}
```

Pattern synthesis approach:
1. Compute maximal compatible atoms: `max_compatible_atoms(S, atoms)`
2. Recursively build patterns by:
   - For each compatible atom α, compute suffix spec φ_α for remaining strings
   - Combine results using intersection at each step
3. Enrich atoms with:
   - All Const atoms from longest common prefixes
   - Fixed-width Class variants where width is consistent

Key function: `get_max_compatible_atoms(S, atoms)` from Figure 15

### Task 7: Dissimilarity Module (`lib/flash_profile/clustering/dissimilarity.ex`)
Implement syntactic dissimilarity measure η (Definition 3.1):
```
η(x, y) =
  0                           if x = y
  ∞                           if x ≠ y and V = {}
  min_{P∈V} C(P, {x,y})       otherwise
where V = L({x,y})
```

Implement SampleDissimilarities (Figure 9):
- Adaptively sample O(M̂·|S|) pairs
- Select seed strings that are most dissimilar to each other
- Cache learned patterns in dictionary D

Implement ApproxDMatrix (Figure 10):
- Use cached patterns to approximate dissimilarities
- Only call LearnBestPattern when no cached pattern describes the pair

### Task 8: Hierarchical Clustering (`lib/flash_profile/clustering/hierarchy.ex`)
Implement AHC algorithm (Figure 11):
```
func AHC(S, A)
  H ← {{s} | s ∈ S}  // Singleton sets
  while |H| > 1 do
    (X, Y) ← argmin_{X,Y∈H} η̂(X, Y | A)  // Complete-linkage
    H ← (H \ {X, Y}) ∪ {{X, Y}}
  return H
```

Complete-linkage criterion: `η̂(X, Y | A) = max_{x∈X, y∈Y} A[x,y]`

Implement Partition function to extract k clusters from hierarchy.

### Task 9: Profile Generation (`lib/flash_profile/profile.ex`)
Implement main Profile algorithm (Figure 4):
```
func Profile(S, m, M, θ)
  H ← BuildHierarchy(S, M, θ)
  P̃ ← {}
  for all X ∈ Partition(H, m, M) do
    {Pattern: P, Cost: c} ← LearnBestPattern(X)
    P̃ ← P̃ ∪ {⟨Data: X, Pattern: P⟩}
  return P̃
```

BuildHierarchy (Figure 8):
```
func BuildHierarchy(S, M, θ)
  M̂ ← ⌈θ·M⌉
  D ← SampleDissimilarities(S, M̂)
  A ← ApproxDMatrix(S, D)
  return AHC(S, A)
```

### Task 10: Profile Compression (`lib/flash_profile/compress.ex`)
Implement CompressProfile (Figure 13):
```
func CompressProfile(P̃, M)
  while |P̃| > M do
    (X, Y) ← argmin_{X,Y∈P̃} LearnBestPattern(X.Data ∪ Y.Data).Cost
    Z ← X.Data ∪ Y.Data
    P ← LearnBestPattern(Z).Pattern
    P̃ ← (P̃ \ {X, Y}) ∪ {⟨Data: Z, Pattern: P⟩}
  return P̃
```

### Task 11: BigProfile (`lib/flash_profile/big_profile.ex`)
Implement BigProfile for large datasets (Figure 12):
```
func BigProfile(S, m, M, θ, μ)
  P̃ ← {}
  while |S| > 0 do
    X ← SampleRandom(S, ⌈μ·M⌉)
    P̃' ← Profile(X, m, M, θ)
    P̃ ← CompressProfile(P̃ ∪ P̃', M)
    S ← RemoveMatchingStrings(S, P̃)
  return P̃
```

### Task 12: Main API (`lib/flash_profile.ex`)
Public API:
```elixir
defmodule FlashProfile do
  @doc "Profile a dataset with automatic cluster count"
  def profile(strings, opts \\ [])

  @doc "Profile with specific cluster count bounds"
  def profile(strings, min_patterns, max_patterns, opts \\ [])

  @doc "Profile large dataset with sampling"
  def big_profile(strings, opts \\ [])

  @doc "Learn best pattern for a set of strings"
  def learn_pattern(strings, opts \\ [])

  @doc "Compute syntactic dissimilarity between two strings"
  def dissimilarity(string1, string2, opts \\ [])

  @doc "Add custom atoms"
  def with_atoms(atoms)
end
```

Default options:
- `theta: 1.25` - pattern sampling factor
- `mu: 4.0` - string sampling factor
- `min_patterns: 1`
- `max_patterns: 10`
- `atoms: FlashProfile.Atoms.Defaults.all()`

### Task 13: Tests
Create comprehensive tests for:
- Individual atom matching
- Pattern composition and matching
- Cost function calculation
- Pattern learning
- Dissimilarity computation
- Clustering accuracy
- End-to-end profiling

## Data Structures

### Atom
```elixir
defmodule FlashProfile.Atom do
  defstruct [:type, :matcher, :static_cost, :params, :name]

  @type t :: %__MODULE__{
    type: :constant | :char_class | :regex | :function,
    matcher: (String.t() -> non_neg_integer()),
    static_cost: float(),
    params: map(),
    name: String.t()
  }
end
```

### Pattern
```elixir
# A pattern is simply a list of atoms
@type pattern :: [FlashProfile.Atom.t()]
```

### Profile Entry
```elixir
defmodule FlashProfile.ProfileEntry do
  defstruct [:data, :pattern, :cost]

  @type t :: %__MODULE__{
    data: [String.t()],
    pattern: FlashProfile.pattern(),
    cost: float()
  }
end
```

### Hierarchy Node
```elixir
defmodule FlashProfile.Clustering.Node do
  defstruct [:left, :right, :data, :height]

  @type t :: %__MODULE__{
    left: t() | nil,
    right: t() | nil,
    data: [String.t()],
    height: float()
  }
end
```

## Algorithm Constants

From paper's evaluation (Section 5):
- Default θ (theta) = 1.25 - pattern sampling factor
- Default μ (mu) = 4.0 - string sampling factor
- These achieve median NMI of 0.96 with 2.3x speedup

## Execution Order

1. Task 1: Project Setup
2. Task 2: Atom Module (base)
3. Task 3: Default Atoms
4. Task 4: Pattern Module
5. Task 5: Cost Function
6. Task 6: Pattern Learner
7. Task 7: Dissimilarity Module
8. Task 8: Hierarchical Clustering
9. Task 9: Profile Generation
10. Task 10: Profile Compression
11. Task 11: BigProfile
12. Task 12: Main API
13. Task 13: Tests

## Key Considerations

1. **Performance**: Use ETS or process dictionary for caching learned patterns during dissimilarity computation
2. **Parallelism**: Consider using Task.async for independent pattern learning calls
3. **Memory**: For large datasets, stream processing where possible
4. **Extensibility**: Design atom system to easily add custom atoms via behaviour

## Implementation Decisions

Based on user input:
- **Pattern Learner**: Full incremental synthesis approach (computing maximal compatible atoms at each step)
- **Atoms**: All 20+ default atoms from Figure 6
- **Scale**: Include BigProfile algorithm for large dataset handling
- **Testing**: Both ExUnit tests AND property-based testing with StreamData

## Dependencies (mix.exs)

```elixir
defp deps do
  [
    {:stream_data, "~> 1.0", only: [:test, :dev]}
  ]
end
```
