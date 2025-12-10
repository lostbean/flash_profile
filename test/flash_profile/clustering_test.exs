defmodule FlashProfile.ClusteringTest do
  use ExUnit.Case, async: true

  doctest FlashProfile.Clustering

  alias FlashProfile.Clustering

  describe "Initial clustering" do
    test "initial_clustering groups by skeleton" do
      groups = Clustering.initial_clustering(["A-1", "B-2", "C-3"])
      assert map_size(groups) == 1
    end

    test "initial_clustering separates different structures" do
      groups = Clustering.initial_clustering(["A-1", "A@B"])
      assert map_size(groups) == 2
    end

    test "initial_clustering handles empty list" do
      groups = Clustering.initial_clustering([])
      assert groups == %{}
    end
  end

  describe "Skeleton distance" do
    test "skeleton_distance zero for identical" do
      assert Clustering.skeleton_distance("X-X", "X-X") == 0.0
    end

    test "skeleton_distance zero for normalized identical" do
      # XX-X and XXX-X both normalize to X-X
      assert Clustering.skeleton_distance("XX-X", "XXX-X") == 0.0
    end

    test "skeleton_distance non-zero for different" do
      assert Clustering.skeleton_distance("X-X", "X@X") > 0.0
    end
  end

  describe "Full clustering" do
    test "cluster merges similar structures" do
      data = ["ACC-001", "ACCT-002", "ORG-003"]
      clusters = Clustering.cluster(data)
      assert length(clusters) == 1
    end

    test "cluster separates different structures" do
      data = ["A-1", "B@C.D"]
      clusters = Clustering.cluster(data)
      assert length(clusters) == 2
    end

    test "cluster respects max_clusters option" do
      # Create 10 different structures
      data = for i <- 1..10, do: String.duplicate("A", i) <> "-1"
      clusters = Clustering.cluster(data, max_clusters: 3)
      assert length(clusters) <= 3
    end

    test "cluster respects min_cluster_size option" do
      # One large group, one singleton
      data = for(_ <- 1..10, do: "A-1") ++ ["X@Y"]
      clusters = Clustering.cluster(data, min_cluster_size: 2)
      # Singleton should be filtered out
      assert Enum.all?(clusters, fn c -> length(c.members) >= 2 end)
    end
  end

  describe "Cluster properties" do
    test "cluster includes all members" do
      data = ["A-1", "B-2", "C-3"]
      clusters = Clustering.cluster(data)
      all_members = clusters |> Enum.flat_map(& &1.members) |> Enum.sort()
      assert all_members == Enum.sort(data)
    end

    test "cluster has representative" do
      clusters = Clustering.cluster(["A-1", "B-2", "C-3"])
      assert Enum.all?(clusters, &Map.has_key?(&1, :representative))
    end

    test "cluster has signature" do
      clusters = Clustering.cluster(["ABC-123"])
      assert hd(clusters).signature == "UUU-DDD"
    end

    test "cluster has compact_signature" do
      clusters = Clustering.cluster(["ABC-123"])
      assert hd(clusters).compact_signature == "U-D"
    end
  end

  describe "Cluster stats" do
    test "cluster_stats returns size" do
      clusters = Clustering.cluster(["A-1", "B-2", "C-3"])
      stats = Clustering.cluster_stats(hd(clusters))
      assert stats.size == 3
    end

    test "cluster_stats returns length range" do
      clusters = Clustering.cluster(["A-1", "BB-22", "CCC-333"])
      stats = Clustering.cluster_stats(hd(clusters))
      assert stats.min_length == 3
      assert stats.max_length == 7
    end
  end
end
