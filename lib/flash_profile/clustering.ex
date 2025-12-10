defmodule FlashProfile.Clustering do
  @moduledoc """
  Clusters strings by structural similarity.

  This module addresses the "signature-based fragmentation" problem by:
  1. Using a flexible distance metric that tolerates minor structural differences
  2. Hierarchical clustering with controllable granularity
  3. Smart merging of clusters that share the same semantic format

  ## Algorithm

  1. Tokenize all strings and compute signatures
  2. Group by compact signature (delimiter structure)
  3. Within groups, further cluster by length patterns if needed
  4. Merge clusters that can be represented by a single pattern
  """

  alias FlashProfile.Tokenizer

  @type cluster :: %{
          id: non_neg_integer(),
          members: [String.t()],
          signature: String.t(),
          compact_signature: String.t(),
          representative: String.t()
        }

  @doc """
  Clusters strings into groups with similar structure.

  ## Options

  - `:max_clusters` - Maximum number of clusters (default: 10)
  - `:min_cluster_size` - Minimum members per cluster (default: 1)
  - `:merge_threshold` - Distance threshold for merging (default: 0.3)

  ## Examples

      iex> clusters = FlashProfile.Clustering.cluster(["ACC-001", "ACC-002", "ORG-001", "ORG-002"])
      iex> length(clusters)
      1
      iex> hd(clusters).members |> Enum.sort()
      ["ACC-001", "ACC-002", "ORG-001", "ORG-002"]

      iex> clusters = FlashProfile.Clustering.cluster(["hello@world.com", "foo@bar.org", "ABC-123"])
      iex> length(clusters)
      2
  """
  @spec cluster([String.t()], keyword()) :: [cluster()]
  def cluster(strings, opts \\ []) do
    max_clusters = Keyword.get(opts, :max_clusters, 10)
    min_cluster_size = Keyword.get(opts, :min_cluster_size, 1)
    merge_threshold = Keyword.get(opts, :merge_threshold, 0.3)

    strings
    |> initial_clustering()
    |> merge_similar_clusters(merge_threshold)
    |> enforce_cluster_limits(max_clusters, min_cluster_size)
    |> finalize_clusters()
  end

  @doc """
  Performs initial clustering based on delimiter structure.

  This groups strings that have the same "skeleton" - same delimiters
  in the same positions. E.g., "ACC-001" and "ACCT-00123" both have
  skeleton "X-X" and would be grouped together.
  """
  @spec initial_clustering([String.t()]) :: %{String.t() => [String.t()]}
  def initial_clustering(strings) do
    strings
    |> Enum.group_by(&delimiter_skeleton/1)
  end

  defp delimiter_skeleton(string) do
    tokens = Tokenizer.tokenize(string)

    tokens
    |> Enum.map(fn token ->
      case token.type do
        :delimiter -> token.value
        :whitespace -> "_"
        _ -> "X"
      end
    end)
    |> Enum.join()
  end

  @doc """
  Merges clusters that are similar enough to be represented by one pattern.
  """
  @spec merge_similar_clusters(%{String.t() => [String.t()]}, float()) :: [[String.t()]]
  def merge_similar_clusters(skeleton_groups, threshold) do
    # Convert to list of {skeleton, members} and sort by size (descending)
    groups =
      skeleton_groups
      |> Enum.map(fn {skeleton, members} -> {skeleton, members} end)
      |> Enum.sort_by(fn {_, members} -> -length(members) end)

    # Merge similar skeletons
    merge_groups(groups, threshold, [])
  end

  defp merge_groups([], _threshold, acc), do: Enum.reverse(acc)

  defp merge_groups([{skeleton, members} | rest], threshold, acc) do
    # Find groups that can be merged with this one
    {mergeable, remaining} =
      Enum.split_with(rest, fn {other_skeleton, _} ->
        skeleton_distance(skeleton, other_skeleton) <= threshold
      end)

    # Combine all mergeable groups
    merged_members =
      [members | Enum.map(mergeable, fn {_, m} -> m end)]
      |> List.flatten()

    merge_groups(remaining, threshold, [merged_members | acc])
  end

  @doc """
  Calculates the distance between two skeletons.

  Returns a value between 0.0 (identical) and 1.0 (completely different).
  """
  @spec skeleton_distance(String.t(), String.t()) :: float()
  def skeleton_distance(s1, s2) when s1 == s2, do: 0.0

  def skeleton_distance(s1, s2) do
    # Normalize: count X's as equivalent regardless of count
    n1 = normalize_skeleton(s1)
    n2 = normalize_skeleton(s2)

    if n1 == n2 do
      0.0
    else
      # Use Levenshtein-like distance on normalized form
      edit_distance(n1, n2) / max(String.length(n1), String.length(n2))
    end
  end

  defp normalize_skeleton(skeleton) do
    # Collapse consecutive X's into single X
    skeleton
    |> String.replace(~r/X+/, "X")
  end

  defp edit_distance(s1, s2) do
    # Simple Levenshtein implementation
    m = String.length(s1)
    n = String.length(s2)

    cond do
      m == 0 ->
        n

      n == 0 ->
        m

      true ->
        s1_chars = String.graphemes(s1)
        s2_chars = String.graphemes(s2)

        # Initialize first row
        first_row = 0..n |> Enum.to_list()

        # Fill matrix
        {final_row, _} =
          s1_chars
          |> Enum.with_index(1)
          |> Enum.reduce({first_row, nil}, fn {c1, i}, {prev_row, _} ->
            new_row =
              s2_chars
              |> Enum.with_index(1)
              |> Enum.reduce([i], fn {c2, j}, row_acc ->
                prev = Enum.at(prev_row, j)
                left = List.last(row_acc)
                diag = Enum.at(prev_row, j - 1)

                cost = if c1 == c2, do: 0, else: 1
                min_val = min(min(prev + 1, left + 1), diag + cost)

                row_acc ++ [min_val]
              end)

            {new_row, prev_row}
          end)

        List.last(final_row)
    end
  end

  @doc """
  Enforces cluster count limits by merging small clusters or splitting large ones.
  """
  @spec enforce_cluster_limits([[String.t()]], pos_integer(), pos_integer()) :: [[String.t()]]
  def enforce_cluster_limits(clusters, max_clusters, min_cluster_size) do
    clusters
    |> Enum.filter(fn members -> length(members) >= min_cluster_size end)
    |> limit_cluster_count(max_clusters)
  end

  defp limit_cluster_count(clusters, max) when length(clusters) <= max, do: clusters

  defp limit_cluster_count(clusters, max) do
    # Sort by size and keep the largest ones
    # Merge the rest into an "other" cluster
    sorted = Enum.sort_by(clusters, &(-length(&1)))

    {keep, merge} = Enum.split(sorted, max - 1)

    merged_other = List.flatten(merge)

    if merged_other == [] do
      keep
    else
      keep ++ [merged_other]
    end
  end

  defp finalize_clusters(cluster_members_list) do
    cluster_members_list
    |> Enum.with_index()
    |> Enum.map(fn {members, idx} ->
      representative = find_representative(members)
      tokens = Tokenizer.tokenize(representative)

      %{
        id: idx,
        members: members,
        signature: Tokenizer.signature(tokens),
        compact_signature: Tokenizer.compact_signature(tokens),
        representative: representative
      }
    end)
  end

  defp find_representative([single]), do: single

  defp find_representative(members) do
    # Choose the most "typical" member - closest to median length
    lengths = Enum.map(members, &String.length/1)
    sorted_lengths = Enum.sort(lengths)
    median_length = Enum.at(sorted_lengths, div(length(sorted_lengths), 2))

    Enum.min_by(members, fn m -> abs(String.length(m) - median_length) end)
  end

  @doc """
  Computes structural statistics for a cluster.
  """
  @spec cluster_stats(cluster()) :: map()
  def cluster_stats(%{members: members}) do
    token_lists = Enum.map(members, &Tokenizer.tokenize/1)

    %{
      size: length(members),
      min_length: members |> Enum.map(&String.length/1) |> Enum.min(),
      max_length: members |> Enum.map(&String.length/1) |> Enum.max(),
      token_count_range: token_count_range(token_lists),
      distinct_values: length(Enum.uniq(members))
    }
  end

  defp token_count_range(token_lists) do
    counts = Enum.map(token_lists, &length/1)
    {Enum.min(counts), Enum.max(counts)}
  end
end
