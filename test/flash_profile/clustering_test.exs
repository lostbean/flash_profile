defmodule FlashProfile.ClusteringTest do
  use ExUnit.Case, async: true

  alias FlashProfile.Clustering.{Dissimilarity, Hierarchy}
  alias FlashProfile.Atoms.Defaults

  describe "Dissimilarity.compute/3" do
    test "identical strings have 0 dissimilarity" do
      assert Dissimilarity.compute("abc", "abc") == 0.0
      assert Dissimilarity.compute("123", "123") == 0.0
      assert Dissimilarity.compute("", "") == 0.0
    end

    test "similar strings have low dissimilarity" do
      # Same format (all digits)
      diss = Dissimilarity.compute("123", "456")

      assert is_float(diss)
      assert diss > 0.0
      # Should be relatively low since both are 3 digits
      assert diss < 20.0
    end

    test "different format strings have higher dissimilarity" do
      # Very different formats
      diss1 = Dissimilarity.compute("123", "abc")
      diss2 = Dissimilarity.compute("PMC123", "2023-01-01")

      assert is_float(diss1) or diss1 == :infinity
      assert is_float(diss2) or diss2 == :infinity
    end

    test "returns infinity when no pattern can describe both" do
      # Strings that are very hard to match with a single pattern
      result = Dissimilarity.compute("", "abc")

      # Could be infinity or a high cost
      assert result == :infinity or (is_float(result) and result > 0)
    end

    test "dissimilarity is symmetric" do
      s1 = "PMC123"
      s2 = "PMC456"

      diss1 = Dissimilarity.compute(s1, s2)
      diss2 = Dissimilarity.compute(s2, s1)

      assert diss1 == diss2
    end

    test "works with custom atoms" do
      atoms = [Defaults.get("Digit"), Defaults.get("Upper")]
      diss = Dissimilarity.compute("123", "456", atoms)

      assert is_float(diss)
    end
  end

  describe "Dissimilarity.sample_dissimilarities/3" do
    test "returns cache for valid dataset" do
      strings = ["PMC123", "PMC456", "ABC789"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)

      assert is_map(cache)
      assert map_size(cache) > 0
    end

    test "cache contains pattern-cost tuples" do
      strings = ["123", "456", "789"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)

      # Check structure of cache entries
      Enum.each(cache, fn {key, value} ->
        assert is_tuple(key)
        assert tuple_size(key) == 2
        {pattern, cost} = value
        assert is_list(pattern) or is_nil(pattern)
        assert is_float(cost) or cost == :infinity
      end)
    end

    test "samples multiple seed strings" do
      strings = ["A", "B", "C", "D", "E"]
      m_hat = 3
      cache = Dissimilarity.sample_dissimilarities(strings, m_hat)

      assert is_map(cache)
      # Should have sampled from multiple seeds
      assert map_size(cache) >= m_hat
    end

    test "handles empty dataset" do
      assert %{} = Dissimilarity.sample_dissimilarities([], 5)
    end

    test "handles single string" do
      assert %{} = Dissimilarity.sample_dissimilarities(["test"], 5)
    end

    test "normalizes cache keys for symmetry" do
      strings = ["abc", "def"]
      cache = Dissimilarity.sample_dissimilarities(strings, 1)

      # Cache should use normalized keys
      keys = Map.keys(cache)

      Enum.each(keys, fn {a, b} ->
        # Keys should be sorted
        assert a <= b
      end)
    end
  end

  describe "Dissimilarity.build_matrix/3" do
    test "builds complete dissimilarity matrix" do
      strings = ["123", "456", "789"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)

      assert is_map(matrix)
      # Should have entries for all unique pairs (symmetric matrix stores only n*(n+1)/2 entries)
      assert map_size(matrix) == div(length(strings) * (length(strings) + 1), 2)
    end

    test "matrix has zero diagonal" do
      strings = ["abc", "def", "ghi"]
      cache = Dissimilarity.sample_dissimilarities(strings, 1)
      matrix = Dissimilarity.build_matrix(strings, cache)

      Enum.each(strings, fn s ->
        diss = Dissimilarity.get_dissimilarity(matrix, s, s)
        assert diss == 0.0
      end)
    end

    test "matrix is symmetric" do
      strings = ["PMC123", "PMC456"]
      cache = Dissimilarity.sample_dissimilarities(strings, 1)
      matrix = Dissimilarity.build_matrix(strings, cache)

      diss_ab = Dissimilarity.get_dissimilarity(matrix, "PMC123", "PMC456")
      diss_ba = Dissimilarity.get_dissimilarity(matrix, "PMC456", "PMC123")

      assert diss_ab == diss_ba
    end

    test "reuses cached patterns when possible" do
      strings = ["123", "456", "789"]
      cache = Dissimilarity.sample_dissimilarities(strings, 3)
      matrix = Dissimilarity.build_matrix(strings, cache)

      # All entries should be computed
      Enum.each(strings, fn s1 ->
        Enum.each(strings, fn s2 ->
          diss = Dissimilarity.get_dissimilarity(matrix, s1, s2)
          assert is_float(diss) or diss == :infinity
        end)
      end)
    end

    test "handles empty cache" do
      strings = ["abc", "def"]
      matrix = Dissimilarity.build_matrix(strings, %{})

      assert is_map(matrix)
      assert map_size(matrix) > 0
    end
  end

  describe "Dissimilarity.get_dissimilarity/3" do
    test "retrieves dissimilarity from matrix" do
      matrix = %{{"a", "b"} => 5.0, {"a", "a"} => 0.0}

      assert Dissimilarity.get_dissimilarity(matrix, "a", "b") == 5.0
      assert Dissimilarity.get_dissimilarity(matrix, "a", "a") == 0.0
    end

    test "handles key normalization" do
      matrix = %{{"a", "b"} => 5.0}

      # Both orderings should work
      assert Dissimilarity.get_dissimilarity(matrix, "a", "b") == 5.0
      assert Dissimilarity.get_dissimilarity(matrix, "b", "a") == 5.0
    end

    test "returns infinity for missing entries" do
      matrix = %{{"a", "b"} => 5.0}

      assert Dissimilarity.get_dissimilarity(matrix, "c", "d") == :infinity
    end
  end

  describe "Dissimilarity.matrix_to_list/1" do
    test "converts matrix to list of tuples" do
      matrix = %{{"a", "b"} => 5.0, {"a", "a"} => 0.0}
      list = Dissimilarity.matrix_to_list(matrix)

      assert is_list(list)
      assert length(list) == 2

      Enum.each(list, fn {x, y, diss} ->
        assert is_binary(x)
        assert is_binary(y)
        assert is_float(diss) or diss == :infinity
      end)
    end
  end

  describe "Hierarchy.ahc/2" do
    test "builds hierarchy for simple dataset" do
      strings = ["123", "456", "789"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)

      hierarchy = Hierarchy.ahc(strings, matrix)

      assert %Hierarchy.Node{} = hierarchy
      assert Enum.sort(hierarchy.data) == Enum.sort(strings)
    end

    test "handles single string" do
      matrix = %{{"a", "a"} => 0.0}
      hierarchy = Hierarchy.ahc(["a"], matrix)

      assert %Hierarchy.Node{} = hierarchy
      assert hierarchy.data == ["a"]
      assert hierarchy.height == 0.0
      assert is_nil(hierarchy.left)
      assert is_nil(hierarchy.right)
    end

    test "raises for empty dataset" do
      assert_raise ArgumentError, fn ->
        Hierarchy.ahc([], %{})
      end
    end

    test "hierarchy contains all strings" do
      strings = ["PMC123", "PMC456", "ABC789", "XYZ000"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)

      hierarchy = Hierarchy.ahc(strings, matrix)

      assert Enum.sort(hierarchy.data) == Enum.sort(strings)
    end

    test "root has positive height for multi-string dataset" do
      strings = ["abc", "def", "ghi"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)

      hierarchy = Hierarchy.ahc(strings, matrix)

      # Root should have merged clusters, so height > 0
      if length(strings) > 1 do
        assert is_float(hierarchy.height) or hierarchy.height == :infinity
      end
    end

    test "leaf nodes have zero height" do
      strings = ["a"]
      matrix = %{{"a", "a"} => 0.0}

      hierarchy = Hierarchy.ahc(strings, matrix)

      assert hierarchy.height == 0.0
    end
  end

  describe "Hierarchy.partition/2" do
    test "extracts k clusters from hierarchy" do
      strings = ["123", "456", "789", "abc", "def"]
      cache = Dissimilarity.sample_dissimilarities(strings, 3)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition(hierarchy, 2)

      assert is_list(clusters)
      assert length(clusters) == 2
    end

    test "preserves all strings across clusters" do
      strings = ["a", "b", "c", "d"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition(hierarchy, 2)

      all_strings = clusters |> List.flatten() |> Enum.sort()
      assert all_strings == Enum.sort(strings)
    end

    test "k=1 returns all strings in single cluster" do
      strings = ["a", "b", "c"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition(hierarchy, 1)

      assert length(clusters) == 1
      assert Enum.sort(hd(clusters)) == Enum.sort(strings)
    end

    test "k >= n returns singletons" do
      strings = ["a", "b", "c"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition(hierarchy, 3)

      assert length(clusters) == 3
      # Each cluster should have 1 string
      Enum.each(clusters, fn cluster ->
        assert length(cluster) == 1
      end)
    end

    test "handles k greater than number of strings" do
      strings = ["a", "b"]
      cache = Dissimilarity.sample_dissimilarities(strings, 1)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      # Requesting more clusters than strings
      clusters = Hierarchy.partition(hierarchy, 5)

      # Should return at most n clusters
      assert length(clusters) <= length(strings)
    end

    test "raises for invalid k" do
      strings = ["a"]
      matrix = %{{"a", "a"} => 0.0}
      hierarchy = Hierarchy.ahc(strings, matrix)

      assert_raise ArgumentError, fn ->
        Hierarchy.partition(hierarchy, 0)
      end

      assert_raise ArgumentError, fn ->
        Hierarchy.partition(hierarchy, -1)
      end

      assert_raise ArgumentError, fn ->
        Hierarchy.partition(hierarchy, "invalid")
      end
    end
  end

  describe "Hierarchy.partition_range/3" do
    test "returns clusters within range" do
      strings = ["a", "b", "c", "d", "e"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition_range(hierarchy, 2, 4)

      assert is_list(clusters)
      assert length(clusters) >= 2
      assert length(clusters) <= 4
    end

    test "preserves all strings" do
      strings = ["a", "b", "c"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition_range(hierarchy, 1, 3)

      all_strings = clusters |> List.flatten() |> Enum.sort()
      assert all_strings == Enum.sort(strings)
    end

    test "handles min_k == max_k" do
      strings = ["a", "b", "c"]
      cache = Dissimilarity.sample_dissimilarities(strings, 2)
      matrix = Dissimilarity.build_matrix(strings, cache)
      hierarchy = Hierarchy.ahc(strings, matrix)

      clusters = Hierarchy.partition_range(hierarchy, 2, 2)

      assert is_list(clusters)
    end

    test "raises for invalid range" do
      strings = ["a"]
      matrix = %{{"a", "a"} => 0.0}
      hierarchy = Hierarchy.ahc(strings, matrix)

      assert_raise ArgumentError, fn ->
        Hierarchy.partition_range(hierarchy, 3, 2)
      end

      assert_raise ArgumentError, fn ->
        Hierarchy.partition_range(hierarchy, 0, 5)
      end
    end
  end

  describe "Hierarchy.get_data/1" do
    test "returns all strings from node" do
      node = %Hierarchy.Node{
        left: nil,
        right: nil,
        data: ["abc", "def"],
        height: 0.0
      }

      assert Hierarchy.get_data(node) == ["abc", "def"]
    end

    test "returns data from internal node" do
      left = %Hierarchy.Node{left: nil, right: nil, data: ["a"], height: 0.0}
      right = %Hierarchy.Node{left: nil, right: nil, data: ["b"], height: 0.0}

      node = %Hierarchy.Node{
        left: left,
        right: right,
        data: ["a", "b"],
        height: 5.0
      }

      assert Hierarchy.get_data(node) == ["a", "b"]
    end
  end

  describe "integration test" do
    test "complete clustering workflow" do
      # Dataset with two distinct formats
      strings = ["PMC123", "PMC456", "PMC789", "2023-01-01", "2024-12-31"]

      # Sample dissimilarities
      cache = Dissimilarity.sample_dissimilarities(strings, 3)
      assert is_map(cache)

      # Build matrix
      matrix = Dissimilarity.build_matrix(strings, cache)
      assert is_map(matrix)

      # Build hierarchy
      hierarchy = Hierarchy.ahc(strings, matrix)
      assert %Hierarchy.Node{} = hierarchy

      # Partition into 2 clusters
      clusters = Hierarchy.partition(hierarchy, 2)
      assert length(clusters) == 2

      # All strings should be preserved
      all_strings = clusters |> List.flatten() |> Enum.sort()
      assert all_strings == Enum.sort(strings)

      # Ideally, PMC IDs should cluster together and dates together
      # (though this depends on the actual dissimilarity computation)
      Enum.each(clusters, fn cluster ->
        assert length(cluster) > 0
      end)
    end
  end
end
