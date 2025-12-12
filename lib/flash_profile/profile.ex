defmodule FlashProfile.Profile do
  @moduledoc """
  Profile generation for FlashProfile.

  A profile is a collection of ProfileEntry records, each containing:
  - A cluster of similar strings (data)
  - A learned pattern describing that cluster
  - The cost of the pattern

  ## Profile Algorithm

  The profiling process follows these steps:

  1. **Build Hierarchy**: Use hierarchical clustering to group similar strings
     based on syntactic dissimilarity (cost of patterns describing pairs).

  2. **Partition**: Split the hierarchy into m to M clusters, where m is the
     minimum number of patterns and M is the maximum.

  3. **Learn Patterns**: For each cluster, learn the best (lowest cost) pattern
     that describes all strings in that cluster.

  4. **Return Profile**: A sorted list of profile entries (by cost).

  ## Algorithm (from Figure 4 of the paper)

  ```
  func Profile(S, m, M, θ)
    H ← BuildHierarchy(S, M, θ)
    P̃ ← {}
    for all X ∈ Partition(H, m, M) do
      {Pattern: P, Cost: c} ← LearnBestPattern(X)
      P̃ ← P̃ ∪ {⟨Data: X, Pattern: P⟩}
    return P̃
  ```

  ## BuildHierarchy Algorithm (from Figure 8)

  ```
  func BuildHierarchy(S, M, θ)
    M̂ ← ⌈θ·M⌉
    D ← SampleDissimilarities(S, M̂)
    A ← ApproxDMatrix(S, D)
    return AHC(S, A)
  ```

  ## Examples

      iex> alias FlashProfile.Profile
      iex> # Profile PMC identifiers
      iex> strings = ["PMC1234567", "PMC9876543", "PMC5555555"]
      iex> _entries = Profile.profile(strings, 1, 3)
      iex> # Returns single entry with pattern ["PMC", Digit×7]

      iex> # Profile mixed data
      iex> alias FlashProfile.Profile
      iex> strings = ["PMC123", "PMC456", "2023-01-01", "2024-12-31"]
      iex> _entries = Profile.profile(strings, 1, 4)
      iex> # Returns 2 entries: one for PMC IDs, one for dates

      iex> # Check if entry matches a string
      iex> alias FlashProfile.Profile
      iex> digit = FlashProfile.Atoms.Defaults.get("Digit")
      iex> entry = %FlashProfile.ProfileEntry{data: ["123"], pattern: [digit], cost: 10.0}
      iex> Profile.matches_entry?(entry, "456")
      true
  """

  alias FlashProfile.{Learner, Pattern, ProfileEntry}
  alias FlashProfile.Clustering.{Dissimilarity, Hierarchy}
  alias FlashProfile.Atoms.Defaults

  @default_opts [
    theta: 1.25,
    atoms: nil
  ]

  @doc """
  Profile a dataset with minimum and maximum pattern bounds.

  Generates a profile containing between `min_patterns` and `max_patterns`
  entries, where each entry represents a cluster of similar strings and
  its learned pattern.

  ## Parameters

    - `strings` - List of strings to profile
    - `min_patterns` - Minimum number of patterns to generate (positive integer)
    - `max_patterns` - Maximum number of patterns to generate (positive integer)
    - `opts` - Optional keyword list:
      - `:theta` - Sampling factor for dissimilarity computation (default: 1.25)
      - `:atoms` - List of atoms to use for pattern learning (default: all default atoms)

  ## Returns

  A list of `ProfileEntry` structs, sorted by cost (lowest first).
  Each entry contains the cluster data, learned pattern, and cost.

  ## Examples

      iex> alias FlashProfile.Profile
      iex> strings = ["PMC123", "PMC456", "PMC789"]
      iex> entries = Profile.profile(strings, 1, 2)
      iex> length(entries) >= 1 and length(entries) <= 2
      true

      iex> # Empty input
      iex> alias FlashProfile.Profile
      iex> Profile.profile([], 1, 5)
      []

      iex> # Single string
      iex> alias FlashProfile.Profile
      iex> entries = Profile.profile(["test"], 1, 5)
      iex> length(entries)
      1
  """
  @spec profile([String.t()], pos_integer(), pos_integer(), keyword()) :: [ProfileEntry.t()]
  def profile(strings, min_patterns, max_patterns, opts \\ [])
      when is_list(strings) and is_integer(min_patterns) and min_patterns > 0 and
             is_integer(max_patterns) and max_patterns > 0 and min_patterns <= max_patterns do
    # Handle edge cases
    cond do
      # Empty dataset - return empty profile
      strings == [] ->
        []

      # Single string - return single entry with learned pattern
      length(strings) == 1 ->
        learn_single_entry(strings, opts)

      # All strings identical - single cluster
      all_identical?(strings) ->
        learn_single_entry(strings, opts)

      # General case - build hierarchy and partition
      true ->
        profile_general(strings, min_patterns, max_patterns, opts)
    end
  end

  @doc """
  Build hierarchical clustering for strings.

  Creates a hierarchical clustering tree using syntactic dissimilarity.
  This implements the BuildHierarchy algorithm from Figure 8 of the paper.

  ## Algorithm

  1. Compute M̂ = ⌈θ·M⌉ (number of samples)
  2. Sample dissimilarities from dataset
  3. Build approximate dissimilarity matrix
  4. Perform agglomerative hierarchical clustering (AHC)

  ## Parameters

    - `strings` - List of strings to cluster
    - `max_patterns` - Maximum number of patterns (used to determine sample size)
    - `theta` - Sampling factor (default: 1.25)
    - `opts` - Optional keyword list:
      - `:atoms` - List of atoms to use (default: all default atoms)

  ## Returns

  A hierarchical clustering tree (Hierarchy.Node.t()).

  ## Examples

      iex> alias FlashProfile.Profile
      iex> strings = ["PMC123", "PMC456", "ABC789"]
      iex> hierarchy = Profile.build_hierarchy(strings, 3, 1.25)
      iex> is_struct(hierarchy, FlashProfile.Clustering.Hierarchy.Node)
      true
  """
  @spec build_hierarchy([String.t()], pos_integer(), float(), keyword()) :: any()
  def build_hierarchy(strings, max_patterns, theta, opts \\ [])
      when is_list(strings) and is_integer(max_patterns) and max_patterns > 0 and
             is_float(theta) and theta > 0 do
    # Get atoms from options or use defaults
    atoms = Keyword.get(opts, :atoms) || Defaults.all()

    # Compute sample size: M̂ = ⌈θ·M⌉
    m_hat = ceil(theta * max_patterns)

    # Sample dissimilarities
    cache = Dissimilarity.sample_dissimilarities(strings, m_hat, atoms)

    # Build approximate dissimilarity matrix
    matrix = Dissimilarity.build_matrix(strings, cache, atoms)

    # Perform agglomerative hierarchical clustering
    Hierarchy.ahc(strings, matrix)
  end

  @doc """
  Check if a profile entry matches a string.

  Returns true if the entry's pattern matches the given string.
  If the pattern is nil (learning failed), returns false.

  ## Parameters

    - `entry` - A ProfileEntry struct
    - `string` - The string to check for a match

  ## Returns

  Boolean indicating whether the pattern matches the string.

  ## Examples

      iex> alias FlashProfile.Profile
      iex> alias FlashProfile.ProfileEntry
      iex> alias FlashProfile.Atoms.CharClass
      iex> pattern = [CharClass.digit()]
      iex> entry = %ProfileEntry{data: ["123"], pattern: pattern, cost: 10.0}
      iex> Profile.matches_entry?(entry, "456")
      true

      iex> # Entry with no pattern (learning failed)
      iex> alias FlashProfile.ProfileEntry
      iex> alias FlashProfile.Profile
      iex> entry = %ProfileEntry{data: ["abc"], pattern: nil, cost: :infinity}
      iex> Profile.matches_entry?(entry, "abc")
      false
  """
  @spec matches_entry?(ProfileEntry.t(), String.t()) :: boolean()
  def matches_entry?(%ProfileEntry{pattern: nil}, _string), do: false

  def matches_entry?(%ProfileEntry{pattern: pattern}, string) when is_list(pattern) do
    Pattern.matches?(pattern, string)
  end

  ## Private Functions

  # Profile for general case with multiple distinct strings
  defp profile_general(strings, min_patterns, max_patterns, opts) do
    # Merge options with defaults
    options = Keyword.merge(@default_opts, opts)
    theta = Keyword.fetch!(options, :theta)
    atoms = Keyword.get(options, :atoms) || Defaults.all()

    # Build hierarchy
    hierarchy = build_hierarchy(strings, max_patterns, theta, atoms: atoms)

    # Partition hierarchy into clusters
    clusters = Hierarchy.partition_range(hierarchy, min_patterns, max_patterns)

    # Learn pattern for each cluster
    entries =
      clusters
      |> Enum.map(fn cluster ->
        learn_entry_for_cluster(cluster, atoms)
      end)
      |> Enum.sort_by(fn entry -> sort_cost(entry.cost) end)

    entries
  end

  # Learn a single profile entry for all strings (edge case handler)
  defp learn_single_entry(strings, opts) do
    options = Keyword.merge(@default_opts, opts)
    atoms = Keyword.get(options, :atoms) || Defaults.all()

    entry = learn_entry_for_cluster(strings, atoms)
    [entry]
  end

  # Learn a pattern for a cluster of strings
  defp learn_entry_for_cluster(cluster, atoms) do
    case Learner.learn_best_pattern(cluster, atoms) do
      {:error, :no_pattern} ->
        # Learning failed - create entry with nil pattern and infinite cost
        %ProfileEntry{
          data: cluster,
          pattern: nil,
          cost: :infinity
        }

      {pattern, cost} ->
        # Learning succeeded
        %ProfileEntry{
          data: cluster,
          pattern: pattern,
          cost: cost
        }
    end
  end

  # Check if all strings in list are identical
  defp all_identical?([]), do: true
  defp all_identical?([_single]), do: true

  defp all_identical?([first | rest]) do
    Enum.all?(rest, fn s -> s == first end)
  end

  # Convert cost to sortable value (infinity should come last)
  defp sort_cost(:infinity), do: {:infinity, 0}
  defp sort_cost(cost) when is_float(cost), do: {:finite, cost}
end
