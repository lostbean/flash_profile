defmodule FlashProfile.CompressTest do
  use ExUnit.Case, async: true

  alias FlashProfile.{Compress, ProfileEntry, Learner}
  alias FlashProfile.Atoms.Defaults

  describe "compress/3" do
    test "returns empty list for empty profile" do
      assert Compress.compress([], 5) == []
    end

    test "returns profile unchanged if already at or below max_patterns" do
      entries = [
        %ProfileEntry{data: ["ABC"], pattern: [], cost: 1.0},
        %ProfileEntry{data: ["DEF"], pattern: [], cost: 2.0}
      ]

      assert Compress.compress(entries, 3) == entries
      assert Compress.compress(entries, 2) == entries
    end

    test "compresses profile with simple patterns" do
      # Create profile entries with real patterns
      {pattern1, cost1} = Learner.learn_best_pattern(["PMC123", "PMC456"])
      {pattern2, cost2} = Learner.learn_best_pattern(["ABC", "DEF"])
      {pattern3, cost3} = Learner.learn_best_pattern(["999", "888"])

      entries = [
        %ProfileEntry{data: ["PMC123", "PMC456"], pattern: pattern1, cost: cost1},
        %ProfileEntry{data: ["ABC", "DEF"], pattern: pattern2, cost: cost2},
        %ProfileEntry{data: ["999", "888"], pattern: pattern3, cost: cost3}
      ]

      compressed = Compress.compress(entries, 2)

      # Should have exactly 2 entries
      assert length(compressed) == 2

      # Total data count should be preserved
      total_data = compressed |> Enum.flat_map(& &1.data) |> Enum.sort()
      original_data = entries |> Enum.flat_map(& &1.data) |> Enum.sort()
      assert total_data == original_data
    end

    test "compresses down to 1 pattern" do
      entries = [
        %ProfileEntry{data: ["123"], pattern: [], cost: 1.0},
        %ProfileEntry{data: ["456"], pattern: [], cost: 2.0},
        %ProfileEntry{data: ["789"], pattern: [], cost: 3.0}
      ]

      compressed = Compress.compress(entries, 1)

      assert length(compressed) == 1
      assert Enum.sort(hd(compressed).data) == ["123", "456", "789"]
    end

    test "raises ArgumentError for invalid max_patterns" do
      entries = [%ProfileEntry{data: ["ABC"], pattern: [], cost: 1.0}]

      assert_raise ArgumentError, fn ->
        Compress.compress(entries, 0)
      end

      assert_raise ArgumentError, fn ->
        Compress.compress(entries, -1)
      end

      assert_raise ArgumentError, fn ->
        Compress.compress(entries, "invalid")
      end
    end

    test "raises ArgumentError for invalid profile" do
      assert_raise ArgumentError, fn ->
        Compress.compress("not a list", 5)
      end
    end
  end

  describe "find_best_merge_pair/2" do
    test "returns nil for empty profile" do
      assert Compress.find_best_merge_pair([]) == nil
    end

    test "returns nil for single-entry profile" do
      entry = %ProfileEntry{data: ["ABC"], pattern: [], cost: 1.0}
      assert Compress.find_best_merge_pair([entry]) == nil
    end

    test "finds best pair for two entries" do
      entry1 = %ProfileEntry{data: ["123"], pattern: [], cost: 1.0}
      entry2 = %ProfileEntry{data: ["456"], pattern: [], cost: 2.0}

      result = Compress.find_best_merge_pair([entry1, entry2])

      assert {e1, e2, merged} = result
      assert e1 == entry1
      assert e2 == entry2
      assert Enum.sort(merged.data) == ["123", "456"]
      assert is_float(merged.cost) or merged.cost == :infinity
    end

    test "finds best pair among multiple entries" do
      # Create entries with patterns that are easier to merge
      {pattern1, cost1} = Learner.learn_best_pattern(["ABC", "DEF"])
      {pattern2, cost2} = Learner.learn_best_pattern(["123", "456"])
      {pattern3, cost3} = Learner.learn_best_pattern(["XYZ"])

      entries = [
        %ProfileEntry{data: ["ABC", "DEF"], pattern: pattern1, cost: cost1},
        %ProfileEntry{data: ["123", "456"], pattern: pattern2, cost: cost2},
        %ProfileEntry{data: ["XYZ"], pattern: pattern3, cost: cost3}
      ]

      result = Compress.find_best_merge_pair(entries)

      assert {e1, e2, merged} = result
      # Should return one of the valid pairs
      assert e1 in entries
      assert e2 in entries
      assert e1 != e2
      assert length(merged.data) == length(e1.data) + length(e2.data)
    end
  end

  describe "merge_entries/3" do
    test "merges two entries with compatible data" do
      entry1 = %ProfileEntry{data: ["123"], pattern: [], cost: 1.0}
      entry2 = %ProfileEntry{data: ["456"], pattern: [], cost: 2.0}

      merged = Compress.merge_entries(entry1, entry2)

      assert merged.data == ["123", "456"]
      assert is_list(merged.pattern) or is_nil(merged.pattern)
      assert is_float(merged.cost) or merged.cost == :infinity
    end

    test "merges entries and learns new pattern" do
      {pattern1, cost1} = Learner.learn_best_pattern(["PMC123"])
      {pattern2, cost2} = Learner.learn_best_pattern(["PMC456"])

      entry1 = %ProfileEntry{data: ["PMC123"], pattern: pattern1, cost: cost1}
      entry2 = %ProfileEntry{data: ["PMC456"], pattern: pattern2, cost: cost2}

      merged = Compress.merge_entries(entry1, entry2)

      assert merged.data == ["PMC123", "PMC456"]
      assert is_list(merged.pattern)
      assert is_float(merged.cost)
    end

    test "handles incompatible data with infinity cost" do
      # Create entries that might be hard to merge - strings with and without content
      entry1 = %ProfileEntry{data: ["ABC123XYZ"], pattern: [], cost: 1.0}
      entry2 = %ProfileEntry{data: [""], pattern: [], cost: 2.0}

      merged = Compress.merge_entries(entry1, entry2)

      assert merged.data == ["ABC123XYZ", ""]
      # When strings include empty string, learner returns error
      # which we convert to nil pattern with :infinity cost
      assert is_nil(merged.pattern)
      assert merged.cost == :infinity
    end

    test "respects atoms option" do
      entry1 = %ProfileEntry{data: ["123"], pattern: [], cost: 1.0}
      entry2 = %ProfileEntry{data: ["456"], pattern: [], cost: 2.0}

      # Use only digit atoms
      atoms = [Defaults.get("Digit")]
      merged = Compress.merge_entries(entry1, entry2, atoms: atoms)

      assert merged.data == ["123", "456"]
      assert is_list(merged.pattern) or is_nil(merged.pattern)
    end
  end

  describe "ProfileEntry" do
    test "creates new entry with struct" do
      entry = %ProfileEntry{data: ["test"], pattern: [], cost: 5.0}

      assert entry.data == ["test"]
      assert entry.pattern == []
      assert entry.cost == 5.0
    end

    test "creates new entry with new/3" do
      entry = ProfileEntry.new(["test"], [], 5.0)

      assert entry.data == ["test"]
      assert entry.pattern == []
      assert entry.cost == 5.0
    end

    test "supports infinity cost" do
      entry = %ProfileEntry{data: ["test"], pattern: nil, cost: :infinity}

      assert entry.cost == :infinity
    end
  end
end
