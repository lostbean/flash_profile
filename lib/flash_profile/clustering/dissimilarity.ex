defmodule FlashProfile.Clustering.Dissimilarity do
  @moduledoc """
  Syntactic dissimilarity computation for FlashProfile.

  Computes how different two strings are based on the cost of patterns
  needed to describe them together. Lower dissimilarity = more similar.

  ## Syntactic Dissimilarity (Definition 3.1)

  The dissimilarity between two strings is the minimum cost of any pattern
  that describes both:

  ```
  η(x, y) =
    0                           if x = y
    ∞                           if x ≠ y and V = {}
    min_{P∈V} C(P, {x,y})       otherwise

  where V = L({x,y}) is the set of patterns that describe both x and y
  ```

  ## Adaptive Sampling

  The `sample_dissimilarities/3` function implements adaptive sampling
  (Figure 9 from the paper) to avoid computing all O(|S|²) pairs. It
  iteratively selects diverse seed strings and builds a cache of patterns.

  ## Matrix Completion

  The `build_matrix/3` function implements ApproxDMatrix (Figure 10) to
  complete the dissimilarity matrix using cached patterns when possible,
  only computing new patterns when necessary.

  ## Examples

      iex> alias FlashProfile.Clustering.Dissimilarity
      iex> # Basic dissimilarity between same format
      iex> Dissimilarity.compute("1990-11-23", "2001-02-04")
      # => ~4.96 (same format, low dissimilarity)

      iex> # Dissimilarity between different formats
      iex> Dissimilarity.compute("1990-11-23", "29/05/1923")
      # => ~30.2 (different format, higher dissimilarity)

      iex> # Sample dissimilarities for clustering
      iex> strings = ["PMC123", "PMC456", "2023-01-01", "2024-12-31"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 2)
      iex> matrix = Dissimilarity.build_matrix(strings, cache)
  """

  alias FlashProfile.{Learner, Pattern, Cost, Atom}

  @type dissimilarity :: float() | :infinity
  @type cache :: %{{String.t(), String.t()} => {Pattern.t() | nil, dissimilarity()}}
  @type matrix :: %{{String.t(), String.t()} => dissimilarity()}

  @doc """
  Compute the syntactic dissimilarity between two strings.

  Returns 0 if strings are identical, :infinity if no pattern can describe both,
  otherwise the minimum cost of patterns describing both.

  ## Parameters

    - `x` - First string
    - `y` - Second string
    - `atoms` - Available atoms for pattern learning (defaults to all default atoms)

  ## Returns

    - `0.0` - If strings are identical
    - `:infinity` - If no pattern can describe both strings
    - `float()` - The minimum cost of patterns describing both strings

  ## Examples

      iex> alias FlashProfile.Clustering.Dissimilarity
      iex> Dissimilarity.compute("abc", "abc")
      0.0

      iex> # Different strings with same pattern
      iex> Dissimilarity.compute("123", "456")
      # Returns cost of Digit+ pattern
  """
  @spec compute(String.t(), String.t(), [Atom.t()]) :: dissimilarity()
  def compute(x, y, atoms \\ FlashProfile.Atoms.Defaults.all())
  def compute(x, x, _atoms), do: 0.0

  def compute(x, y, atoms) do
    case Learner.learn_best_pattern([x, y], atoms) do
      {:error, :no_pattern} -> :infinity
      {_pattern, cost} -> cost
    end
  end

  @doc """
  Sample dissimilarities for a dataset, building a cache of patterns.

  Implements the SampleDissimilarities algorithm from Figure 9 of the paper.
  Uses adaptive sampling to select diverse seed strings, building up a cache
  of patterns that can be reused when constructing the full matrix.

  Returns a cache mapping string pairs to {pattern, cost}. The cache uses
  normalized keys so that {a, b} and {b, a} map to the same entry.

  ## Implementation Note

  This implementation uses the most recently added seed string for computing
  dissimilarities in each iteration, rather than the original seed string `a`
  from step 1. This is a minor improvement that results in more diverse
  sampling of seed strings.

  **Paper** (step 3): `for all b ∈ S do D[a,b] ← LearnBestPattern({a,b})`

  **Implementation**: Uses `current_seed` which is the most recently added seed

  ## Algorithm

  1. Start with a random seed string
  2. For each iteration (up to m_hat times):
     - Compute dissimilarities from current seed to all strings
     - Select the string most dissimilar from all previous seeds
     - Add it to the seed set
  3. Return the cache of computed dissimilarities

  ## Parameters

    - `strings` - Dataset to sample from
    - `m_hat` - Number of seed strings to select (typically ⌈θ·M⌉ where θ ≈ 0.05)
    - `atoms` - Available atoms for pattern learning (defaults to all default atoms)

  ## Returns

  A map from `{string1, string2}` tuples to `{pattern, cost}` tuples,
  where pattern may be nil if no pattern was found (cost will be :infinity).

  ## Examples

      iex> alias FlashProfile.Clustering.Dissimilarity
      iex> strings = ["PMC123", "PMC456", "ABC789"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 2)
      iex> map_size(cache) > 0
      true
  """
  @spec sample_dissimilarities([String.t()], non_neg_integer(), [Atom.t()]) :: cache()
  def sample_dissimilarities(strings, m_hat, atoms \\ FlashProfile.Atoms.Defaults.all())
  def sample_dissimilarities([], _m_hat, _atoms), do: %{}
  def sample_dissimilarities([_single], _m_hat, _atoms), do: %{}

  def sample_dissimilarities(strings, m_hat, atoms) do
    # Start with random seed string
    seed = Enum.random(strings)

    # Iteratively select most dissimilar strings
    {cache, _seeds} =
      Enum.reduce(1..m_hat, {%{}, [seed]}, fn _i, {cache_acc, seeds} ->
        current_seed = hd(seeds)

        # Compute dissimilarities from current seed to all strings
        new_cache =
          Enum.reduce(strings, cache_acc, fn s, acc ->
            key = normalize_key(current_seed, s)

            if Map.has_key?(acc, key) do
              acc
            else
              case Learner.learn_best_pattern([current_seed, s], atoms) do
                {:error, :no_pattern} ->
                  Map.put(acc, key, {nil, :infinity})

                {pattern, cost} ->
                  Map.put(acc, key, {pattern, cost})
              end
            end
          end)

        # Find most dissimilar string from all seeds
        next_seed = find_most_dissimilar(strings, seeds, new_cache)

        {new_cache, [next_seed | seeds]}
      end)

    cache
  end

  @doc """
  Build a complete dissimilarity matrix using cached patterns.

  Implements the ApproxDMatrix algorithm from Figure 10 of the paper.
  Constructs a full dissimilarity matrix by:

  1. Using cached dissimilarities when available
  2. Trying to reuse cached patterns that match both strings
  3. Computing new patterns only when necessary

  Returns a map of {x, y} => dissimilarity for all pairs in strings.
  Uses normalized keys so the matrix is symmetric.

  ## Parameters

    - `strings` - List of strings to build matrix for
    - `cache` - Cache from `sample_dissimilarities/3`
    - `atoms` - Available atoms for pattern learning (defaults to all default atoms)

  ## Returns

  A map from `{string1, string2}` tuples to dissimilarity values.
  The matrix is symmetric: `matrix[{a,b}] == matrix[{b,a}]`.

  ## Examples

      iex> alias FlashProfile.Clustering.Dissimilarity
      iex> strings = ["PMC123", "PMC456"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 1)
      iex> matrix = Dissimilarity.build_matrix(strings, cache)
      iex> Dissimilarity.get_dissimilarity(matrix, "PMC123", "PMC123")
      0.0
  """
  @spec build_matrix([String.t()], cache(), [Atom.t()]) :: matrix()
  def build_matrix(strings, cache, atoms \\ FlashProfile.Atoms.Defaults.all()) do
    # Build list of all cached patterns
    cached_patterns =
      cache
      |> Map.values()
      |> Enum.filter(fn {pattern, _cost} -> pattern != nil end)
      |> Enum.map(fn {pattern, _cost} -> pattern end)
      |> Enum.uniq()

    # Build matrix
    for x <- strings, y <- strings, into: %{} do
      key = normalize_key(x, y)
      dissimilarity = compute_with_cache(x, y, key, cache, cached_patterns, atoms)
      {key, dissimilarity}
    end
  end

  @doc """
  Get dissimilarity from matrix (handles key normalization).

  Retrieves the dissimilarity between two strings from a matrix,
  automatically normalizing the key to handle symmetry.

  ## Parameters

    - `matrix` - Dissimilarity matrix from `build_matrix/3`
    - `x` - First string
    - `y` - Second string

  ## Returns

  The dissimilarity value, or `:infinity` if not found in the matrix.

  ## Examples

      iex> alias FlashProfile.Clustering.Dissimilarity
      iex> matrix = %{{{"a", "b"} => 5.0, {"a", "a"} => 0.0}}
      iex> Dissimilarity.get_dissimilarity(matrix, "a", "b")
      5.0
      iex> Dissimilarity.get_dissimilarity(matrix, "b", "a")
      5.0
  """
  @spec get_dissimilarity(matrix(), String.t(), String.t()) :: dissimilarity()
  def get_dissimilarity(matrix, x, y) do
    Map.get(matrix, normalize_key(x, y), :infinity)
  end

  @doc """
  Convert dissimilarity matrix to list format for clustering.

  Returns list of {x, y, dissimilarity} tuples. Only includes entries
  where x <= y to avoid duplicates (since the matrix is symmetric).

  ## Parameters

    - `matrix` - Dissimilarity matrix from `build_matrix/3`

  ## Returns

  A list of `{string1, string2, dissimilarity}` tuples.

  ## Examples

      iex> alias FlashProfile.Clustering.Dissimilarity
      iex> matrix = %{{{"a", "b"} => 5.0, {"a", "a"} => 0.0}}
      iex> list = Dissimilarity.matrix_to_list(matrix)
      iex> length(list) == 2
      true
  """
  @spec matrix_to_list(matrix()) :: [{String.t(), String.t(), dissimilarity()}]
  def matrix_to_list(matrix) do
    Enum.map(matrix, fn {{x, y}, diss} -> {x, y, diss} end)
  end

  ## Private Helper Functions

  # Normalize key so {a,b} and {b,a} map to same entry
  # This ensures the dissimilarity matrix is symmetric
  @spec normalize_key(String.t(), String.t()) :: {String.t(), String.t()}
  defp normalize_key(a, b) when a <= b, do: {a, b}
  defp normalize_key(a, b), do: {b, a}

  # Find the string most dissimilar from all seeds so far
  # This implements the argmax_{x∈S} min_{y∈ρ} D[y,x].Cost from the paper
  @spec find_most_dissimilar([String.t()], [String.t()], cache()) :: String.t()
  defp find_most_dissimilar(strings, seeds, cache) do
    strings
    |> Enum.max_by(
      fn x ->
        # Min dissimilarity to any seed
        min_diss =
          seeds
          |> Enum.map(fn seed ->
            key = normalize_key(seed, x)

            case Map.get(cache, key) do
              nil -> :infinity
              {_pattern, cost} -> cost
            end
          end)
          |> Enum.min(fn
            :infinity, :infinity -> true
            :infinity, _ -> false
            _, :infinity -> true
            a, b -> a <= b
          end)

        # We want to maximize the minimum dissimilarity
        min_diss
      end,
      fn
        :infinity, :infinity -> true
        :infinity, _ -> false
        _, :infinity -> true
        a, b -> a >= b
      end
    )
  end

  # Compute dissimilarity with cache lookup and pattern reuse
  # Implements the ApproxDMatrix logic from Figure 10
  @spec compute_with_cache(
          String.t(),
          String.t(),
          {String.t(), String.t()},
          cache(),
          [Pattern.t()],
          [Atom.t()]
        ) :: dissimilarity()
  defp compute_with_cache(x, x, _key, _cache, _patterns, _atoms), do: 0.0

  defp compute_with_cache(x, y, key, cache, cached_patterns, atoms) do
    # Check if already in cache
    case Map.get(cache, key) do
      {_pattern, cost} ->
        cost

      nil ->
        # Try to find a cached pattern that matches both
        matching_patterns =
          cached_patterns
          |> Enum.filter(fn pattern ->
            Pattern.matches?(pattern, x) and Pattern.matches?(pattern, y)
          end)

        if matching_patterns == [] do
          # No cached pattern works, compute directly
          compute(x, y, atoms)
        else
          # Use best (lowest cost) matching pattern
          matching_patterns
          |> Enum.map(fn pattern ->
            Cost.calculate(pattern, [x, y])
          end)
          |> Enum.min(fn
            :infinity, :infinity -> true
            :infinity, _ -> false
            _, :infinity -> true
            a, b -> a <= b
          end)
        end
    end
  end
end
