defmodule FlashProfile.Learner do
  @moduledoc """
  Pattern learning (synthesis) for FlashProfile.

  Learns patterns that describe a given set of strings by:
  1. Finding compatible atoms (atoms that match all strings)
  2. Recursively building patterns from atoms
  3. Selecting the lowest-cost pattern

  This module implements the LearnBestPattern and GetMaxCompatibleAtoms algorithms
  from the FlashProfile paper (Figures 7 and 15).

  ## Algorithm Overview

  The learner uses a recursive approach to synthesize patterns:

  1. **Get Compatible Atoms**: Find all atoms that can match a non-empty prefix
     of ALL strings in the dataset. Enrich with:
     - Fixed-width variants where match lengths are consistent
     - Constant atoms from longest common prefix

  2. **Recursive Pattern Building**: For each compatible atom:
     - Match it against all strings to get remaining suffixes
     - Recursively learn patterns for those suffixes
     - Combine atom with suffix patterns

  3. **Cost-Based Selection**: Among all valid patterns, select the one
     with minimum cost using the FlashProfile cost function.

  ## Performance Considerations

  To manage the exponential search space, the learner implements several optimizations:
  - Maximum pattern length limit
  - Maximum number of patterns to explore
  - Early termination when sufficient patterns found
  - Memoization of compatible atoms

  ## Examples

      iex> alias FlashProfile.Learner
      iex> # Learn pattern for PMC IDs
      iex> strings = ["PMC1234567", "PMC9876543", "PMC5555555"]
      iex> {_pattern, _cost} = Learner.learn_best_pattern(strings)
      iex> # Returns pattern like ["PMC", Digit×7]

      iex> # Learn pattern for dates
      iex> alias FlashProfile.Learner
      iex> dates = ["2023-01-15", "2024-12-31", "2022-06-30"]
      iex> {_pattern, _cost} = Learner.learn_best_pattern(dates)
      iex> # Returns pattern like [Digit×4, "-", Digit×2, "-", Digit×2]

      iex> # Get compatible atoms
      iex> alias FlashProfile.{Learner, Atoms.Defaults}
      iex> _atoms = Learner.get_compatible_atoms(["123", "456", "789"], Defaults.all())
      iex> # Returns [Digit, Digit×3, "1", ...]
  """

  alias FlashProfile.{Atom, Pattern, Cost}
  alias FlashProfile.Atoms.{Defaults, Constant}

  # Optimization constants to prevent exponential blowup
  @max_pattern_length 15
  @max_patterns_to_explore 5000

  @doc """
  Learn the best (lowest cost) pattern for a set of strings.

  Returns {pattern, cost} or {:error, :no_pattern} if no pattern can describe
  all strings.

  ## Parameters

    - `strings` - List of strings to learn a pattern from
    - `atoms` - List of atoms to use (defaults to all standard atoms)

  ## Returns

    - `{pattern, cost}` - The best pattern and its cost
    - `{:error, :no_pattern}` - If no pattern can describe all strings

  ## Examples

      iex> alias FlashProfile.Learner
      iex> strings = ["PMC123", "PMC456"]
      iex> {pattern, _cost} = Learner.learn_best_pattern(strings)
      iex> FlashProfile.Pattern.matches?(pattern, "PMC123")
      true
  """
  @spec learn_best_pattern([String.t()], [Atom.t()]) ::
          {Pattern.t(), float()} | {:error, :no_pattern}
  def learn_best_pattern(strings, atoms \\ Defaults.all())

  def learn_best_pattern([], _atoms) do
    # Empty dataset - return empty pattern with zero cost
    {[], 0.0}
  end

  def learn_best_pattern(strings, atoms) when is_list(strings) and is_list(atoms) do
    patterns = learn_all_patterns(strings, atoms)

    if patterns == [] do
      {:error, :no_pattern}
    else
      # Find pattern with minimum cost
      case Cost.min_cost(patterns, strings) do
        nil -> {:error, :no_pattern}
        {best_pattern, cost} -> {best_pattern, cost}
      end
    end
  end

  @doc """
  Learn all patterns that describe the given strings.

  Returns a list of patterns (may be empty if none found). This function
  explores the pattern space recursively and returns all valid patterns
  up to the configured limits.

  ## Parameters

    - `strings` - List of strings to learn patterns from
    - `atoms` - List of atoms to use (defaults to all standard atoms)

  ## Returns

  A list of patterns, where each pattern is a list of atoms. Returns an
  empty list if no patterns can describe all strings.

  ## Examples

      iex> alias FlashProfile.Learner
      iex> patterns = Learner.learn_all_patterns(["AB", "CD"])
      iex> length(patterns) > 0
      true
  """
  @spec learn_all_patterns([String.t()], [Atom.t()]) :: [Pattern.t()]
  def learn_all_patterns(strings, atoms \\ Defaults.all())

  def learn_all_patterns([], _atoms) do
    # Empty dataset - return list containing empty pattern
    [[]]
  end

  def learn_all_patterns(strings, atoms) when is_list(strings) and is_list(atoms) do
    # Check if all strings are empty
    if Enum.all?(strings, &(&1 == "")) do
      # All strings are empty - return empty pattern
      [[]]
    else
      # Start recursive pattern learning with depth tracking
      learn_patterns_recursive(strings, atoms, 0, %{})
    end
  end

  @doc """
  Get the maximal set of atoms compatible with all strings.

  An atom is compatible if it matches a non-empty prefix of ALL strings.
  This function also enriches the atom set with:
  - Fixed-width variants where match lengths are consistent across all strings
  - Constant atoms from longest common prefix

  This implements the GetMaxCompatibleAtoms algorithm from Figure 15 of the paper.

  ## Parameters

    - `strings` - List of strings to check compatibility against
    - `atoms` - List of candidate atoms to filter

  ## Returns

  A list of atoms that are compatible with all strings, plus enriched atoms.

  ## Examples

      iex> alias FlashProfile.{Learner, Atoms.Defaults}
      iex> _atoms = Learner.get_compatible_atoms(["123", "456"], Defaults.all())
      iex> # Returns atoms like [Digit, Digit×3, ...]
  """
  @spec get_compatible_atoms([String.t()], [Atom.t()]) :: [Atom.t()]
  def get_compatible_atoms(strings, atoms)

  def get_compatible_atoms([], _atoms), do: []
  def get_compatible_atoms(_strings, []), do: []

  def get_compatible_atoms(strings, atoms) when is_list(strings) and is_list(atoms) do
    # Filter atoms: keep only those that match ALL strings with non-empty prefix
    compatible =
      atoms
      |> Enum.filter(fn atom ->
        Enum.all?(strings, fn s ->
          Atom.match(atom, s) > 0
        end)
      end)

    # Build width map: track consistent match widths for char class atoms
    width_map = build_width_map(strings, compatible)

    # Add fixed-width variants where widths are consistent
    fixed_width_atoms =
      width_map
      |> Enum.map(fn {atom, width} ->
        Atom.with_fixed_width(atom, width)
      end)

    # Add constant atoms from longest common prefix
    lcp = longest_common_prefix(strings)

    constant_atoms =
      if String.length(lcp) > 0 do
        Constant.all_prefixes(lcp)
      else
        []
      end

    # Combine all atoms and remove duplicates
    # Use a more robust deduplication based on atom characteristics
    (compatible ++ fixed_width_atoms ++ constant_atoms)
    |> Enum.uniq_by(&atom_signature/1)
  end

  ## Private Functions

  # Recursively learn patterns with depth tracking and limits
  defp learn_patterns_recursive(strings, atoms, depth, memo_cache) do
    # Check depth limit to prevent infinite recursion
    if depth >= @max_pattern_length do
      []
    else
      # Create cache key for memoization
      cache_key = {strings, depth}

      case Map.get(memo_cache, cache_key) do
        nil ->
          # Not cached, compute patterns
          patterns = do_learn_patterns(strings, atoms, depth, memo_cache)
          patterns

        cached_patterns ->
          cached_patterns
      end
    end
  end

  # Core pattern learning logic
  defp do_learn_patterns(strings, atoms, depth, memo_cache) do
    # Get compatible atoms (enriched with constants and fixed-width)
    compatible = get_compatible_atoms(strings, atoms)

    if compatible == [] do
      # No compatible atoms - no patterns possible
      []
    else
      # For each compatible atom, recursively build patterns
      compatible
      |> Enum.reduce({[], 0}, fn atom, {acc_patterns, count} ->
        # Early termination if we've found enough patterns
        if count >= @max_patterns_to_explore do
          {acc_patterns, count}
        else
          # Get remaining suffixes after matching this atom
          suffixes = get_suffixes_after_atom(strings, atom)

          # Check if all suffixes are empty (pattern complete)
          if Enum.all?(suffixes, &(&1 == "")) do
            # This atom completes the pattern
            new_patterns = [[atom]]
            {acc_patterns ++ new_patterns, count + 1}
          else
            # Recursively learn patterns for suffixes
            suffix_patterns = learn_patterns_recursive(suffixes, atoms, depth + 1, memo_cache)

            # Prepend this atom to each suffix pattern
            new_patterns =
              Enum.map(suffix_patterns, fn suffix_pattern ->
                [atom | suffix_pattern]
              end)

            {acc_patterns ++ new_patterns, count + length(new_patterns)}
          end
        end
      end)
      |> elem(0)
    end
  end

  # Get suffixes of strings after matching an atom
  defp get_suffixes_after_atom(strings, atom) do
    Enum.map(strings, fn string ->
      len = Atom.match(atom, string)

      if len > 0 do
        String.slice(string, len..-1//1)
      else
        # Should not happen if atom is compatible, but handle gracefully
        string
      end
    end)
  end

  # Build a map of atoms to their consistent match widths
  # Only includes char class atoms that match the same width across all strings
  defp build_width_map(strings, atoms) do
    atoms
    |> Enum.filter(fn atom ->
      atom.type == :char_class and Map.get(atom.params, :width, 0) == 0
    end)
    |> Enum.reduce(%{}, fn atom, acc ->
      # Get match widths for this atom across all strings
      widths = Enum.map(strings, fn s -> Atom.match(atom, s) end)

      # Check if all widths are the same and non-zero
      unique_widths = Enum.uniq(widths)

      if length(unique_widths) == 1 and hd(unique_widths) > 0 do
        # All strings have same match width - add to map
        Map.put(acc, atom, hd(unique_widths))
      else
        acc
      end
    end)
  end

  # Find the longest common prefix of a list of strings
  defp longest_common_prefix([]), do: ""
  defp longest_common_prefix([s]), do: s

  defp longest_common_prefix(strings) do
    # Find shortest string as upper bound
    min_length =
      strings
      |> Enum.map(&String.length/1)
      |> Enum.min()

    if min_length == 0 do
      ""
    else
      # Check each position from 0 to min_length - 1
      Enum.reduce_while(0..(min_length - 1), "", fn i, acc ->
        # Get character at position i from first string
        first_string = hd(strings)
        char = String.at(first_string, i)

        # Check if all strings have the same character at position i
        if Enum.all?(strings, fn s -> String.at(s, i) == char end) do
          {:cont, acc <> char}
        else
          {:halt, acc}
        end
      end)
    end
  end

  # Create a signature for an atom for deduplication
  # Two atoms are considered the same if they have the same type, name, and key params
  defp atom_signature(%Atom{type: :constant, params: %{string: str}}) do
    {:constant, str}
  end

  defp atom_signature(%Atom{type: :char_class, name: name, params: params}) do
    width = Map.get(params, :width, 0)
    chars = Map.get(params, :chars, [])
    {:char_class, name, width, chars}
  end

  defp atom_signature(%Atom{type: :regex, name: name, params: params}) do
    pattern = Map.get(params, :pattern, nil)
    {:regex, name, pattern}
  end

  defp atom_signature(%Atom{type: type, name: name}) do
    {type, name}
  end
end
