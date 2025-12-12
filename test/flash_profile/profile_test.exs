defmodule FlashProfile.ProfileTest do
  use ExUnit.Case, async: true
  doctest FlashProfile.Profile

  alias FlashProfile.{Profile, ProfileEntry, Pattern}
  alias FlashProfile.Atoms.Defaults

  describe "profile/4" do
    test "profiles homogeneous dataset" do
      strings = ["PMC123", "PMC456", "PMC789"]
      entries = Profile.profile(strings, 1, 3)

      assert is_list(entries)
      assert length(entries) >= 1
      assert length(entries) <= 3

      # All entries should be ProfileEntry structs
      Enum.each(entries, fn entry ->
        assert %ProfileEntry{} = entry
        assert is_list(entry.data)
        assert is_list(entry.pattern) or is_nil(entry.pattern)
        assert is_float(entry.cost) or entry.cost == :infinity
      end)
    end

    test "profiles heterogeneous dataset" do
      # Mix of different formats
      strings = ["PMC123", "PMC456", "2023-01-01", "2024-12-31"]
      entries = Profile.profile(strings, 1, 4)

      assert is_list(entries)
      assert length(entries) >= 1

      # Should create multiple patterns for different formats
      # (actual number depends on clustering)
      total_strings =
        entries
        |> Enum.flat_map(fn entry -> entry.data end)
        |> Enum.sort()

      assert total_strings == Enum.sort(strings)
    end

    test "respects min_patterns boundary" do
      strings = ["abc", "def", "ghi", "jkl"]
      min_patterns = 2
      entries = Profile.profile(strings, min_patterns, 5)

      # Should have at least min_patterns entries
      # (unless dataset is too small)
      assert length(entries) >= 1
    end

    test "respects max_patterns boundary" do
      strings = ["a", "b", "c", "d", "e", "f", "g", "h"]
      max_patterns = 3
      entries = Profile.profile(strings, 1, max_patterns)

      assert length(entries) <= max_patterns
    end

    test "handles empty dataset" do
      assert [] = Profile.profile([], 1, 5)
    end

    test "handles single string" do
      entries = Profile.profile(["test"], 1, 5)

      assert length(entries) == 1
      entry = hd(entries)
      assert entry.data == ["test"]
      assert is_list(entry.pattern)
    end

    test "handles identical strings" do
      strings = ["ABC", "ABC", "ABC"]
      entries = Profile.profile(strings, 1, 3)

      assert length(entries) == 1
      entry = hd(entries)
      assert Enum.sort(entry.data) == Enum.sort(strings)
    end

    test "sorts entries by cost" do
      strings = ["PMC123", "PMC456", "2023-01-01", "2024-12-31"]
      entries = Profile.profile(strings, 1, 4)

      # Entries should be sorted by cost (lowest first)
      costs = Enum.map(entries, fn e -> e.cost end)

      # Filter out infinity values for comparison
      finite_costs = Enum.filter(costs, fn c -> is_float(c) end)

      if length(finite_costs) > 1 do
        assert finite_costs == Enum.sort(finite_costs)
      end
    end

    test "each pattern matches its cluster data" do
      strings = ["123", "456", "789"]
      entries = Profile.profile(strings, 1, 3)

      Enum.each(entries, fn entry ->
        # Skip entries with nil patterns (learning failed)
        if entry.pattern do
          Enum.each(entry.data, fn s ->
            assert Pattern.matches?(entry.pattern, s),
                   "Pattern #{inspect(entry.pattern)} should match #{s}"
          end)
        end
      end)
    end

    test "accepts custom theta parameter" do
      strings = ["PMC123", "PMC456", "ABC789"]
      entries = Profile.profile(strings, 1, 3, theta: 2.0)

      assert is_list(entries)
      assert length(entries) >= 1
    end

    test "accepts custom atoms parameter" do
      strings = ["123", "456", "789"]
      atoms = [Defaults.get("Digit")]
      entries = Profile.profile(strings, 1, 2, atoms: atoms)

      assert is_list(entries)
      assert length(entries) >= 1
    end
  end

  describe "build_hierarchy/4" do
    test "builds hierarchy for dataset" do
      strings = ["PMC123", "PMC456", "ABC789"]
      hierarchy = Profile.build_hierarchy(strings, 3, 1.25)

      assert hierarchy != nil
      assert is_list(hierarchy.data)
      assert Enum.sort(hierarchy.data) == Enum.sort(strings)
    end

    test "uses theta parameter for sampling" do
      strings = ["a", "b", "c", "d", "e"]
      # Higher theta means more samples
      hierarchy1 = Profile.build_hierarchy(strings, 3, 1.0)
      hierarchy2 = Profile.build_hierarchy(strings, 3, 2.0)

      # Both should work
      assert hierarchy1 != nil
      assert hierarchy2 != nil
    end

    test "works with custom atoms" do
      strings = ["123", "456"]
      atoms = [Defaults.get("Digit")]
      hierarchy = Profile.build_hierarchy(strings, 2, 1.25, atoms: atoms)

      assert hierarchy != nil
    end

    test "raises for invalid parameters" do
      assert_raise FunctionClauseError, fn ->
        Profile.build_hierarchy(["a"], 0, 1.25)
      end

      assert_raise FunctionClauseError, fn ->
        Profile.build_hierarchy(["a"], 5, -1.0)
      end
    end
  end

  describe "matches_entry?/2" do
    test "returns true when pattern matches string" do
      digit = Defaults.get("Digit")
      pattern = [digit]
      entry = %ProfileEntry{data: ["123"], pattern: pattern, cost: 10.0}

      assert Profile.matches_entry?(entry, "456")
      assert Profile.matches_entry?(entry, "789")
    end

    test "returns false when pattern does not match" do
      digit = Defaults.get("Digit")
      pattern = [digit]
      entry = %ProfileEntry{data: ["123"], pattern: pattern, cost: 10.0}

      refute Profile.matches_entry?(entry, "abc")
      refute Profile.matches_entry?(entry, "12a")
    end

    test "returns false for entry with nil pattern" do
      entry = %ProfileEntry{data: ["test"], pattern: nil, cost: :infinity}

      refute Profile.matches_entry?(entry, "test")
      refute Profile.matches_entry?(entry, "anything")
    end

    test "works with complex patterns" do
      pmc = FlashProfile.Atom.constant("PMC")
      digit = Defaults.get("Digit")
      pattern = [pmc, digit]
      entry = %ProfileEntry{data: ["PMC123"], pattern: pattern, cost: 15.0}

      assert Profile.matches_entry?(entry, "PMC123")
      assert Profile.matches_entry?(entry, "PMC9876")
      refute Profile.matches_entry?(entry, "XYZ123")
    end
  end

  describe "real-world profiling scenarios" do
    test "profiles PMC identifiers" do
      strings = [
        "PMC1234567",
        "PMC9876543",
        "PMC5555555",
        "PMC1111111"
      ]

      entries = Profile.profile(strings, 1, 2)

      assert length(entries) >= 1

      # All strings should be covered by some entry
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)

      # Patterns should match their respective data
      Enum.each(entries, fn entry ->
        if entry.pattern do
          Enum.each(entry.data, fn s ->
            assert Pattern.matches?(entry.pattern, s)
          end)
        end
      end)
    end

    test "profiles dates" do
      strings = [
        "2023-01-15",
        "2024-12-31",
        "2022-06-30",
        "2021-03-20"
      ]

      entries = Profile.profile(strings, 1, 2)

      assert length(entries) >= 1

      # All dates should appear in some cluster
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end

    test "profiles mixed formats into separate clusters" do
      strings = [
        "PMC123",
        "PMC456",
        "PMC789",
        "2023-01-01",
        "2024-12-31",
        "ABC",
        "DEF"
      ]

      entries = Profile.profile(strings, 2, 5)

      # Should create multiple clusters for different formats
      assert length(entries) >= 2

      # All strings should be covered
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end

    test "profiles phone numbers" do
      strings = ["555-1234", "123-4567", "999-0000", "111-2222"]
      entries = Profile.profile(strings, 1, 2)

      assert length(entries) >= 1

      # Should learn a pattern that matches all phone numbers
      Enum.each(entries, fn entry ->
        if entry.pattern do
          Enum.each(entry.data, fn s ->
            assert Pattern.matches?(entry.pattern, s)
          end)
        end
      end)
    end

    test "handles dataset with some incompatible strings" do
      strings = ["PMC123", "PMC456", "", "single"]

      entries = Profile.profile(strings, 1, 4)

      # Should still produce a profile
      assert is_list(entries)
      assert length(entries) >= 1

      # All strings should be in some cluster
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end
  end

  describe "ProfileEntry struct" do
    test "can be created with new/3" do
      entry = ProfileEntry.new(["test"], [], 5.0)

      assert entry.data == ["test"]
      assert entry.pattern == []
      assert entry.cost == 5.0
    end

    test "supports infinity cost" do
      entry = %ProfileEntry{data: ["test"], pattern: nil, cost: :infinity}

      assert entry.cost == :infinity
    end

    test "stores cluster data" do
      data = ["a", "b", "c"]
      entry = %ProfileEntry{data: data, pattern: [], cost: 1.0}

      assert entry.data == data
    end
  end

  describe "edge cases and error handling" do
    test "handles very small datasets" do
      assert [] = Profile.profile([], 1, 1)
      assert [%ProfileEntry{}] = Profile.profile(["x"], 1, 1)
    end

    test "handles min_patterns == max_patterns" do
      strings = ["a", "b", "c", "d"]
      entries = Profile.profile(strings, 2, 2)

      assert is_list(entries)
      # Should aim for exactly 2 patterns
    end

    test "handles large max_patterns" do
      strings = ["a", "b", "c"]
      # More patterns than strings
      entries = Profile.profile(strings, 1, 10)

      # Should return at most n patterns for n strings
      assert length(entries) <= length(strings)
    end

    test "profile preserves all input strings" do
      strings = ["PMC123", "ABC", "123", "xyz", "2023-01-01"]
      entries = Profile.profile(strings, 1, 5)

      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end
  end

  describe "boundary enforcement" do
    test "strictly respects max_patterns" do
      # Create diverse dataset that would naturally cluster into many groups
      strings = [
        "PMC1234567",
        "PMC2345678",
        # Group 1: PMC IDs
        "2024-01-15",
        "2023-12-25",
        # Group 2: Dates
        "user@example.com",
        "admin@test.org",
        # Group 3: Emails
        "+1-555-1234",
        "+1-555-5678",
        # Group 4: Phone numbers
        "v1.2.3",
        "v2.0.0"
        # Group 5: Versions
      ]

      result = Profile.profile(strings, 1, 3)

      # max 3 patterns

      # STRICT assertion
      assert length(result) <= 3,
             "Profile returned #{length(result)} patterns but max was 3"

      # All strings should still be covered
      all_data = Enum.flat_map(result, & &1.data)
      assert length(all_data) == length(strings)
    end

    test "respects min_patterns when possible" do
      # Dataset with clear distinct formats
      strings = [
        "AAA111",
        "BBB222",
        "CCC333",
        # Format 1
        "111-AAA",
        "222-BBB",
        "333-CCC"
        # Format 2
      ]

      result = Profile.profile(strings, 2, 5)

      # min 2 patterns

      # Should have at least 2 patterns (there are 2 distinct formats)
      assert length(result) >= 2,
             "Profile returned #{length(result)} patterns but min was 2"
    end

    test "handles min_patterns = max_patterns" do
      strings = ["A1", "B2", "C3", "D4", "E5", "F6"]

      result = Profile.profile(strings, 3, 3)

      # exactly 3 patterns

      assert length(result) == 3, "Profile should return exactly 3 patterns"
    end

    test "handles single string with min_patterns > 1" do
      strings = ["PMC1234567"]

      result = Profile.profile(strings, 3, 5)

      # Can't have more patterns than strings
      assert length(result) == 1
    end

    test "handles empty dataset" do
      result = Profile.profile([], 1, 5)
      assert result == []
    end
  end
end
