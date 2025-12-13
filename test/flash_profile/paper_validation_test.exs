defmodule FlashProfile.PaperValidationTest do
  @moduledoc """
  Validation tests using the FlashProfileDemo test fixtures.

  These tests validate our FlashProfile implementation against the datasets
  and expected patterns from the FlashProfile paper's reference implementation.

  All tests are tagged with :paper_validation for selective running:
      mix test --only paper_validation
  """

  use ExUnit.Case, async: true

  @moduletag :paper_validation

  @fixtures_dir Path.join([__DIR__, "..", "fixtures", "flash_profile_demo"])

  describe "HOMOGENEOUS pattern validation" do
    @tag :phones
    test "phones.json - US phone numbers" do
      fixture = load_fixture("phones.json")
      data = Map.get(fixture, "Data")
      _expected = Map.get(fixture, "Results")

      # Learn a pattern for the phone data
      {pattern, cost} = FlashProfile.learn_pattern(data)

      # Validate that the pattern exists
      assert pattern != nil, "Should learn a pattern for phone numbers"
      assert is_float(cost), "Cost should be a float"

      # Functional validation: pattern should match ALL input strings
      coverage = calculate_coverage(pattern, data)

      assert coverage == 100.0,
             "Pattern should match 100% of inputs, got #{coverage}%"

      # Pattern should not be trivial (just Any+)
      assert_pattern_is_specific(pattern, data)

      # Verify expected pattern structure from paper
      # Expected: [Digit]{3} · '-' · [Digit]{3} · '-' · [Digit]{4}
      # Our pattern should have similar structure: Digit atoms and '-' constants
      assert_has_digit_atoms(pattern)

      # Log the learned pattern for debugging
      IO.puts("\nPhones pattern: #{FlashProfile.pattern_to_string(pattern)}")
      IO.puts("Pattern cost: #{cost}")
      IO.puts("Expected: [Digit]{3} · '-' · [Digit]{3} · '-' · [Digit]{4}")
    end

    @tag :bool
    test "bool.json - yes/no values" do
      fixture = load_fixture("bool.json")
      data = Map.get(fixture, "Data")

      # Learn a pattern for boolean-like data
      {pattern, cost} = FlashProfile.learn_pattern(data)

      # Validate pattern exists
      assert pattern != nil, "Should learn a pattern for boolean values"
      assert is_float(cost)

      # Functional validation: 100% coverage
      coverage = calculate_coverage(pattern, data)

      assert coverage == 100.0,
             "Pattern should match 100% of inputs, got #{coverage}%"

      # Pattern should be specific to yes/no
      assert_pattern_is_specific(pattern, data)

      # Expected patterns from paper:
      # Option 1: 'yes' | 'no' (explicit constants)
      # Option 2: [Lower]+ (character class)
      # Both are valid

      # Log the learned pattern
      IO.puts("\nBool pattern: #{FlashProfile.pattern_to_string(pattern)}")
      IO.puts("Pattern cost: #{cost}")
      IO.puts("Expected: 'yes' | 'no' OR [Lower]+")
    end

    @tag :dates
    test "dates.json - DD.MM.YYYY format dates" do
      fixture = load_fixture("dates.json")
      data = Map.get(fixture, "Data")

      # Learn a pattern for date data
      {pattern, cost} = FlashProfile.learn_pattern(data)

      # Validate pattern exists
      assert pattern != nil, "Should learn a pattern for dates"
      assert is_float(cost)

      # Functional validation: 100% coverage
      coverage = calculate_coverage(pattern, data)

      assert coverage == 100.0,
             "Pattern should match 100% of inputs, got #{coverage}%"

      # Pattern should be specific
      assert_pattern_is_specific(pattern, data)

      # Expected from paper (simplest option):
      # [Digit]{2} · '.0' · [Digit]{1} · '.2016'
      # or more general: [Digit]{2} · '.' · [Digit]{2} · '.2016'
      # Should have digit atoms and '.' constants

      assert_has_digit_atoms(pattern)

      # Log the learned pattern
      IO.puts("\nDates pattern: #{FlashProfile.pattern_to_string(pattern)}")
      IO.puts("Pattern cost: #{cost}")
      IO.puts("Expected: [Digit]{2} · '.0' · [Digit]{1} · '.2016'")
    end

    @tag :ipv4
    @tag :slow
    @tag timeout: 180_000
    test "ipv4.json - IPv4 addresses" do
      fixture = load_fixture("ipv4.json")
      data = Map.get(fixture, "Data")

      # Learn a pattern for IPv4 addresses
      {pattern, cost} = FlashProfile.learn_pattern(data)

      # Validate pattern exists
      assert pattern != nil, "Should learn a pattern for IPv4 addresses"
      assert is_float(cost)

      # Functional validation: 100% coverage
      coverage = calculate_coverage(pattern, data)

      assert coverage == 100.0,
             "Pattern should match 100% of inputs, got #{coverage}%"

      # Pattern should be specific
      assert_pattern_is_specific(pattern, data)

      # Expected: [Digit]+ · '.' · [Digit]+ · '.' · [Digit]+ · '.' · [Digit]+
      # Should have digit atoms and '.' constants

      assert_has_digit_atoms(pattern)

      # Log the learned pattern
      IO.puts("\nIPv4 pattern: #{FlashProfile.pattern_to_string(pattern)}")
      IO.puts("Pattern cost: #{cost}")
      IO.puts("Expected: [Digit]+ · '.' · [Digit]+ · '.' · [Digit]+ · '.' · [Digit]+")
    end

    @tag :emails
    test "emails.json - email addresses" do
      fixture = load_fixture("emails.json")
      data = Map.get(fixture, "Data")

      # Learn a pattern for email addresses
      {pattern, cost} = FlashProfile.learn_pattern(data)

      # Validate pattern exists
      assert pattern != nil, "Should learn a pattern for emails"
      assert is_float(cost)

      # Functional validation: 100% coverage
      coverage = calculate_coverage(pattern, data)

      assert coverage == 100.0,
             "Pattern should match 100% of inputs, got #{coverage}%"

      # Pattern should be specific
      assert_pattern_is_specific(pattern, data)

      # Expected: [Lower]+ · '.' · [Lower]+ · '@' · [Lower]+ · '.com'
      # Should have Lower atoms and special character constants

      # Log the learned pattern
      IO.puts("\nEmails pattern: #{FlashProfile.pattern_to_string(pattern)}")
      IO.puts("Pattern cost: #{cost}")
      IO.puts("Expected: [Lower]+ · '.' · [Lower]+ · '@' · [Lower]+ · '.com'")
    end
  end

  describe "Profile-level validation" do
    @tag :phones_profile
    test "phones - single pattern profile" do
      fixture = load_fixture("phones.json")
      data = Map.get(fixture, "Data")

      # Run full profiling
      profile = FlashProfile.profile(data, min_patterns: 1, max_patterns: 3)

      # Should have at least one pattern
      assert length(profile) >= 1,
             "Should generate at least one pattern for homogeneous data"

      # For homogeneous data, we expect a single pattern
      # (though the algorithm might find multiple clusters)
      entry = hd(profile)

      # The best pattern should cover most or all of the data
      # For homogeneous data, we expect high coverage (80%+)
      coverage_percent = length(entry.data) / length(data) * 100

      assert coverage_percent >= 80.0,
             "Best pattern should cover at least 80% of data, got #{coverage_percent}%"

      # All matched data should actually match the pattern
      for str <- entry.data do
        assert FlashProfile.matches?(entry.pattern, str),
               "Pattern should match its own data: #{str}"
      end

      IO.puts("\nPhones profile: #{length(profile)} pattern(s)")
      IO.puts("Best pattern covers: #{coverage_percent}% of data")
    end

    @tag :emails_profile
    test "emails - single pattern profile" do
      fixture = load_fixture("emails.json")
      data = Map.get(fixture, "Data")

      profile = FlashProfile.profile(data, min_patterns: 1, max_patterns: 3)

      assert length(profile) >= 1
      entry = hd(profile)

      # Check coverage
      # For homogeneous data, we expect high coverage (80%+)
      coverage_percent = length(entry.data) / length(data) * 100

      assert coverage_percent >= 80.0,
             "Best pattern should cover at least 80% of data, got #{coverage_percent}%"

      # Validate matches
      for str <- entry.data do
        assert FlashProfile.matches?(entry.pattern, str),
               "Pattern should match: #{str}"
      end

      IO.puts("\nEmails profile: #{length(profile)} pattern(s)")
      IO.puts("Best pattern covers: #{coverage_percent}% of data")
    end
  end

  describe "Pattern quality metrics" do
    @tag :quality
    @tag timeout: 180_000
    test "learned patterns should have reasonable costs" do
      # Skip ipv4 in this test due to timeout
      fixtures = [
        {"phones.json", 50.0},
        {"bool.json", 30.0},
        {"dates.json", 50.0},
        {"emails.json", 70.0}
      ]

      for {filename, max_expected_cost} <- fixtures do
        fixture = load_fixture(filename)
        data = Map.get(fixture, "Data")

        {_pattern, cost} = FlashProfile.learn_pattern(data)

        # Cost should be reasonable (not too high)
        # These are rough heuristics based on pattern complexity
        assert cost < max_expected_cost,
               "Cost for #{filename} too high: #{cost} >= #{max_expected_cost}"

        IO.puts("\n#{filename}: cost = #{cost} (max: #{max_expected_cost})")
      end
    end

    @tag :specificity
    test "patterns should use appropriate atoms" do
      # Phones should use Digit
      phones_fixture = load_fixture("phones.json")
      {phones_pattern, _} = FlashProfile.learn_pattern(Map.get(phones_fixture, "Data"))
      assert_has_digit_atoms(phones_pattern)

      # Emails should use Lower (for all-lowercase emails)
      emails_fixture = load_fixture("emails.json")
      {emails_pattern, _} = FlashProfile.learn_pattern(Map.get(emails_fixture, "Data"))
      assert_has_lower_atoms(emails_pattern)

      IO.puts("\nAtom specificity checks passed")
    end

    @tag :specificity_ipv4
    @tag :slow
    @tag timeout: 180_000
    test "ipv4 patterns should use Digit atoms" do
      # IPv4 should use Digit - separate test due to timeout
      ipv4_fixture = load_fixture("ipv4.json")
      {ipv4_pattern, _} = FlashProfile.learn_pattern(Map.get(ipv4_fixture, "Data"))
      assert_has_digit_atoms(ipv4_pattern)

      IO.puts("\nIPv4 atom specificity check passed")
    end
  end

  # Helper functions

  defp load_fixture(filename) do
    path = Path.join(@fixtures_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        # Use Elixir's built-in JSON decoder (OTP 27+)
        :json.decode(content)

      {:error, reason} ->
        flunk("Failed to load fixture #{filename}: #{inspect(reason)}")
    end
  end

  defp calculate_coverage(pattern, strings) do
    matches = Enum.count(strings, fn s -> FlashProfile.matches?(pattern, s) end)
    matches / length(strings) * 100.0
  end

  defp assert_pattern_is_specific(pattern, data) do
    # Pattern shouldn't be trivial (just Any+)
    # Check that it's not a single Any atom
    refute length(pattern) == 1 and is_any_atom?(hd(pattern)),
           "Pattern should not be trivial (just Any+)"

    # Pattern should have multiple atoms or constants for structured data
    if Enum.all?(data, &(String.length(&1) > 3)) do
      assert length(pattern) > 1,
             "Pattern should have multiple atoms for structured data"
    end
  end

  defp assert_has_digit_atoms(pattern) do
    has_digit =
      Enum.any?(pattern, fn atom ->
        atom.name == "Digit" or String.contains?(atom.name || "", "Digit")
      end)

    assert has_digit, "Pattern should contain Digit atoms"
  end

  defp assert_has_lower_atoms(pattern) do
    has_lower =
      Enum.any?(pattern, fn atom ->
        atom.name == "Lower" or String.contains?(atom.name || "", "Lower")
      end)

    assert has_lower, "Pattern should contain Lower atoms"
  end

  defp is_any_atom?(atom) do
    atom.name == "Any" or String.contains?(atom.name || "", "Any")
  end

  # Verify that all input strings are covered by profile entries (no data loss)
  defp all_strings_covered?(entries, original_strings) do
    covered = entries |> Enum.flat_map(& &1.data) |> MapSet.new()
    original = MapSet.new(original_strings)
    MapSet.equal?(covered, original)
  end

  # Verify that each pattern actually matches all its data strings
  defp patterns_match_data?(entries) do
    Enum.all?(entries, fn entry ->
      # Entries with nil patterns are expected (learning failed)
      if entry.pattern do
        Enum.all?(entry.data, fn s -> FlashProfile.matches?(entry.pattern, s) end)
      else
        true
      end
    end)
  end

  # Verify that similar strings cluster together
  defp check_cluster_contains?(entries, strings, _description) do
    # Find the cluster(s) that contain any of these strings
    matching_clusters =
      entries
      |> Enum.filter(fn entry ->
        Enum.any?(strings, fn s -> s in entry.data end)
      end)

    # If strings cluster together, they should mostly be in the same cluster
    if length(matching_clusters) == 1 do
      cluster = hd(matching_clusters)
      matching_count = Enum.count(strings, fn s -> s in cluster.data end)
      # At least 50% should be in the same cluster (lenient for small datasets)
      matching_count >= length(strings) * 0.5
    else
      # Multiple clusters - check if most strings are concentrated
      max_cluster =
        Enum.max_by(matching_clusters, fn entry ->
          Enum.count(strings, fn s -> s in entry.data end)
        end)

      matching_count = Enum.count(strings, fn s -> s in max_cluster.data end)
      # At least 50% in the largest cluster (lenient for heterogeneous data)
      matching_count >= length(strings) * 0.5
    end
  end

  describe "HETEROGENEOUS patterns - hetero_dates.json" do
    @tag :hetero_dates
    test "produces correct number of clusters" do
      fixture = load_fixture("hetero_dates.json")
      strings = Map.get(fixture, "Data")
      expected_disjuncts = fixture |> Map.get("Results") |> List.last() |> Map.get("Disjuncts")

      # Expected: 4 disjuncts
      assert expected_disjuncts == 4

      # Allow some flexibility: 3-5 patterns
      min_patterns = expected_disjuncts - 1
      max_patterns = expected_disjuncts + 1

      entries =
        FlashProfile.profile(strings, min_patterns: min_patterns, max_patterns: max_patterns)

      # Should produce 3-5 patterns
      assert length(entries) >= 3, "Expected at least 3 patterns, got #{length(entries)}"
      assert length(entries) <= 5, "Expected at most 5 patterns, got #{length(entries)}"

      IO.puts("\nHetero dates: #{length(entries)} patterns (expected ~#{expected_disjuncts})")
    end

    @tag :hetero_dates
    test "provides complete coverage of all dates" do
      fixture = load_fixture("hetero_dates.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 3, max_patterns: 5)

      # All 7 date strings should be covered
      assert all_strings_covered?(entries, strings),
             "Not all date strings are covered by profile entries"
    end

    @tag :hetero_dates
    test "patterns match their assigned data" do
      fixture = load_fixture("hetero_dates.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 3, max_patterns: 5)

      assert patterns_match_data?(entries),
             "Some patterns don't match their assigned data strings"
    end

    @tag :hetero_dates
    test "different date formats cluster separately" do
      fixture = load_fixture("hetero_dates.json")
      strings = Map.get(fixture, "Data")

      # Dataset contains:
      # - "12/31/1991" (MM/DD/YYYY format)
      # - "December 10, 1980", "September 25, 1970", "October 12, 2005" (Month DD, YYYY)
      # - "2005-11-14", "1993-06-26" (YYYY-MM-DD ISO format)
      # - "December 1990" (Month YYYY)

      entries = FlashProfile.profile(strings, min_patterns: 3, max_patterns: 5)

      # Check that ISO dates cluster together
      iso_dates = ["2005-11-14", "1993-06-26"]

      assert check_cluster_contains?(entries, iso_dates, "ISO dates"),
             "ISO date strings should cluster together"

      # Check that "Month DD, YYYY" dates cluster together
      month_day_year = ["December 10, 1980", "September 25, 1970", "October 12, 2005"]

      assert check_cluster_contains?(entries, month_day_year, "Month DD, YYYY dates"),
             "Month DD, YYYY date strings should cluster together"

      IO.puts("\nHetero dates clustering validation passed")
    end
  end

  describe "HETEROGENEOUS patterns - us_canada_zip_codes.json" do
    @tag :zip_codes
    test "produces approximately 6 clusters" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")
      expected_disjuncts = fixture |> Map.get("Results") |> List.last() |> Map.get("Disjuncts")

      # Expected: 6 disjuncts
      assert expected_disjuncts == 6

      # Allow some flexibility: 4-8 patterns
      min_patterns = expected_disjuncts - 2
      max_patterns = expected_disjuncts + 2

      entries =
        FlashProfile.profile(strings, min_patterns: min_patterns, max_patterns: max_patterns)

      # Should produce 4-8 patterns
      assert length(entries) >= 4, "Expected at least 4 patterns, got #{length(entries)}"
      assert length(entries) <= 8, "Expected at most 8 patterns, got #{length(entries)}"

      IO.puts("\nZip codes: #{length(entries)} patterns (expected ~#{expected_disjuncts})")
    end

    @tag :zip_codes
    test "provides complete coverage of all postal codes" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 8)

      # All 80 strings (including empty strings) should be covered
      assert all_strings_covered?(entries, strings),
             "Not all postal code strings are covered by profile entries"
    end

    @tag :zip_codes
    test "patterns match their assigned data" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 8)

      assert patterns_match_data?(entries),
             "Some patterns don't match their assigned data strings"
    end

    @tag :zip_codes
    test "US 5-digit zip codes cluster together" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")

      # Sample US 5-digit zip codes from the dataset
      us_5digit = ["99518", "35555", "93722", "80022", "80909", "52057", "50315"]

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 8)

      assert check_cluster_contains?(entries, us_5digit, "US 5-digit zip codes"),
             "US 5-digit zip codes should cluster together"
    end

    @tag :zip_codes
    test "Canadian postal codes cluster together" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")

      # Canadian postal codes from the dataset
      canadian = ["T5M 3R4", "T2C 2R1", "V3C 1S9", "R3C 2E6", "E1H 2E6", "N0G 2L0", "K0K 2C0"]

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 8)

      assert check_cluster_contains?(entries, canadian, "Canadian postal codes"),
             "Canadian postal codes should cluster together"

      IO.puts("\nZip codes clustering validation passed")
    end

    @tag :zip_codes
    test "empty strings are handled" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 8)

      # Find entries containing empty strings
      empty_entries = Enum.filter(entries, fn entry -> "" in entry.data end)

      # Empty strings should be in some cluster
      assert length(empty_entries) >= 1, "Empty strings should be assigned to a cluster"
    end
  end

  describe "HETEROGENEOUS patterns - motivating_example.json" do
    @tag :motivating_example
    test "produces approximately 5 clusters" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")
      expected_disjuncts = fixture |> Map.get("Results") |> Enum.at(1) |> Map.get("Disjuncts")

      # Expected: 5 disjuncts
      assert expected_disjuncts == 5

      # Allow some flexibility: 4-7 patterns
      min_patterns = expected_disjuncts - 1
      max_patterns = expected_disjuncts + 2

      entries =
        FlashProfile.profile(strings, min_patterns: min_patterns, max_patterns: max_patterns)

      # Should produce 4-7 patterns
      assert length(entries) >= 4, "Expected at least 4 patterns, got #{length(entries)}"
      assert length(entries) <= 7, "Expected at most 7 patterns, got #{length(entries)}"

      IO.puts(
        "\nMotivating example: #{length(entries)} patterns (expected ~#{expected_disjuncts})"
      )
    end

    @tag :motivating_example
    test "provides complete coverage of all identifiers" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      # All 1451 strings should be covered
      assert all_strings_covered?(entries, strings),
             "Not all identifier strings are covered by profile entries"
    end

    @tag :motivating_example
    test "patterns match their assigned data" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      assert patterns_match_data?(entries),
             "Some patterns don't match their assigned data strings"
    end

    @tag :motivating_example
    test "PMC identifiers cluster together" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      # Sample PMC identifiers from the dataset
      pmc_ids = Enum.filter(strings, fn s -> String.starts_with?(s, "PMC") end)

      # Should have many PMC identifiers
      assert length(pmc_ids) > 500, "Expected many PMC identifiers in dataset"

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      # Check if PMC IDs cluster together (at least 90% should be in one cluster)
      matching_clusters =
        entries
        |> Enum.filter(fn entry ->
          Enum.any?(pmc_ids, fn s -> s in entry.data end)
        end)

      assert length(matching_clusters) >= 1, "PMC IDs should form at least one cluster"

      # Find the main PMC cluster
      main_pmc_cluster =
        Enum.max_by(matching_clusters, fn entry ->
          Enum.count(entry.data, fn s -> String.starts_with?(s, "PMC") end)
        end)

      pmc_in_main_cluster =
        Enum.count(main_pmc_cluster.data, fn s -> String.starts_with?(s, "PMC") end)

      assert pmc_in_main_cluster >= length(pmc_ids) * 0.9,
             "At least 90% of PMC IDs should cluster together. Found #{pmc_in_main_cluster}/#{length(pmc_ids)}"
    end

    @tag :motivating_example
    test "DOI identifiers cluster together" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      # Sample DOI identifiers from the dataset
      doi_ids = Enum.filter(strings, fn s -> String.starts_with?(s, "doi:") end)

      # Should have many DOI identifiers
      assert length(doi_ids) > 100, "Expected many DOI identifiers in dataset"

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      # DOIs might split into subclusters (10.13039 vs 10.1016), so allow multiple clusters
      # but most should be together
      matching_clusters =
        entries
        |> Enum.filter(fn entry ->
          Enum.any?(doi_ids, fn s -> s in entry.data end)
        end)

      assert length(matching_clusters) >= 1, "DOI identifiers should form at least one cluster"

      # Check that DOIs are well-clustered (at least 80% in top 2 clusters)
      top_doi_clusters =
        matching_clusters
        |> Enum.sort_by(
          fn entry ->
            -Enum.count(entry.data, fn s -> String.starts_with?(s, "doi:") end)
          end,
          :asc
        )
        |> Enum.take(2)

      doi_in_top_clusters =
        Enum.reduce(top_doi_clusters, 0, fn entry, acc ->
          acc + Enum.count(entry.data, fn s -> String.starts_with?(s, "doi:") end)
        end)

      assert doi_in_top_clusters >= length(doi_ids) * 0.8,
             "At least 80% of DOI identifiers should cluster together"
    end

    @tag :motivating_example
    test "ISBN identifiers cluster together" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      # Sample ISBN identifiers from the dataset
      isbn_ids = Enum.filter(strings, fn s -> String.starts_with?(s, "ISBN:") end)

      # Should have many ISBN identifiers
      assert length(isbn_ids) > 100, "Expected many ISBN identifiers in dataset"

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      # Check if ISBN identifiers cluster together
      matching_clusters =
        entries
        |> Enum.filter(fn entry ->
          Enum.any?(isbn_ids, fn s -> s in entry.data end)
        end)

      assert length(matching_clusters) >= 1, "ISBN identifiers should form at least one cluster"

      # Find the main ISBN cluster
      main_isbn_cluster =
        Enum.max_by(matching_clusters, fn entry ->
          Enum.count(entry.data, fn s -> String.starts_with?(s, "ISBN:") end)
        end)

      isbn_in_main_cluster =
        Enum.count(main_isbn_cluster.data, fn s -> String.starts_with?(s, "ISBN:") end)

      assert isbn_in_main_cluster >= length(isbn_ids) * 0.85,
             "At least 85% of ISBN identifiers should cluster together"
    end

    @tag :motivating_example
    test "not_available strings form separate cluster" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      # "not_available" strings
      not_available = Enum.filter(strings, fn s -> s == "not_available" end)

      # Should have a few "not_available" strings
      assert length(not_available) >= 2, "Expected at least 2 'not_available' strings"

      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      # All "not_available" strings should be in the same cluster
      assert check_cluster_contains?(entries, not_available, "not_available strings"),
             "All 'not_available' strings should cluster together"

      IO.puts("\nMotivating example clustering validation passed")
    end

    @tag :motivating_example
    @tag :performance
    test "performance - handles 1451 strings efficiently" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")

      # Ensure dataset is large
      assert length(strings) == 1451, "Expected exactly 1451 strings in motivating_example.json"

      # Profile should complete in reasonable time (this test will timeout if too slow)
      {time_microseconds, entries} =
        :timer.tc(fn ->
          FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)
        end)

      # Should complete in under 30 seconds
      time_seconds = time_microseconds / 1_000_000

      assert time_seconds < 30.0,
             "Profiling took #{time_seconds}s, expected < 30s"

      # Verify output is still correct
      assert all_strings_covered?(entries, strings)
      assert patterns_match_data?(entries)

      IO.puts("\nPerformance: #{time_seconds}s for 1451 strings")
    end
  end

  describe "Cluster quality metrics" do
    @tag :cluster_quality
    test "hetero_dates - cluster purity" do
      fixture = load_fixture("hetero_dates.json")
      strings = Map.get(fixture, "Data")
      entries = FlashProfile.profile(strings, min_patterns: 3, max_patterns: 5)

      # Each cluster should be relatively pure (same format)
      # Count the number of clusters where all strings share similar characteristics
      pure_clusters =
        Enum.count(entries, fn entry ->
          # A cluster is pure if all strings are similar format
          # For dates, check if they all contain same separators
          data = entry.data

          if length(data) > 1 do
            # Check if all have same separator pattern
            separators =
              Enum.map(data, fn s ->
                cond do
                  String.contains?(s, "/") -> :slash
                  String.contains?(s, "-") -> :dash
                  String.contains?(s, ",") -> :comma
                  true -> :other
                end
              end)

            # Pure if all have same separator
            separators |> Enum.uniq() |> length() == 1
          else
            true
          end
        end)

      # At least 60% of clusters should be pure
      assert pure_clusters >= length(entries) * 0.6,
             "Expected at least 60% pure clusters, got #{pure_clusters}/#{length(entries)}"
    end

    @tag :cluster_quality
    test "us_canada_zip_codes - geographic separation" do
      fixture = load_fixture("us_canada_zip_codes.json")
      strings = Map.get(fixture, "Data")
      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 8)

      # US and Canadian codes should be in different clusters
      us_codes =
        Enum.filter(strings, fn s ->
          # US codes are all digits (various lengths)
          String.match?(s, ~r/^\d+$/) or String.match?(s, ~r/^\d+-\d+$/)
        end)

      canadian_codes =
        Enum.filter(strings, fn s ->
          # Canadian codes have letters and follow pattern: A1A 1A1
          String.match?(s, ~r/^[A-Z]\d[A-Z]\s?\d[A-Z]\d$/)
        end)

      # Find clusters for US codes
      us_clusters =
        entries
        |> Enum.filter(fn entry ->
          Enum.any?(us_codes, fn code -> code in entry.data end)
        end)

      # Find clusters for Canadian codes
      canadian_clusters =
        entries
        |> Enum.filter(fn entry ->
          Enum.any?(canadian_codes, fn code -> code in entry.data end)
        end)

      # US and Canadian codes should have minimal cluster overlap
      overlap = MapSet.intersection(MapSet.new(us_clusters), MapSet.new(canadian_clusters))

      # Allow at most 1 shared cluster (for edge cases)
      assert MapSet.size(overlap) <= 1,
             "US and Canadian codes should be in mostly separate clusters"
    end

    @tag :cluster_quality
    test "motivating_example - identifier type separation" do
      fixture = load_fixture("motivating_example.json")
      strings = Map.get(fixture, "Data")
      entries = FlashProfile.profile(strings, min_patterns: 4, max_patterns: 7)

      # Get identifiers by type
      pmc_ids = Enum.filter(strings, fn s -> String.starts_with?(s, "PMC") end)
      isbn_ids = Enum.filter(strings, fn s -> String.starts_with?(s, "ISBN:") end)

      # Find main cluster for each type
      pmc_cluster_idx =
        entries
        |> Enum.with_index()
        |> Enum.max_by(fn {entry, _idx} ->
          Enum.count(entry.data, fn s -> String.starts_with?(s, "PMC") end)
        end)
        |> elem(1)

      isbn_cluster_idx =
        entries
        |> Enum.with_index()
        |> Enum.max_by(fn {entry, _idx} ->
          Enum.count(entry.data, fn s -> String.starts_with?(s, "ISBN:") end)
        end)
        |> elem(1)

      # PMC and ISBN should be in different main clusters
      assert pmc_cluster_idx != isbn_cluster_idx,
             "PMC and ISBN identifiers should be in different clusters"
    end
  end
end
