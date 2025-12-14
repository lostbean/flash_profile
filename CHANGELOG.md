# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Division by zero in `atom.zig` for `constant()` and `withFixedWidth()` functions
- Unsafe timestamp cast in `profile.zig` using conditional bitcast
- Unsafe width cast in `learner.zig` using `std.math.cast`
- Replace assertions in `dissimilarity.zig` with bounds checks
- Convert recursive `learnPatternsRecursive` to iterative algorithm to prevent stack overflow

### Added

- Input validation module (`validation.zig`) with validation at all 6 NIF entry points
- Safety limits to prevent runaway computation:
  - `MAX_ITERATIONS` (1M) for pattern learning
  - `MAX_CACHE_ENTRIES` (10K) for PatternCache
  - `MAX_AHC_ITERATIONS` (100K) for hierarchical clustering
- 21 new validation tests (103 total Zig tests)

## [0.1.0] - 2025-12-13

### Added

- Core FlashProfile algorithm implementation based on the paper "FlashProfile: A Framework for Synthesizing Data Profiles"
- High-performance Zig NIF backend implementing:
  - Pattern learning algorithm (Figure 4)
  - Profile algorithm with hierarchical clustering
  - BigProfile algorithm for large datasets (Figure 12)
  - Dissimilarity computation (Definition 3.1)
- 17 default atoms from the paper (Figure 6):
  - Character classes: Lower, Upper, Digit, Alpha, AlphaDigit, Space, Any
  - Extended classes: Bin, Hex, Base64, AlphaSpace, AlphaDash, AlphaDigitSpace
  - Punctuation: DotDash, Punct, Symb
  - Constants (dynamically created)
- Pattern matching and cost calculation
- Comprehensive test suite with paper validation tests
- Elixir API with full documentation
