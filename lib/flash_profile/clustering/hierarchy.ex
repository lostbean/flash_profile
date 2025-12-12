defmodule FlashProfile.Clustering.Hierarchy do
  @moduledoc """
  Hierarchical clustering implementation for pattern grouping.

  Implements hierarchical clustering algorithms used to group similar
  strings together before pattern learning, improving the quality of
  learned patterns for heterogeneous datasets.

  ## Algorithm

  Uses Agglomerative Hierarchical Clustering (AHC) with complete-linkage
  criterion as described in Figure 11 of the FlashProfile paper:

  ```
  func AHC(S, A)
    H ← {{s} | s ∈ S}  // Singleton sets
    while |H| > 1 do
      (X, Y) ← argmin_{X,Y∈H} η̂(X, Y | A)  // Complete-linkage
      H ← (H \ {X, Y}) ∪ {merge(X, Y)}
    return H
  ```

  Complete-linkage criterion: η̂(X, Y | A) = max_{x∈X, y∈Y} A[x,y]

  ## Hierarchy Structure

  The clustering result is represented as a binary tree (dendrogram):
  - Leaf nodes contain singleton string lists
  - Internal nodes represent merged clusters
  - Height represents the linkage distance at merge time

  ## Examples

      iex> alias FlashProfile.Clustering.{Hierarchy, Dissimilarity}
      iex> strings = ["PMC123", "PMC456", "ABC789"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 2)
      iex> matrix = Dissimilarity.build_matrix(strings, cache)
      iex> hierarchy = Hierarchy.ahc(strings, matrix)
      iex> clusters = Hierarchy.partition(hierarchy, 2)
      iex> length(clusters)
      2
  """

  alias FlashProfile.Clustering.Dissimilarity

  defmodule Node do
    @moduledoc """
    A node in the hierarchical clustering tree (dendrogram).

    Represents either:
    - A leaf node: contains a single string (left/right are nil)
    - An internal node: contains merged clusters (left/right are child nodes)

    ## Fields

    - `left` - Left child node (nil for leaves)
    - `right` - Right child node (nil for leaves)
    - `data` - List of all strings in this cluster
    - `height` - Linkage distance at which this merge occurred (0.0 for leaves)
    """

    defstruct [:left, :right, :data, :height]

    @type t :: %__MODULE__{
            left: t() | nil,
            right: t() | nil,
            data: [String.t()],
            height: float()
          }
  end

  @type cluster_set :: %{reference() => Node.t()}
  @type matrix :: Dissimilarity.matrix()

  @doc """
  Build hierarchical clustering from strings and dissimilarity matrix.

  Implements the AHC (Agglomerative Hierarchical Clustering) algorithm
  from Figure 11 of the FlashProfile paper, using complete-linkage criterion.

  ## Algorithm

  1. Start with each string as a singleton cluster (leaf node)
  2. Repeat until only one cluster remains:
     - Find the pair of clusters with minimum complete-linkage distance
     - Merge them into a new cluster (internal node)
     - Set new node's height to the linkage distance
  3. Return the root of the resulting hierarchy

  ## Parameters

    - `strings` - List of strings to cluster
    - `matrix` - Dissimilarity matrix from `Dissimilarity.build_matrix/3`

  ## Returns

  A `Node.t()` representing the root of the hierarchical clustering tree.

  ## Examples

      iex> alias FlashProfile.Clustering.{Hierarchy, Dissimilarity}
      iex> strings = ["123", "456", "abc"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 1)
      iex> matrix = Dissimilarity.build_matrix(strings, cache)
      iex> hierarchy = Hierarchy.ahc(strings, matrix)
      iex> Hierarchy.get_data(hierarchy)
      ["123", "456", "abc"]
  """
  @spec ahc([String.t()], matrix()) :: Node.t()
  def ahc([], _matrix) do
    raise ArgumentError, "cannot cluster empty list of strings"
  end

  def ahc([single], _matrix) do
    # Single string: return leaf node
    %Node{left: nil, right: nil, data: [single], height: 0.0}
  end

  def ahc(strings, matrix) do
    # Initialize: create singleton clusters (leaf nodes)
    initial_clusters =
      strings
      |> Enum.map(fn s ->
        ref = make_ref()
        node = %Node{left: nil, right: nil, data: [s], height: 0.0}
        {ref, node}
      end)
      |> Map.new()

    # Run AHC algorithm
    ahc_loop(initial_clusters, matrix)
  end

  @doc """
  Extract k clusters from hierarchy by cutting at appropriate level.

  Partitions the hierarchical clustering tree into k clusters by iteratively
  splitting the cluster with the largest height until k clusters are obtained.

  ## Algorithm

  1. Start with the root node as a single active cluster
  2. While we have fewer than k clusters:
     - Find the active node with maximum height
     - Replace it with its two children
  3. Return the data from all active nodes

  ## Parameters

    - `hierarchy` - Root node from `ahc/2`
    - `k` - Number of clusters to extract (must be >= 1)

  ## Returns

  A list of clusters, where each cluster is a list of strings.

  ## Examples

      iex> alias FlashProfile.Clustering.{Hierarchy, Dissimilarity}
      iex> strings = ["123", "456", "789", "abc"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 2)
      iex> matrix = Dissimilarity.build_matrix(strings, cache)
      iex> hierarchy = Hierarchy.ahc(strings, matrix)
      iex> clusters = Hierarchy.partition(hierarchy, 2)
      iex> length(clusters)
      2
  """
  @spec partition(Node.t(), pos_integer()) :: [[String.t()]]
  def partition(%Node{} = hierarchy, k) when is_integer(k) and k >= 1 do
    total_strings = length(hierarchy.data)

    # Clamp k to valid range
    k = min(k, total_strings)

    if k == 1 do
      # Return all data as single cluster
      [hierarchy.data]
    else
      # Start with root as single active node
      partition_loop([hierarchy], k)
    end
  end

  def partition(_hierarchy, k) do
    raise ArgumentError, "k must be a positive integer, got: #{inspect(k)}"
  end

  @doc """
  Partition hierarchy to get between min_k and max_k clusters.

  Useful for adaptive clustering where the exact number of clusters
  is not known in advance. Returns a partition with at most max_k clusters
  and at least min_k clusters (unless the hierarchy has fewer leaves).

  ## Parameters

    - `hierarchy` - Root node from `ahc/2`
    - `min_k` - Minimum number of clusters (must be >= 1)
    - `max_k` - Maximum number of clusters (must be >= min_k)

  ## Returns

  A list of clusters, where each cluster is a list of strings.

  ## Examples

      iex> alias FlashProfile.Clustering.{Hierarchy, Dissimilarity}
      iex> strings = ["123", "456", "789"]
      iex> cache = Dissimilarity.sample_dissimilarities(strings, 1)
      iex> matrix = Dissimilarity.build_matrix(strings, cache)
      iex> hierarchy = Hierarchy.ahc(strings, matrix)
      iex> clusters = Hierarchy.partition_range(hierarchy, 2, 3)
      iex> length(clusters) >= 2 and length(clusters) <= 3
      true
  """
  @spec partition_range(Node.t(), pos_integer(), pos_integer()) :: [[String.t()]]
  def partition_range(%Node{} = hierarchy, min_k, max_k)
      when is_integer(min_k) and is_integer(max_k) and min_k >= 1 and max_k >= min_k do
    total_strings = length(hierarchy.data)

    # Clamp to valid range
    actual_max_k = min(max_k, total_strings)
    actual_min_k = min(min_k, actual_max_k)

    # Use max_k as target
    partition(hierarchy, actual_max_k)
    |> Enum.filter(fn cluster -> length(cluster) >= 1 end)
    |> ensure_min_clusters(actual_min_k)
  end

  def partition_range(_hierarchy, min_k, max_k) do
    raise ArgumentError,
          "invalid range: min_k=#{inspect(min_k)}, max_k=#{inspect(max_k)}"
  end

  @doc """
  Get all strings from a hierarchy node.

  Returns the list of strings contained in the node and all its descendants.

  ## Parameters

    - `node` - A node in the hierarchical clustering tree

  ## Returns

  A list of all strings in the node's subtree.

  ## Examples

      iex> alias FlashProfile.Clustering.Hierarchy
      iex> node = %Hierarchy.Node{left: nil, right: nil, data: ["abc"], height: 0.0}
      iex> Hierarchy.get_data(node)
      ["abc"]
  """
  @spec get_data(Node.t()) :: [String.t()]
  def get_data(%Node{data: data}), do: data

  ## Private Helper Functions

  # Main AHC loop - merges clusters until only one remains
  @spec ahc_loop(cluster_set(), matrix()) :: Node.t()
  defp ahc_loop(clusters, _matrix) when map_size(clusters) == 1 do
    # Only one cluster left - return it
    clusters |> Map.values() |> hd()
  end

  defp ahc_loop(clusters, matrix) do
    # Find pair of clusters with minimum complete-linkage distance
    {ref_x, ref_y, linkage_dist} = find_min_linkage_pair(clusters, matrix)

    # Get the two clusters to merge
    node_x = Map.fetch!(clusters, ref_x)
    node_y = Map.fetch!(clusters, ref_y)

    # Create merged cluster
    merged_node = %Node{
      left: node_x,
      right: node_y,
      data: node_x.data ++ node_y.data,
      height: linkage_dist
    }

    # Update cluster set: remove X and Y, add merged
    new_clusters =
      clusters
      |> Map.delete(ref_x)
      |> Map.delete(ref_y)
      |> Map.put(make_ref(), merged_node)

    # Continue merging
    ahc_loop(new_clusters, matrix)
  end

  # Find the pair of clusters with minimum complete-linkage distance
  # Returns {ref_x, ref_y, distance}
  @spec find_min_linkage_pair(cluster_set(), matrix()) ::
          {reference(), reference(), float()}
  defp find_min_linkage_pair(clusters, matrix) do
    cluster_list = Map.to_list(clusters)

    # Generate all pairs
    pairs =
      for {ref_x, node_x} <- cluster_list,
          {ref_y, node_y} <- cluster_list,
          ref_x < ref_y do
        linkage = complete_linkage(node_x, node_y, matrix)
        {ref_x, ref_y, linkage}
      end

    # Find minimum
    pairs
    |> Enum.min_by(
      fn {_ref_x, _ref_y, dist} -> dist end,
      fn
        :infinity, :infinity -> true
        :infinity, _ -> false
        _, :infinity -> true
        a, b -> a <= b
      end
    )
  end

  # Complete-linkage criterion: max dissimilarity between any two elements
  # η̂(X, Y | A) = max_{x∈X, y∈Y} A[x,y]
  @spec complete_linkage(Node.t(), Node.t(), matrix()) :: float() | :infinity
  defp complete_linkage(node_x, node_y, matrix) do
    # Compute max dissimilarity between all pairs
    for x <- node_x.data, y <- node_y.data do
      Dissimilarity.get_dissimilarity(matrix, x, y)
    end
    |> Enum.max(fn
      :infinity, :infinity -> true
      :infinity, _ -> false
      _, :infinity -> true
      a, b -> a >= b
    end)
  end

  # Partition loop - iteratively split clusters until we have k
  @spec partition_loop([Node.t()], pos_integer()) :: [[String.t()]]
  defp partition_loop(active_nodes, k) when length(active_nodes) >= k do
    # We have enough clusters - return data
    Enum.map(active_nodes, fn node -> node.data end)
  end

  defp partition_loop(active_nodes, k) do
    # Find node with maximum height
    max_node = Enum.max_by(active_nodes, fn node -> node.height end)

    # Check if it's a leaf (cannot split further)
    if max_node.left == nil and max_node.right == nil do
      # All remaining nodes are leaves - return what we have
      Enum.map(active_nodes, fn node -> node.data end)
    else
      # Replace max node with its children
      new_active =
        active_nodes
        |> Enum.reject(fn node -> node == max_node end)
        |> Kernel.++([max_node.left, max_node.right])

      partition_loop(new_active, k)
    end
  end

  # Ensure we have at least min_k clusters by splitting if necessary
  @spec ensure_min_clusters([[String.t()]], pos_integer()) :: [[String.t()]]
  defp ensure_min_clusters(clusters, min_k) when length(clusters) >= min_k do
    clusters
  end

  defp ensure_min_clusters(clusters, _min_k) do
    # Already have fewer than min_k, just return what we have
    clusters
  end
end
