defmodule FlashProfile do
  @moduledoc """
  FlashProfile: A Framework for Synthesizing Data Profiles

  FlashProfile learns syntactic profiles for string collections -
  regex-like patterns that describe syntactic variations in strings.

  This library implements the FlashProfile algorithm from the paper
  "FlashProfile: A Framework for Synthesizing Data Profiles" by
  Saswat Padhi et al.

  ## Paper Reference

  - Paper: https://doi.org/10.1145/3276520
  - arXiv: https://arxiv.org/abs/1709.05725

  ## Implementation Notes

  This implementation follows the paper's algorithms (Figures 4-15) with the following
  extensions and deviations:

  ### Extensions

  - **Additional default atoms**: AlphaDigitSpace, AlphaSpace (beyond Figure 6)
  - **Enhanced constant enrichment**: Uses common character analysis in addition to LCP

  ### Algorithmic Improvements

  - **SampleDissimilarities**: Uses most recently added seed string for sampling (more diverse)
  - **Memoization**: Pattern learning caches results to avoid redundant computation

  ### Configuration Defaults

  Default parameter values from paper's evaluation (Section 5):
  - theta = 1.25 - pattern sampling factor
  - mu = 4.0 - string sampling factor

  ## Quick Start

      # Learn patterns for a dataset
      profile = FlashProfile.profile(["PMC123", "PMC456", "PMC789"])
      # => [%ProfileEntry{pattern: [Const("PMC"), Digit×3], cost: ...}]

      # Learn a single best pattern
      {pattern, cost} = FlashProfile.learn_pattern(["2023-01-15", "2024-12-31"])
      # => {[Digit×4, Const("-"), Digit×2, Const("-"), Digit×2], 5.2}

      # Profile large datasets efficiently
      profile = FlashProfile.big_profile(large_dataset)

  ## Core Concepts

  ### Atoms
  Atomic patterns that match string prefixes:
  - Constant strings (e.g., "PMC", "-")
  - Character classes (e.g., Digit, Upper, Lower)
  - Regular expressions
  - Custom functions

  ### Patterns
  Sequences of atoms that describe strings:
  - Example: [Const("PMC"), Digit×7] matches "PMC1234567"
  - Patterns match greedily from left to right

  ### Profiles
  Collections of pattern entries, each describing a cluster of similar strings:
  - Automatically determines optimal number of patterns
  - Uses hierarchical clustering based on syntactic dissimilarity
  - Returns patterns sorted by cost (lowest = best)

  ### Cost Function
  Measures pattern quality using:
  - Static cost: Inherent complexity of atoms
  - Dynamic cost: Variability in how atoms match data
  - Lower cost = better pattern

  ## Examples

      # Simple pattern learning
      iex> {pattern, _cost} = FlashProfile.learn_pattern(["ABC123", "DEF456"])
      iex> FlashProfile.matches?(pattern, "XYZ789")
      true

      # Profile mixed data
      iex> data = ["PMC123", "PMC456", "2023-01-01", "2024-12-31"]
      iex> profile = FlashProfile.profile(data, min_patterns: 1, max_patterns: 3)
      iex> length(profile) >= 1 and length(profile) <= 3
      true

      # Custom atoms
      iex> custom_atom = FlashProfile.atom_char_class("Vowel", ~c"aeiouAEIOU", 10.0)
      iex> {_pattern, _cost} = FlashProfile.learn_pattern(["aaa", "eee"], atoms: [custom_atom])
  """

  alias FlashProfile.{
    Atom,
    Pattern,
    ProfileEntry,
    Profile,
    BigProfile,
    Learner
  }

  alias FlashProfile.Clustering.Dissimilarity
  alias FlashProfile.Atoms.Defaults

  # Type exports for convenience
  @type pattern :: [Atom.t()]
  @type profile :: [ProfileEntry.t()]
  @type flash_atom :: Atom.t()

  # Default options for profiling operations
  @default_opts [
    min_patterns: 1,
    max_patterns: 10,
    theta: 1.25,
    mu: 4.0,
    atoms: nil
  ]

  ## Public API Functions

  @doc """
  Profile a dataset with automatic cluster count.

  Generates a profile containing between `min_patterns` and `max_patterns`
  pattern entries. Each entry represents a cluster of syntactically similar
  strings and the learned pattern that describes them.

  ## Parameters

    - `strings` - List of strings to profile
    - `opts` - Options (keyword list):
      - `:min_patterns` - Minimum patterns (default: 1)
      - `:max_patterns` - Maximum patterns (default: 10)
      - `:theta` - Sampling factor for dissimilarity computation (default: 1.25)
      - `:atoms` - Custom atom list (default: all default atoms)

  ## Returns

  List of `ProfileEntry` structs, sorted by cost (lowest first).
  Each entry contains:
  - `data` - Strings matched by this pattern
  - `pattern` - Learned pattern (list of atoms)
  - `cost` - Pattern cost

  ## Examples

      iex> profile = FlashProfile.profile(["hello", "world", "123"])
      iex> is_list(profile)
      true
      iex> length(profile) >= 1
      true

      iex> # Profile with specific bounds
      iex> profile = FlashProfile.profile(
      ...>   ["PMC123", "PMC456", "ABC789"],
      ...>   min_patterns: 1,
      ...>   max_patterns: 2
      ...> )
      iex> length(profile) <= 2
      true

      iex> # Empty dataset
      iex> FlashProfile.profile([])
      []
  """
  @spec profile([String.t()], keyword()) :: profile()
  def profile(strings, opts \\ []) when is_list(strings) do
    # Merge options with defaults
    config = Keyword.merge(@default_opts, opts)
    min_patterns = config[:min_patterns]
    max_patterns = config[:max_patterns]

    profile(strings, min_patterns, max_patterns, opts)
  end

  @doc """
  Profile with specific cluster count bounds.

  This is the main profiling function that implements the Profile algorithm
  from Figure 4 of the paper. It uses hierarchical clustering to group
  similar strings and learns patterns for each cluster.

  ## Parameters

    - `strings` - List of strings to profile
    - `min_patterns` - Minimum number of patterns (positive integer)
    - `max_patterns` - Maximum number of patterns (positive integer, >= min_patterns)
    - `opts` - Options (keyword list):
      - `:theta` - Sampling factor (default: 1.25)
      - `:atoms` - Custom atom list (default: all default atoms)

  ## Returns

  List of `ProfileEntry` structs, sorted by cost.

  ## Examples

      iex> profile = FlashProfile.profile(["PMC123", "PMC456"], 1, 2)
      iex> is_list(profile)
      true

      iex> # Single string
      iex> profile = FlashProfile.profile(["test"], 1, 5)
      iex> length(profile)
      1
  """
  @spec profile([String.t()], pos_integer(), pos_integer(), keyword()) :: profile()
  def profile(strings, min_patterns, max_patterns, opts \\ [])
      when is_list(strings) and is_integer(min_patterns) and min_patterns > 0 and
             is_integer(max_patterns) and max_patterns > 0 and min_patterns <= max_patterns do
    config = Keyword.merge(@default_opts, opts)

    # Use custom atoms if provided, otherwise use NIF with default atoms
    # Also fall back to Elixir for large datasets until NIF is optimized
    if config[:atoms] || length(strings) > 30 do
      Profile.profile(strings, min_patterns, max_patterns, opts)
    else
      theta = config[:theta]

      # Use NIF implementation for performance
      case FlashProfile.Native.profile(strings, min_patterns, max_patterns, theta) do
        {:ok, entries} ->
          convert_nif_profile_entries(entries, strings)

        {:error, _reason} ->
          # Fall back to Elixir implementation on error
          Profile.profile(strings, min_patterns, max_patterns, opts)
      end
    end
  end

  # Convert NIF profile entries to Elixir ProfileEntry structs
  defp convert_nif_profile_entries(entries, strings) do
    Enum.map(entries, fn %{pattern: pattern_names, cost: cost, indices: indices} ->
      # Convert pattern atom names back to Elixir Atom structs
      pattern = Enum.map(pattern_names, &name_to_atom/1)
      # Get actual string data from indices
      data = Enum.map(indices, fn i -> Enum.at(strings, i) end)

      %ProfileEntry{
        pattern: pattern,
        cost: cost,
        data: data
      }
    end)
  end

  # Convert atom name string to Elixir Atom struct
  defp name_to_atom(name) when is_binary(name) do
    alias FlashProfile.Atoms.CharClass

    case name do
      "Lower" -> CharClass.lower()
      "Upper" -> CharClass.upper()
      "Digit" -> CharClass.digit()
      "Alpha" -> CharClass.alpha()
      "AlphaDigit" -> CharClass.alpha_digit()
      "Space" -> CharClass.space()
      "Any" -> CharClass.any()
      # Handle constant atoms (any other string is treated as constant)
      _ -> Atom.constant(name)
    end
  end

  @doc """
  Profile large dataset with sampling (BigProfile algorithm).

  More efficient for large datasets (1000+ strings). Uses iterative sampling
  to build up a profile incrementally, removing matched strings at each step.

  This implements the BigProfile algorithm from Figure 12 of the paper.

  ## Parameters

    - `strings` - List of strings to profile
    - `opts` - Options (keyword list):
      - `:min_patterns` - Minimum patterns (default: 1)
      - `:max_patterns` - Maximum patterns (default: 10)
      - `:theta` - Pattern sampling factor (default: 1.25)
      - `:mu` - String sampling factor (default: 4.0)
      - `:atoms` - Custom atom list (default: all default atoms)
      - `:max_iterations` - Max iterations to prevent infinite loops (default: 100)

  ## Returns

  List of `ProfileEntry` structs.

  ## Examples

      iex> # Generate large dataset
      iex> large_data = for i <- 1..100, do: "PMC\#{i}"
      iex> profile = FlashProfile.big_profile(large_data)
      iex> is_list(profile)
      true

      iex> # Small dataset (falls back to regular profiling)
      iex> profile = FlashProfile.big_profile(["A", "B", "C"])
      iex> length(profile) >= 1
      true

      iex> # Empty dataset
      iex> FlashProfile.big_profile([])
      []
  """
  @spec big_profile([String.t()], keyword()) :: profile()
  def big_profile(strings, opts \\ []) when is_list(strings) do
    config = Keyword.merge(@default_opts, opts)

    # Use custom atoms if provided, otherwise use NIF with default atoms
    # Also fall back to Elixir for large datasets until NIF is optimized
    if config[:atoms] || length(strings) > 50 do
      BigProfile.big_profile(strings, opts)
    else
      min_patterns = config[:min_patterns]
      max_patterns = config[:max_patterns]
      theta = config[:theta]
      mu = config[:mu]

      # Use NIF implementation for performance
      case FlashProfile.Native.big_profile(strings, min_patterns, max_patterns, theta, mu) do
        {:ok, entries} ->
          convert_nif_profile_entries(entries, strings)

        {:error, _reason} ->
          # Fall back to Elixir implementation on error
          BigProfile.big_profile(strings, opts)
      end
    end
  end

  @doc """
  Learn the best pattern for a set of strings.

  Finds the pattern with minimum cost that describes all input strings.
  This is useful when you need a single pattern rather than a full profile.

  ## Parameters

    - `strings` - List of strings to learn a pattern from
    - `opts` - Options (keyword list):
      - `:atoms` - Custom atom list (default: all default atoms)

  ## Returns

    - `{pattern, cost}` - The best pattern and its cost
    - `{:error, :no_pattern}` - If no pattern can describe all strings

  ## Examples

      iex> {pattern, cost} = FlashProfile.learn_pattern(["ABC", "DEF"])
      iex> is_list(pattern) and is_float(cost)
      true

      iex> # Pattern should match input strings
      iex> {pattern, _cost} = FlashProfile.learn_pattern(["123", "456"])
      iex> FlashProfile.matches?(pattern, "789")
      true

      iex> # Empty dataset returns empty pattern
      iex> FlashProfile.learn_pattern([])
      {[], 0.0}
  """
  @spec learn_pattern([String.t()], keyword()) :: {pattern(), float()} | {:error, :no_pattern}
  def learn_pattern(strings, opts \\ []) when is_list(strings) do
    config = Keyword.merge(@default_opts, opts)

    # Use custom atoms if provided, otherwise use NIF with default atoms
    if config[:atoms] do
      # Custom atoms require Elixir implementation
      Learner.learn_best_pattern(strings, config[:atoms])
    else
      # Use NIF for default atoms
      case FlashProfile.Native.learn_pattern_nif(strings) do
        {:ok, {pattern_names, cost}} ->
          pattern = Enum.map(pattern_names, &name_to_atom/1)
          {pattern, cost}

        {:error, :no_pattern} ->
          {:error, :no_pattern}

        {:error, _reason} ->
          # Fall back to Elixir implementation on error
          Learner.learn_best_pattern(strings, Defaults.all())
      end
    end
  end

  @doc """
  Compute syntactic dissimilarity between two strings.

  The dissimilarity is the minimum cost of any pattern that describes both
  strings. Returns 0 for identical strings, :infinity if no pattern exists.

  This implements Definition 3.1 from the paper.

  ## Parameters

    - `string1` - First string
    - `string2` - Second string
    - `opts` - Options (keyword list):
      - `:atoms` - Custom atom list (default: all default atoms)

  ## Returns

    - `0.0` - If strings are identical
    - `:infinity` - If no pattern can describe both
    - `float()` - Cost of best pattern for both strings

  ## Examples

      iex> FlashProfile.dissimilarity("abc", "abc")
      0.0

      iex> # Similar format strings have low dissimilarity
      iex> diss = FlashProfile.dissimilarity("123", "456")
      iex> is_float(diss)
      true

      iex> # Different format strings have higher dissimilarity
      iex> d1 = FlashProfile.dissimilarity("123", "456")
      iex> d2 = FlashProfile.dissimilarity("123", "abc")
      iex> is_float(d1) and is_float(d2)
      true
  """
  @spec dissimilarity(String.t(), String.t(), keyword()) :: float() | :infinity
  def dissimilarity(string1, string2, opts \\ [])
      when is_binary(string1) and is_binary(string2) do
    config = Keyword.merge(@default_opts, opts)

    # Use custom atoms if provided, otherwise use NIF with default atoms
    if config[:atoms] do
      # Custom atoms require Elixir implementation
      Dissimilarity.compute(string1, string2, config[:atoms])
    else
      # Use NIF for default atoms
      case FlashProfile.Native.dissimilarity_nif(string1, string2) do
        {:ok, cost} ->
          cost

        {:error, :no_pattern} ->
          :infinity

        {:error, _reason} ->
          # Fall back to Elixir implementation on error
          Dissimilarity.compute(string1, string2, Defaults.all())
      end
    end
  end

  @doc """
  Check if a pattern matches a string.

  Returns true if the pattern describes the entire string (matches from
  start to end with nothing left over).

  ## Parameters

    - `pattern` - List of atoms forming the pattern
    - `string` - String to check

  ## Returns

  Boolean indicating whether the pattern matches.

  ## Examples

      iex> alias FlashProfile.Atoms.CharClass
      iex> pattern = [CharClass.digit()]
      iex> FlashProfile.matches?(pattern, "123")
      true
      iex> FlashProfile.matches?(pattern, "abc")
      false

      iex> # Empty pattern only matches empty string
      iex> FlashProfile.matches?([], "")
      true
      iex> FlashProfile.matches?([], "abc")
      false
  """
  @spec matches?(pattern(), String.t()) :: boolean()
  def matches?(pattern, string) when is_list(pattern) and is_binary(string) do
    Pattern.matches?(pattern, string)
  end

  @doc """
  Convert a pattern to a human-readable string representation.

  Formats the pattern for display using the notation from the paper:
  - Constant strings in quotes: "PMC"
  - Fixed-width char classes: Digit×4
  - Variable-width char classes: Upper+
  - Atoms separated by ◇

  ## Parameters

    - `pattern` - List of atoms forming the pattern

  ## Returns

  String representation of the pattern.

  ## Examples

      iex> alias FlashProfile.Atoms.CharClass
      iex> pattern = [CharClass.upper(), CharClass.digit()]
      iex> str = FlashProfile.pattern_to_string(pattern)
      iex> is_binary(str)
      true

      iex> # Empty pattern
      iex> FlashProfile.pattern_to_string([])
      ""
  """
  @spec pattern_to_string(pattern()) :: String.t()
  def pattern_to_string(pattern) when is_list(pattern) do
    Pattern.to_string(pattern)
  end

  @doc """
  Get all default atoms.

  Returns the standard set of 17 atoms defined in the FlashProfile paper
  (Figure 6). These atoms cover common character classes and patterns.

  ## Returns

  List of default atoms.

  ## Examples

      iex> atoms = FlashProfile.default_atoms()
      iex> length(atoms)
      17

      iex> # All atoms have names
      iex> atoms = FlashProfile.default_atoms()
      iex> Enum.all?(atoms, fn atom -> is_binary(atom.name) end)
      true
  """
  @spec default_atoms() :: [flash_atom()]
  def default_atoms() do
    Defaults.all()
  end

  @doc """
  Create a custom atom from a character class.

  Creates a variable-width character class atom that matches the longest
  prefix containing only characters from the allowed set.

  ## Parameters

    - `name` - Display name for the atom (e.g., "Vowel")
    - `chars` - Charlist of allowed characters (e.g., ~c"aeiou")
    - `cost` - Static cost for this atom (should be positive float)

  ## Returns

  A new character class atom.

  ## Examples

      iex> vowel = FlashProfile.atom_char_class("Vowel", ~c"aeiouAEIOU", 10.0)
      iex> vowel.name
      "Vowel"

      iex> # Create binary digit atom
      iex> binary = FlashProfile.atom_char_class("Binary", ~c"01", 8.5)
      iex> FlashProfile.Atom.match(binary, "101010")
      6
  """
  @spec atom_char_class(String.t(), charlist(), float()) :: flash_atom()
  def atom_char_class(name, chars, cost)
      when is_binary(name) and is_list(chars) and is_float(cost) do
    Atom.char_class(name, chars, cost)
  end

  @doc """
  Create a constant atom that matches a literal string.

  Creates an atom that matches exactly the given string as a prefix.
  The cost is automatically calculated as 100.0 / length(string).

  ## Parameters

    - `string` - The literal string to match (must be non-empty)

  ## Returns

  A new constant atom.

  ## Examples

      iex> pmc = FlashProfile.atom_constant("PMC")
      iex> pmc.type
      :constant

      iex> # Match the constant
      iex> atom = FlashProfile.atom_constant("hello")
      iex> FlashProfile.Atom.match(atom, "hello world")
      5
      iex> FlashProfile.Atom.match(atom, "goodbye")
      0
  """
  @spec atom_constant(String.t()) :: flash_atom()
  def atom_constant(string) when is_binary(string) and byte_size(string) > 0 do
    Atom.constant(string)
  end

  @doc """
  Returns the version of FlashProfile.

  ## Examples

      iex> FlashProfile.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version(), do: "0.1.0"
end
