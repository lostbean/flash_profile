# FlashProfile.Pattern Module

Implementation of the Pattern module for FlashProfile, based on Definition 4.3 from the FlashProfile paper.

## Overview

A pattern is simply a sequence of atoms that match strings through greedy left-to-right matching. The empty pattern `[]` matches only the empty string `""`, while non-empty patterns match strings where each atom successfully matches a non-empty prefix in sequence, consuming the entire string.

## Module Location

`/code/edgar/flash_profile/lib/flash_profile/pattern.ex`

## Type Definition

```elixir
@type t :: [FlashProfile.Atom.t()]
```

A pattern is represented as a list of atoms.

## Core Functions

### Matching Functions

- **`matches?(pattern, string)`** - Returns `true` if pattern matches the entire string
- **`match(pattern, string)`** - Returns `{:ok, matches}` with detailed match information, or `{:error, :no_match}`
- **`match_lengths(pattern, string)`** - Returns list of match lengths for each atom, or `nil` if no match

### Pattern Construction

- **`empty()`** - Creates an empty pattern `[]`
- **`concat(pattern1, pattern2)`** - Concatenates two patterns
- **`append(pattern, atom)`** - Appends an atom to a pattern

### Pattern Inspection

- **`empty?(pattern)`** - Checks if pattern is empty
- **`length(pattern)`** - Returns number of atoms in pattern
- **`first(pattern)`** - Returns first atom, or `nil` if empty
- **`last(pattern)`** - Returns last atom, or `nil` if empty
- **`to_string(pattern)`** - Formats pattern as human-readable string

## Matching Algorithm

Patterns use **greedy left-to-right matching**:

1. Start at position 0 of the string
2. For each atom in order:
   - Call `atom.match(remaining_string)` to get match length
   - If length is 0, the pattern doesn't match
   - Otherwise, consume that many characters and continue with the next atom
3. After all atoms are processed, verify the entire string was consumed
4. If any step fails, return `{:error, :no_match}`

### Important Properties

- **Empty pattern**: Only matches empty string `""`
- **Non-empty prefixes**: Each atom must match at least 1 character (length > 0)
- **Greedy matching**: Each atom consumes the maximum possible characters
- **Complete consumption**: The entire string must be matched

## Pattern Display Format

The `to_string/1` function formats patterns using these conventions:

- **Constant strings**: Shown in quotes, e.g., `"PMC"`, `"-"`
- **Fixed-width char classes**: `Name×N`, e.g., `Digit×4`, `Upper×2`
- **Variable-width char classes**: `Name+`, e.g., `Lower+`, `Digit+`
- **Separator**: Atoms separated by ` ◇ `

### Examples

```elixir
"PMC" ◇ Digit×7                           # PMC IDs
Digit×4 ◇ "-" ◇ Digit×2 ◇ "-" ◇ Digit×2   # ISO dates
Upper+ ◇ "." ◇ Lower+ ◇ "@"               # Email prefix
```

## Usage Examples

### Example 1: PMC IDs

```elixir
alias FlashProfile.{Pattern, Atom}

pmc = Atom.constant("PMC")
digit7 = Atom.char_class("Digit", ~c"0123456789", 7, 8.2)
pattern = [pmc, digit7]

Pattern.matches?(pattern, "PMC1234567")  # => true
Pattern.matches?(pattern, "PMC123456")   # => false (only 6 digits)
Pattern.matches?(pattern, "PMC12345678") # => false (8 digits)

Pattern.to_string(pattern)
# => "PMC" ◇ Digit×7
```

### Example 2: ISO Date Format

```elixir
alias FlashProfile.{Pattern, Atom}

digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
dash = Atom.constant("-")
pattern = [digit4, dash, digit2, dash, digit2]

Pattern.matches?(pattern, "2024-12-11")  # => true
Pattern.matches?(pattern, "2024-1-11")   # => false (wrong month format)

Pattern.match_lengths(pattern, "2024-12-11")
# => [4, 1, 2, 1, 2]
```

### Example 3: Detailed Match Information

```elixir
alias FlashProfile.{Pattern, Atom}
alias FlashProfile.Atoms.CharClass

upper = CharClass.upper()
digit = CharClass.digit()
dash = Atom.constant("-")
pattern = [upper, dash, digit]

{:ok, matches} = Pattern.match(pattern, "AB-123")

# matches is a list of tuples: {atom, matched_string, position, length}
# [
#   {upper_atom, "AB", 0, 2},
#   {dash_atom, "-", 2, 1},
#   {digit_atom, "123", 3, 3}
# ]
```

### Example 4: Greedy Matching Behavior

```elixir
alias FlashProfile.Atoms.CharClass

lower = CharClass.lower()
pattern = [lower, lower]  # Two Lower+ atoms

Pattern.matches?(pattern, "hello")
# => false
#
# Explanation: The first Lower+ atom greedily consumes ALL lowercase
# letters ("hello"), leaving nothing for the second Lower+ atom.
# The pattern fails to match.
```

### Example 5: Pattern Composition

```elixir
alias FlashProfile.{Pattern, Atom}
alias FlashProfile.Atoms.CharClass

# Build patterns incrementally
prefix = [Atom.constant("http://")]
domain = [CharClass.alpha_digit(), Atom.constant("."), CharClass.alpha_digit()]

url_pattern = Pattern.concat(prefix, domain)

Pattern.matches?(url_pattern, "http://example.com")
# => true
```

## Integration with Other Modules

The Pattern module integrates with:

- **`FlashProfile.Atom`** - Atoms are the building blocks of patterns
- **`FlashProfile.Atoms.CharClass`** - Factory for common character class atoms
- **`FlashProfile.Cost`** - Uses `match_lengths/2` for cost calculations
- **`FlashProfile.Learner`** - Pattern learning algorithms use pattern matching

## Testing

Run the comprehensive examples:

```bash
mix run examples/pattern_examples.exs
```

This demonstrates:
- PMC ID matching
- Date format validation
- Email username patterns
- Capitalized word patterns
- Detailed match information
- Pattern composition
- Greedy matching behavior
- Utility functions

## Implementation Notes

1. **Greedy Matching**: Each atom matches its maximum prefix. This is crucial for correct behavior.

2. **Empty Pattern**: The empty pattern `[]` is special - it only matches the empty string `""`.

3. **Complete Consumption**: Patterns must consume the entire string. Partial matches are not allowed.

4. **Type Safety**: All functions include proper typespecs and guard clauses.

5. **Performance**: The matching algorithm is O(n × m) where n is string length and m is pattern length, with each atom's matching time dependent on its type.

## References

- FlashProfile paper, Definition 4.3 (Patterns)
- `/code/edgar/flash_profile/lib/flash_profile/atom.ex`
- `/code/edgar/flash_profile/examples/pattern_examples.exs`
