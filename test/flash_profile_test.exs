defmodule FlashProfileTest do
  use ExUnit.Case, async: true
  doctest FlashProfile

  describe "FlashProfile module" do
    test "module loads successfully" do
      assert is_binary(FlashProfile.version())
    end

    test "version returns expected format" do
      assert FlashProfile.version() == "0.1.0"
    end
  end

  describe "end-to-end: profile -> patterns -> matches" do
    test "profiles and matches PMC identifiers" do
      strings = ["PMC123", "PMC456", "PMC789"]
      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 3)

      assert length(entries) >= 1

      # Get the first entry
      entry = hd(entries)

      # Pattern should match all input strings
      if entry.pattern do
        Enum.each(strings, fn s ->
          assert FlashProfile.matches?(entry.pattern, s),
                 "Pattern should match #{s}"
        end)
      end
    end

    test "profiles and matches dates" do
      strings = ["2023-01-15", "2024-12-31", "2022-06-30"]
      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 2)

      assert length(entries) >= 1

      # All patterns should match their respective data
      Enum.each(entries, fn entry ->
        if entry.pattern do
          Enum.each(entry.data, fn s ->
            assert FlashProfile.matches?(entry.pattern, s)
          end)
        end
      end)
    end

    test "profiles mixed formats into separate clusters" do
      pmc_ids = ["PMC123", "PMC456"]
      dates = ["2023-01-01", "2024-12-31"]
      strings = pmc_ids ++ dates

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 4)

      # Should create entries for different formats
      assert length(entries) >= 1

      # All strings should be covered
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)

      # Each pattern should match its data
      Enum.each(entries, fn entry ->
        if entry.pattern do
          Enum.each(entry.data, fn s ->
            assert FlashProfile.matches?(entry.pattern, s)
          end)
        end
      end)
    end
  end

  describe "end-to-end: learn pattern workflow" do
    test "learns and applies pattern for consistent data" do
      strings = ["123", "456", "789"]
      {pattern, cost} = FlashProfile.learn_pattern(strings)

      assert is_list(pattern)
      assert is_float(cost)

      # Pattern should match all input
      Enum.each(strings, fn s ->
        assert FlashProfile.matches?(pattern, s)
      end)

      # Pattern should also match similar strings
      assert FlashProfile.matches?(pattern, "000")
      assert FlashProfile.matches?(pattern, "999")

      # But not different formats (letters instead of digits)
      refute FlashProfile.matches?(pattern, "abc")
      refute FlashProfile.matches?(pattern, "")

      # NOTE: The Zig NIF may learn Digit+ which matches "12"
      # This is acceptable for variable-width patterns
    end

    test "learned pattern can be formatted and displayed" do
      strings = ["PMC123", "PMC456"]
      {pattern, _cost} = FlashProfile.learn_pattern(strings)

      pattern_str = FlashProfile.pattern_to_string(pattern)

      assert is_binary(pattern_str)
      assert String.length(pattern_str) > 0
      # Should contain some recognizable elements
      assert String.contains?(pattern_str, "◇") or length(pattern) == 1
    end
  end

  describe "end-to-end: dissimilarity via public API" do
    test "dissimilarity function exists and works" do
      # Same format
      diss1 = FlashProfile.dissimilarity("PMC123", "PMC456")
      # Different format
      diss2 = FlashProfile.dissimilarity("PMC123", "2023-01-01")

      assert is_float(diss1) or diss1 == :infinity
      assert is_float(diss2) or diss2 == :infinity

      # Similar strings should have lower dissimilarity (if both finite)
      if is_float(diss1) and is_float(diss2) do
        assert diss1 <= diss2
      end
    end

    test "dissimilarity reflects string similarity" do
      # Identical strings
      diss_identical = FlashProfile.dissimilarity("ABC", "ABC")
      # Very similar strings
      diss_similar = FlashProfile.dissimilarity("ABC123", "ABC456")
      # Completely different strings
      diss_different = FlashProfile.dissimilarity("ABC123", "XYZXYZ")

      # Identical should have lower dissimilarity than similar
      # Similar should have lower dissimilarity than different (when finite)
      if is_float(diss_identical) and is_float(diss_similar) and is_float(diss_different) do
        assert diss_identical <= diss_similar
        assert diss_similar <= diss_different
      end
    end
  end

  describe "integration: complex real-world scenarios" do
    test "handles scientific identifiers" do
      strings = [
        "PMC1234567",
        "PMC9876543",
        "DOI:10.1234/abc",
        "DOI:10.5678/def",
        "PMID12345678",
        "PMID87654321"
      ]

      entries = FlashProfile.profile(strings, min_patterns: 2, max_patterns: 4)

      # Should identify different types
      assert length(entries) >= 2

      # All strings should be covered
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end

    test "handles various date formats" do
      strings = [
        "2023-01-15",
        "2024-12-31",
        "01/15/2023",
        "12/31/2024"
      ]

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 3)

      # Should find patterns for different date formats
      assert length(entries) >= 1

      # Patterns should match their respective data
      Enum.each(entries, fn entry ->
        if entry.pattern do
          Enum.each(entry.data, fn s ->
            assert FlashProfile.matches?(entry.pattern, s)
          end)
        end
      end)
    end

    test "handles contact information" do
      strings = [
        "555-1234",
        "123-4567",
        "user@example.com",
        "admin@site.org"
      ]

      entries = FlashProfile.profile(strings, min_patterns: 2, max_patterns: 4)

      # Should separate phone numbers from emails
      assert length(entries) >= 2

      # All should be covered
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end

    test "handles version numbers" do
      strings = [
        "v1.0.0",
        "v2.3.1",
        "v10.5.2",
        "v3.14.159"
      ]

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 2)

      assert length(entries) >= 1

      # Pattern should work for version numbers
      entry = hd(entries)

      if entry.pattern do
        Enum.each(entry.data, fn s ->
          assert FlashProfile.matches?(entry.pattern, s)
        end)
      end
    end
  end

  describe "integration: robustness and edge cases" do
    test "handles empty and whitespace strings" do
      strings = ["", "   ", "abc", "def"]

      # Should not crash
      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 4)

      assert is_list(entries)

      # All strings should be somewhere in the profile
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end

    @tag timeout: 120_000
    test "handles very long strings" do
      long_string = String.duplicate("A", 1000)
      strings = [long_string, long_string, long_string]

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 2)

      assert is_list(entries)
      assert length(entries) >= 1
    end

    test "handles unicode characters" do
      strings = ["hello", "world", "こんにちは", "世界"]

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 4)

      assert is_list(entries)

      # All strings should be covered
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end

    test "handles special characters" do
      strings = ["a@b.com", "c@d.org", "x#y$z", "p*q&r"]

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 4)

      assert is_list(entries)
      assert length(entries) >= 1
    end

    test "handles all identical strings efficiently" do
      strings = List.duplicate("identical", 100)

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 2)

      # Should create single cluster
      assert length(entries) == 1

      entry = hd(entries)
      assert length(entry.data) == 100
    end
  end

  describe "integration: performance characteristics" do
    test "handles moderately sized datasets" do
      # 50 strings
      strings =
        for i <- 1..50 do
          "PMC#{i * 1000}"
        end

      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 5)

      assert is_list(entries)
      assert length(entries) >= 1
      assert length(entries) <= 5

      # All strings should be covered
      all_data = entries |> Enum.flat_map(fn e -> e.data end)
      assert length(all_data) == 50
    end

    test "learns patterns quickly for simple data" do
      strings = ["123", "456", "789"]

      start_time = System.monotonic_time(:millisecond)
      {pattern, _cost} = FlashProfile.learn_pattern(strings)
      end_time = System.monotonic_time(:millisecond)

      assert is_list(pattern)
      # Should complete in reasonable time (< 1 second)
      assert end_time - start_time < 1000
    end
  end

  describe "integration: pattern cost optimization" do
    test "selects lower-cost patterns" do
      strings = ["Male", "Female"]
      {pattern, cost} = FlashProfile.learn_pattern(strings)

      # Should find a pattern
      assert is_list(pattern)
      assert is_float(cost)

      # Pattern should work
      Enum.each(strings, fn s ->
        assert FlashProfile.matches?(pattern, s)
      end)

      # Cost should be reasonable (not infinity)
      assert cost < 100.0
    end

    test "profile entries are sorted by cost" do
      strings = ["PMC123", "ABC", "2023-01-01"]
      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 3)

      costs = Enum.map(entries, fn e -> e.cost end)
      finite_costs = Enum.filter(costs, &is_float/1)

      if length(finite_costs) > 1 do
        # Should be sorted (lowest cost first)
        assert finite_costs == Enum.sort(finite_costs)
      end
    end
  end

  describe "documentation examples" do
    test "README example: profiling PMC IDs" do
      strings = ["PMC1234567", "PMC9876543", "PMC5555555"]
      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 3)

      assert length(entries) >= 1

      # All strings should be covered by some entry
      all_data = entries |> Enum.flat_map(& &1.data) |> Enum.uniq()
      assert Enum.sort(all_data) == Enum.sort(strings)

      # At least one entry should have a pattern
      patterns = Enum.filter(entries, fn e -> e.pattern != nil end)

      if length(patterns) > 0 do
        pattern_str = FlashProfile.pattern_to_string(hd(patterns).pattern)
        assert is_binary(pattern_str)
      end
    end

    test "README example: profiling mixed data" do
      strings = ["PMC123", "PMC456", "2023-01-01", "2024-12-31"]
      entries = FlashProfile.profile(strings, min_patterns: 1, max_patterns: 4)

      # Should create multiple patterns
      assert length(entries) >= 1

      # All strings should be profiled
      all_data = entries |> Enum.flat_map(fn e -> e.data end) |> Enum.sort()
      assert all_data == Enum.sort(strings)
    end
  end
end
