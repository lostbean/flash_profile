defmodule FlashProfile.Compress do
  @moduledoc """
  Profile compression for FlashProfile.

  Reduces the number of patterns in a profile by merging similar entries.
  This module implements the CompressProfile algorithm from Figure 13 of the
  FlashProfile paper.

  ## Algorithm Overview

  The compression algorithm iteratively merges the two profile entries that,
  when combined, produce the lowest-cost pattern. This continues until the
  profile has at most M patterns.

  From the paper (Figure 13):
  ```
  func CompressProfile(P̃, M)
    while |P̃| > M do
      (X, Y) ← argmin_{X,Y∈P̃} LearnBestPattern(X.Data ∪ Y.Data).Cost
      Z ← X.Data ∪ Y.Data
      P ← LearnBestPattern(Z).Pattern
      P̃ ← (P̃ \\ {X, Y}) ∪ {⟨Data: Z, Pattern: P⟩}
    return P̃
  ```

  ## Profile Entry Structure

  Each entry in a profile contains:
  - `data`: List of strings described by this pattern
  - `pattern`: The learned pattern (list of atoms)
  - `cost`: Cost of the pattern over the data

  ## Examples

      iex> alias FlashProfile.Compress
      iex> # Compress a profile with 10 entries down to 3
      iex> compressed = Compress.compress(large_profile, 3)
      iex> length(compressed) <= 3
      true

      iex> # Find best pair to merge
      iex> {entry1, entry2, merged} = Compress.find_best_merge_pair(profile)
      iex> merged.data == entry1.data ++ entry2.data
      true
  """

  alias FlashProfile.{Learner, ProfileEntry}
  alias FlashProfile.Atoms.Defaults

  @doc """
  Compress a profile to at most max_patterns entries.

  Iteratively merges pairs of entries that produce the lowest-cost pattern
  when combined, until the profile has at most max_patterns entries.

  If the profile already has max_patterns or fewer entries, returns it unchanged.

  ## Parameters

    - `profile` - List of ProfileEntry structs to compress
    - `max_patterns` - Maximum number of entries in the result (must be >= 1)
    - `opts` - Options keyword list:
      - `:atoms` - List of atoms to use (defaults to all standard atoms)

  ## Returns

  A compressed profile with at most max_patterns entries.

  ## Examples

      iex> alias FlashProfile.{Compress, ProfileEntry}
      iex> entries = [
      ...>   %ProfileEntry{data: ["PMC123", "PMC456"], pattern: [], cost: 10.0},
      ...>   %ProfileEntry{data: ["XYZ789"], pattern: [], cost: 5.0}
      ...> ]
      iex> compressed = Compress.compress(entries, 1)
      iex> length(compressed) == 1
      true
  """
  @spec compress([ProfileEntry.t()], pos_integer(), keyword()) :: [ProfileEntry.t()]
  def compress(profile, max_patterns, opts \\ [])

  def compress(_profile, max_patterns, _opts)
      when not is_integer(max_patterns) or max_patterns < 1 do
    raise ArgumentError, "max_patterns must be a positive integer, got: #{inspect(max_patterns)}"
  end

  def compress(profile, _max_patterns, _opts) when not is_list(profile) do
    raise ArgumentError, "profile must be a list, got: #{inspect(profile)}"
  end

  def compress([], _max_patterns, _opts), do: []

  def compress(profile, max_patterns, opts) when is_list(profile) do
    # Early termination if already at or below target size
    if length(profile) <= max_patterns do
      profile
    else
      # Recursively merge until we reach max_patterns
      compress_recursive(profile, max_patterns, opts)
    end
  end

  @doc """
  Find the best pair of entries to merge.

  Evaluates all possible pairs of profile entries and returns the pair that,
  when merged, produces the pattern with the lowest cost.

  Returns a tuple {entry1, entry2, merged_entry} where merged_entry is the
  result of merging entry1 and entry2. Returns nil if the profile has fewer
  than 2 entries.

  ## Parameters

    - `profile` - List of ProfileEntry structs
    - `opts` - Options keyword list:
      - `:atoms` - List of atoms to use (defaults to all standard atoms)

  ## Returns

    - `{entry1, entry2, merged_entry}` - The best pair and their merge result
    - `nil` - If profile has fewer than 2 entries

  ## Examples

      iex> alias FlashProfile.{Compress, ProfileEntry}
      iex> entries = [
      ...>   %ProfileEntry{data: ["ABC", "DEF"], pattern: [], cost: 5.0},
      ...>   %ProfileEntry{data: ["123", "456"], pattern: [], cost: 3.0}
      ...> ]
      iex> {e1, e2, merged} = Compress.find_best_merge_pair(entries)
      iex> merged.data == e1.data ++ e2.data
      true
  """
  @spec find_best_merge_pair([ProfileEntry.t()], keyword()) ::
          {ProfileEntry.t(), ProfileEntry.t(), ProfileEntry.t()} | nil
  def find_best_merge_pair(profile, opts \\ [])

  def find_best_merge_pair(profile, _opts) when length(profile) < 2, do: nil

  def find_best_merge_pair(profile, opts) when is_list(profile) do
    # Generate all pairs of entries
    pairs =
      for i <- 0..(length(profile) - 2),
          j <- (i + 1)..(length(profile) - 1) do
        {Enum.at(profile, i), Enum.at(profile, j)}
      end

    # Find the pair with minimum merge cost
    pairs
    |> Enum.map(fn {entry1, entry2} ->
      merged = merge_entries(entry1, entry2, opts)
      {entry1, entry2, merged}
    end)
    |> Enum.min_by(
      fn {_e1, _e2, merged} -> merged.cost end,
      fn
        :infinity, :infinity -> true
        :infinity, _ -> false
        _, :infinity -> true
        c1, c2 -> c1 <= c2
      end
    )
  end

  @doc """
  Merge two profile entries into one.

  Combines the data from both entries and learns a new pattern that describes
  the combined dataset. The resulting entry contains all strings from both
  input entries.

  ## Parameters

    - `entry1` - First ProfileEntry to merge
    - `entry2` - Second ProfileEntry to merge
    - `opts` - Options keyword list:
      - `:atoms` - List of atoms to use (defaults to all standard atoms)

  ## Returns

  A new ProfileEntry with:
  - `data`: Combined data from both entries
  - `pattern`: Best pattern learned for the combined data
  - `cost`: Cost of the learned pattern, or :infinity if no pattern found

  ## Examples

      iex> alias FlashProfile.{Compress, ProfileEntry}
      iex> e1 = %ProfileEntry{data: ["ABC"], pattern: [], cost: 2.0}
      iex> e2 = %ProfileEntry{data: ["DEF"], pattern: [], cost: 3.0}
      iex> merged = Compress.merge_entries(e1, e2)
      iex> merged.data
      ["ABC", "DEF"]
  """
  @spec merge_entries(ProfileEntry.t(), ProfileEntry.t(), keyword()) :: ProfileEntry.t()
  def merge_entries(%ProfileEntry{} = entry1, %ProfileEntry{} = entry2, opts \\ []) do
    combined_data = entry1.data ++ entry2.data
    atoms = Keyword.get(opts, :atoms, Defaults.all())

    case Learner.learn_best_pattern(combined_data, atoms) do
      {:error, _reason} ->
        # No pattern can describe all strings - return entry with infinity cost
        %ProfileEntry{data: combined_data, pattern: nil, cost: :infinity}

      {pattern, cost} ->
        %ProfileEntry{data: combined_data, pattern: pattern, cost: cost}
    end
  end

  ## Private Functions

  # Recursively compress profile until it has max_patterns entries
  defp compress_recursive(profile, max_patterns, opts) do
    if length(profile) <= max_patterns do
      profile
    else
      # Find best pair to merge
      case find_best_merge_pair(profile, opts) do
        nil ->
          # Cannot merge further (shouldn't happen since length > max_patterns)
          profile

        {entry1, entry2, merged} ->
          # Remove the two entries and add the merged one
          new_profile =
            profile
            |> Enum.reject(fn e -> e == entry1 or e == entry2 end)
            |> Kernel.++([merged])

          # Continue compressing
          compress_recursive(new_profile, max_patterns, opts)
      end
    end
  end
end
