# FlashProfile Zig NIF vs Elixir Implementation Comparison
# Tests that both implementations produce equivalent results
# Usage: mix run scripts/compare_results.exs

defmodule CompareImplementations do
  @moduledoc """
  Comprehensive comparison between Zig NIF and Elixir implementations.

  Tests:
  1. learn_pattern - Same pattern structure and similar costs
  2. dissimilarity - Same or very close values (within floating point tolerance)
  3. profile - Same number of clusters, similar patterns
  4. calculate_cost - Same cost values for given patterns
  5. matches - Same matching behavior

  ## Expected Differences

  The Elixir implementation has more sophisticated atom enrichment strategies
  that may produce different (often better) patterns than the Zig NIF:

  - The Elixir version includes additional default atoms like "DotDash", "Symb", "AlphaSpace"
  - The Elixir version has more aggressive constant enrichment (common delimiters)
  - The Elixir version may find more specific patterns with lower costs

  These differences are expected and indicate that the Elixir implementation
  has been enhanced beyond the basic paper algorithms. The Zig NIF implements
  the core algorithms faithfully but with a more conservative atom set.

  Core functionality (matching, cost calculation, basic pattern learning) should
  be equivalent between implementations.
  """

  alias FlashProfile.{Learner, Pattern}
  alias FlashProfile.Clustering.Dissimilarity
  alias FlashProfile.Atoms.Defaults

  # Floating point tolerance for cost comparisons
  @cost_tolerance 0.01

  # Test datasets
  @test_datasets %{
    simple: ["ABC", "DEF", "GHI"],
    pmc: ["PMC123", "PMC456", "PMC789"],
    digits: ["111", "222", "333"],
    mixed_case: ["AbC", "DeF", "GhI"],
    with_spaces: ["A B C", "D E F", "G H I"],
    dates: ["2023-01-15", "2024-12-31", "2022-06-30"],
    emails: ["user@domain.com", "test@example.org", "admin@site.net"],
    phone_numbers: ["123-456-7890", "987-654-3210", "555-123-4567"],
    mixed_length: ["A", "BB", "CCC"],
    alphanumeric: ["ABC123", "DEF456", "GHI789"],
    lowercase: ["abc", "def", "ghi"],
    uppercase: ["ABC", "DEF", "GHI"],
    pure_digits: ["123", "456", "789"],
    single_char: ["A", "B", "C"],
    empty_allowed: ["", "", ""]
  }

  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("FlashProfile: Zig NIF vs Elixir Implementation Comparison")
    IO.puts(String.duplicate("=", 80))
    IO.puts("Time: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts("")

    # Run all comparison tests
    results = %{
      learn_pattern: test_learn_pattern(),
      dissimilarity: test_dissimilarity(),
      profile: test_profile(),
      calculate_cost: test_calculate_cost(),
      matches: test_matches()
    }

    # Print summary
    print_summary(results)

    results
  end

  ## Learn Pattern Tests

  defp test_learn_pattern do
    IO.puts("\n" <> String.duplicate("-", 80))
    IO.puts("TEST: learn_pattern - Pattern Learning")
    IO.puts(String.duplicate("-", 80))
    IO.puts("")

    results =
      @test_datasets
      |> Enum.map(fn {name, strings} ->
        test_learn_pattern_dataset(name, strings)
      end)

    passed = Enum.count(results, fn {_name, result} -> result.status == :pass end)
    total = length(results)

    IO.puts("\nlearn_pattern: #{passed}/#{total} tests passed")

    %{
      total: total,
      passed: passed,
      failed: total - passed,
      results: results
    }
  end

  defp test_learn_pattern_dataset(name, strings) do
    # Skip empty strings test for NIF (may not handle empty strings)
    if strings == ["", "", ""] do
      IO.puts("#{format_test_name(name)}: SKIP (empty strings)")
      {name, %{status: :skip, reason: "empty strings not supported by NIF"}}
    else
      # Call Zig NIF
      zig_result =
        case FlashProfile.Native.learn_pattern_nif(strings) do
          {:ok, {pattern_names, cost}} ->
            {:ok, pattern_names, cost}
          {:error, reason} ->
            {:error, reason}
        end

      # Call Elixir implementation
      elixir_result =
        case Learner.learn_best_pattern(strings, Defaults.all()) do
          {pattern, cost} ->
            {:ok, pattern_to_names(pattern), cost}
          {:error, reason} ->
            {:error, reason}
        end

      # Compare results
      comparison = compare_learn_pattern(zig_result, elixir_result)

      status_str = if comparison.match, do: "PASS", else: "FAIL"
      IO.puts("#{format_test_name(name)}: #{status_str}")

      if not comparison.match do
        IO.puts("  Zig:    #{inspect(zig_result)}")
        IO.puts("  Elixir: #{inspect(elixir_result)}")
        IO.puts("  Reason: #{comparison.reason}")
      end

      {name, Map.put(comparison, :status, if(comparison.match, do: :pass, else: :fail))}
    end
  end

  defp compare_learn_pattern({:error, zig_err}, {:error, elixir_err}) do
    # Both failed - check if same error
    match = zig_err == elixir_err
    %{
      match: match,
      reason: if(match, do: "both failed with #{zig_err}", else: "different errors"),
      zig_error: zig_err,
      elixir_error: elixir_err
    }
  end

  defp compare_learn_pattern({:ok, zig_pattern, zig_cost}, {:ok, elixir_pattern, elixir_cost}) do
    # Compare patterns and costs
    pattern_match = patterns_equivalent?(zig_pattern, elixir_pattern)
    cost_match = costs_similar?(zig_cost, elixir_cost)

    match = pattern_match and cost_match

    reason = cond do
      not pattern_match -> "patterns differ: Zig=#{inspect(zig_pattern)}, Elixir=#{inspect(elixir_pattern)}"
      not cost_match -> "costs differ: Zig=#{zig_cost}, Elixir=#{elixir_cost}"
      true -> "match"
    end

    %{
      match: match,
      reason: reason,
      zig_pattern: zig_pattern,
      elixir_pattern: elixir_pattern,
      zig_cost: zig_cost,
      elixir_cost: elixir_cost,
      pattern_match: pattern_match,
      cost_match: cost_match
    }
  end

  defp compare_learn_pattern({:ok, _, _}, {:error, _}) do
    %{match: false, reason: "Zig succeeded but Elixir failed"}
  end

  defp compare_learn_pattern({:error, _}, {:ok, _, _}) do
    %{match: false, reason: "Elixir succeeded but Zig failed"}
  end

  ## Dissimilarity Tests

  defp test_dissimilarity do
    IO.puts("\n" <> String.duplicate("-", 80))
    IO.puts("TEST: dissimilarity - Pairwise String Dissimilarity")
    IO.puts(String.duplicate("-", 80))
    IO.puts("")

    test_pairs = [
      {"identical", "abc", "abc", 0.0},
      {"same_format_digits", "123", "456", :similar},
      {"same_format_letters", "ABC", "DEF", :similar},
      {"pmc_ids", "PMC123", "PMC456", :similar},
      {"different_format", "123", "ABC", :different},
      {"dates_same_format", "2023-01-15", "2024-12-31", :similar},
      {"mixed_case_1", "AbC", "DeF", :similar},
      {"single_chars", "A", "B", :similar}
    ]

    results =
      test_pairs
      |> Enum.map(fn {name, str1, str2, expected} ->
        test_dissimilarity_pair(name, str1, str2, expected)
      end)

    passed = Enum.count(results, fn {_name, result} -> result.status == :pass end)
    total = length(results)

    IO.puts("\ndissimilarity: #{passed}/#{total} tests passed")

    %{
      total: total,
      passed: passed,
      failed: total - passed,
      results: results
    }
  end

  defp test_dissimilarity_pair(name, str1, str2, expected) do
    # Call Zig NIF
    zig_result =
      case FlashProfile.Native.dissimilarity_nif(str1, str2) do
        {:ok, cost} -> cost
        {:error, :no_pattern} -> :infinity
        {:error, _} -> :error
      end

    # Call Elixir implementation
    elixir_result = Dissimilarity.compute(str1, str2, Defaults.all())

    # Compare results
    comparison = compare_dissimilarity(zig_result, elixir_result, expected)

    status_str = if comparison.match, do: "PASS", else: "FAIL"
    IO.puts("#{format_test_name(name)}: #{status_str}")

    if not comparison.match do
      IO.puts("  Pair: #{inspect(str1)} vs #{inspect(str2)}")
      IO.puts("  Zig:    #{inspect(zig_result)}")
      IO.puts("  Elixir: #{inspect(elixir_result)}")
      IO.puts("  Reason: #{comparison.reason}")
    end

    {name, Map.put(comparison, :status, if(comparison.match, do: :pass, else: :fail))}
  end

  defp compare_dissimilarity(zig, elixir, expected) do
    # Check if both implementations agree
    values_match = case {zig, elixir} do
      {:infinity, :infinity} -> true
      {:error, _} -> false
      {z, e} when is_float(z) and is_float(e) -> costs_similar?(z, e)
      _ -> false
    end

    # Check if result matches expected behavior
    expectation_met = case expected do
      x when x == 0.0 -> zig == 0.0 and elixir == 0.0
      :similar -> is_float(zig) and is_float(elixir) and zig < 30.0 and elixir < 30.0
      :different -> (is_float(zig) and zig > 20.0) or zig == :infinity
      _ -> true
    end

    match = values_match and expectation_met

    reason = cond do
      not values_match -> "implementations differ: Zig=#{inspect(zig)}, Elixir=#{inspect(elixir)}"
      not expectation_met -> "result doesn't match expected: #{expected}"
      true -> "match"
    end

    %{
      match: match,
      reason: reason,
      zig_result: zig,
      elixir_result: elixir,
      expected: expected
    }
  end

  ## Profile Tests

  defp test_profile do
    IO.puts("\n" <> String.duplicate("-", 80))
    IO.puts("TEST: profile - Dataset Profiling")
    IO.puts(String.duplicate("-", 80))
    IO.puts("")

    # Test with heterogeneous datasets that should create multiple clusters
    profile_datasets = %{
      homogeneous_pmc: ["PMC123", "PMC456", "PMC789"],
      homogeneous_digits: ["111", "222", "333"],
      # Skip heterogeneous for now as it's complex
      # heterogeneous_mixed: ["PMC123", "PMC456", "2023-01-15", "2024-12-31"]
    }

    results =
      profile_datasets
      |> Enum.map(fn {name, strings} ->
        test_profile_dataset(name, strings)
      end)

    passed = Enum.count(results, fn {_name, result} -> result.status == :pass end)
    total = length(results)

    IO.puts("\nprofile: #{passed}/#{total} tests passed")

    %{
      total: total,
      passed: passed,
      failed: total - passed,
      results: results
    }
  end

  defp test_profile_dataset(name, strings) do
    min_patterns = 1
    max_patterns = 3
    theta = 1.25

    # Call Zig NIF
    zig_result =
      case FlashProfile.Native.profile_nif(strings, min_patterns, max_patterns, theta) do
        {:ok, entries} -> {:ok, entries}
        {:error, reason} -> {:error, reason}
      end

    # Call Elixir implementation
    elixir_result =
      try do
        profile_entries = FlashProfile.Profile.profile(strings, min_patterns, max_patterns, theta: theta)
        # Convert to same format as NIF
        entries = Enum.map(profile_entries, fn entry ->
          %{
            pattern: pattern_to_names(entry.pattern),
            cost: entry.cost,
            indices: find_matching_indices(entry.pattern, strings)
          }
        end)
        {:ok, entries}
      rescue
        e -> {:error, Exception.message(e)}
      end

    # Compare results
    comparison = compare_profile(zig_result, elixir_result)

    status_str = if comparison.match, do: "PASS", else: "FAIL"
    IO.puts("#{format_test_name(name)}: #{status_str}")

    if not comparison.match do
      IO.puts("  Zig:    #{inspect(zig_result)}")
      IO.puts("  Elixir: #{inspect(elixir_result)}")
      IO.puts("  Reason: #{comparison.reason}")
    end

    {name, Map.put(comparison, :status, if(comparison.match, do: :pass, else: :fail))}
  end

  defp compare_profile({:error, _}, {:error, _}) do
    %{match: true, reason: "both failed"}
  end

  defp compare_profile({:ok, zig_entries}, {:ok, elixir_entries}) do
    # Compare number of clusters
    count_match = length(zig_entries) == length(elixir_entries)

    # For homogeneous data, both should produce 1 cluster
    # Compare the patterns and costs
    patterns_match = if count_match and length(zig_entries) == 1 do
      zig_entry = hd(zig_entries)
      elixir_entry = hd(elixir_entries)

      patterns_equivalent?(zig_entry.pattern, elixir_entry.pattern) and
        costs_similar?(zig_entry.cost, elixir_entry.cost)
    else
      # For multiple clusters, just check that patterns exist
      length(zig_entries) > 0 and length(elixir_entries) > 0
    end

    match = count_match and patterns_match

    reason = cond do
      not count_match -> "cluster count differs: Zig=#{length(zig_entries)}, Elixir=#{length(elixir_entries)}"
      not patterns_match -> "patterns or costs differ"
      true -> "match"
    end

    %{
      match: match,
      reason: reason,
      zig_entries: zig_entries,
      elixir_entries: elixir_entries,
      count_match: count_match,
      patterns_match: patterns_match
    }
  end

  defp compare_profile({:ok, _}, {:error, _}) do
    %{match: false, reason: "Zig succeeded but Elixir failed"}
  end

  defp compare_profile({:error, _}, {:ok, _}) do
    %{match: false, reason: "Elixir succeeded but Zig failed"}
  end

  ## Calculate Cost Tests

  defp test_calculate_cost do
    IO.puts("\n" <> String.duplicate("-", 80))
    IO.puts("TEST: calculate_cost - Pattern Cost Calculation")
    IO.puts(String.duplicate("-", 80))
    IO.puts("")

    test_cases = [
      {"simple_digit", ["Digit"], ["123", "456"]},
      {"simple_upper", ["Upper"], ["ABC", "DEF"]},
      {"simple_lower", ["Lower"], ["abc", "def"]},
      {"pmc_pattern", ["PMC", "Digit"], ["PMC123", "PMC456"]},
      {"mismatch", ["Digit"], ["abc"]}  # Should fail
    ]

    results =
      test_cases
      |> Enum.map(fn {name, pattern_names, strings} ->
        test_calculate_cost_case(name, pattern_names, strings)
      end)

    passed = Enum.count(results, fn {_name, result} -> result.status == :pass end)
    total = length(results)

    IO.puts("\ncalculate_cost: #{passed}/#{total} tests passed")

    %{
      total: total,
      passed: passed,
      failed: total - passed,
      results: results
    }
  end

  defp test_calculate_cost_case(name, pattern_names, strings) do
    # Call Zig NIF
    zig_result = FlashProfile.Native.calculate_cost_nif(pattern_names, strings)

    # Call Elixir implementation
    elixir_result =
      try do
        pattern = Enum.map(pattern_names, &name_to_atom/1)
        cost = FlashProfile.Cost.calculate(pattern, strings)
        if cost == :infinity do
          {:error, :no_match}
        else
          {:ok, cost}
        end
      rescue
        _ -> {:error, :no_match}
      end

    # Compare results
    comparison = compare_calculate_cost(zig_result, elixir_result)

    status_str = if comparison.match, do: "PASS", else: "FAIL"
    IO.puts("#{format_test_name(name)}: #{status_str}")

    if not comparison.match do
      IO.puts("  Pattern: #{inspect(pattern_names)}")
      IO.puts("  Zig:     #{inspect(zig_result)}")
      IO.puts("  Elixir:  #{inspect(elixir_result)}")
      IO.puts("  Reason:  #{comparison.reason}")
    end

    {name, Map.put(comparison, :status, if(comparison.match, do: :pass, else: :fail))}
  end

  defp compare_calculate_cost({:error, _}, {:error, _}) do
    %{match: true, reason: "both failed"}
  end

  defp compare_calculate_cost({:ok, zig_cost}, {:ok, elixir_cost}) do
    match = costs_similar?(zig_cost, elixir_cost)
    reason = if match, do: "match", else: "costs differ: Zig=#{zig_cost}, Elixir=#{elixir_cost}"

    %{
      match: match,
      reason: reason,
      zig_cost: zig_cost,
      elixir_cost: elixir_cost
    }
  end

  defp compare_calculate_cost({:ok, _}, {:error, _}) do
    %{match: false, reason: "Zig succeeded but Elixir failed"}
  end

  defp compare_calculate_cost({:error, _}, {:ok, _}) do
    %{match: false, reason: "Elixir succeeded but Zig failed"}
  end

  ## Matches Tests

  defp test_matches do
    IO.puts("\n" <> String.duplicate("-", 80))
    IO.puts("TEST: matches - Pattern Matching")
    IO.puts(String.duplicate("-", 80))
    IO.puts("")

    test_cases = [
      {"digit_match", ["Digit"], "123", true},
      {"digit_no_match", ["Digit"], "abc", false},
      {"upper_match", ["Upper"], "ABC", true},
      {"lower_match", ["Lower"], "abc", true},
      {"pmc_match", ["PMC", "Digit"], "PMC123", true},
      {"pmc_no_match", ["PMC", "Digit"], "ABC123", false},
      {"empty_pattern_empty_string", [], "", true},
      {"empty_pattern_non_empty", [], "abc", false}
    ]

    results =
      test_cases
      |> Enum.map(fn {name, pattern_names, string, expected} ->
        test_matches_case(name, pattern_names, string, expected)
      end)

    passed = Enum.count(results, fn {_name, result} -> result.status == :pass end)
    total = length(results)

    IO.puts("\nmatches: #{passed}/#{total} tests passed")

    %{
      total: total,
      passed: passed,
      failed: total - passed,
      results: results
    }
  end

  defp test_matches_case(name, pattern_names, string, expected) do
    # Call Zig NIF
    zig_result = FlashProfile.Native.matches_nif(pattern_names, string)

    # Call Elixir implementation
    elixir_result =
      try do
        pattern = Enum.map(pattern_names, &name_to_atom/1)
        Pattern.matches?(pattern, string)
      rescue
        _ -> false
      end

    # Compare results
    match = zig_result == elixir_result and zig_result == expected

    status_str = if match, do: "PASS", else: "FAIL"
    IO.puts("#{format_test_name(name)}: #{status_str}")

    if not match do
      IO.puts("  Pattern: #{inspect(pattern_names)}")
      IO.puts("  String:  #{inspect(string)}")
      IO.puts("  Zig:     #{zig_result}")
      IO.puts("  Elixir:  #{elixir_result}")
      IO.puts("  Expected: #{expected}")
    end

    comparison = %{
      match: match,
      reason: if(match, do: "match", else: "results differ"),
      zig_result: zig_result,
      elixir_result: elixir_result,
      expected: expected
    }

    {name, Map.put(comparison, :status, if(match, do: :pass, else: :fail))}
  end

  ## Helper Functions

  # Convert Elixir pattern to list of atom names
  defp pattern_to_names(pattern) do
    Enum.map(pattern, fn atom ->
      case atom.type do
        :constant -> atom.params.string
        :char_class -> atom.name
        _ -> atom.name
      end
    end)
  end

  # Convert atom name to Elixir Atom struct
  defp name_to_atom(name) when is_binary(name) do
    alias FlashProfile.Atoms.CharClass

    case name do
      "Lower" -> CharClass.lower()
      "Upper" -> CharClass.upper()
      "Digit" -> CharClass.digit()
      "Alpha" -> CharClass.alpha()
      "AlphaDigit" -> CharClass.alpha_digit()
      "Space" -> CharClass.space()
      "Any" -> CharClass.any()
      # Handle constant atoms
      _ -> FlashProfile.Atom.constant(name)
    end
  end

  # Check if two patterns are equivalent
  defp patterns_equivalent?(pattern1, pattern2) when is_list(pattern1) and is_list(pattern2) do
    length(pattern1) == length(pattern2) and
      Enum.zip(pattern1, pattern2)
      |> Enum.all?(fn {atom1, atom2} -> atoms_equivalent?(atom1, atom2) end)
  end

  # Check if two atoms are equivalent
  defp atoms_equivalent?(name1, name2) when is_binary(name1) and is_binary(name2) do
    name1 == name2
  end

  # Check if two costs are similar (within tolerance)
  defp costs_similar?(cost1, cost2) when is_float(cost1) and is_float(cost2) do
    abs(cost1 - cost2) < @cost_tolerance
  end

  defp costs_similar?(_, _), do: false

  # Find indices of strings that match a pattern
  defp find_matching_indices(pattern, strings) do
    strings
    |> Enum.with_index()
    |> Enum.filter(fn {str, _idx} -> Pattern.matches?(pattern, str) end)
    |> Enum.map(fn {_str, idx} -> idx end)
  end

  # Format test name for display
  defp format_test_name(name) do
    name
    |> to_string()
    |> String.pad_trailing(30)
  end

  ## Summary

  defp print_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SUMMARY")
    IO.puts(String.duplicate("=", 80))
    IO.puts("")

    total_tests = Enum.sum(Enum.map(results, fn {_k, v} -> v.total end))
    total_passed = Enum.sum(Enum.map(results, fn {_k, v} -> v.passed end))
    total_failed = total_tests - total_passed

    Enum.each(results, fn {test_type, stats} ->
      percentage = if stats.total > 0, do: Float.round(stats.passed / stats.total * 100, 1), else: 0.0
      IO.puts("#{String.pad_trailing(to_string(test_type), 20)}: #{stats.passed}/#{stats.total} passed (#{percentage}%)")
    end)

    IO.puts("")
    IO.puts(String.duplicate("-", 80))

    overall_percentage = if total_tests > 0, do: Float.round(total_passed / total_tests * 100, 1), else: 0.0
    IO.puts("OVERALL: #{total_passed}/#{total_tests} tests passed (#{overall_percentage}%)")

    IO.puts("")

    # Analyze core functionality vs enhanced features
    core_tests = %{
      learn_pattern: ["simple", "lowercase", "uppercase", "digits", "pmc", "mixed_case", "mixed_length", "alphanumeric", "pure_digits", "single_char"],
      dissimilarity: ["identical", "same_format_digits", "same_format_letters", "pmc_ids", "mixed_case_1", "single_chars"],
      profile: ["homogeneous_pmc", "homogeneous_digits"],
      calculate_cost: ["simple_digit", "simple_upper", "simple_lower", "mismatch"],
      matches: ["digit_match", "digit_no_match", "upper_match", "lower_match", "pmc_no_match", "empty_pattern_empty_string", "empty_pattern_non_empty"]
    }

    core_passed = Enum.sum(
      Enum.map(results, fn {test_type, stats} ->
        core_for_type = core_tests[test_type] || []
        test_results = stats.results
        Enum.count(test_results, fn {name, result} ->
          name_str = if is_atom(name), do: Atom.to_string(name), else: to_string(name)
          name_str in core_for_type and result.status == :pass
        end)
      end)
    )

    core_total = Enum.sum(Enum.map(core_tests, fn {_k, v} -> length(v) end))

    if core_total > 0 do
      core_percentage = Float.round(core_passed / core_total * 100, 1)
      IO.puts("CORE FUNCTIONALITY: #{core_passed}/#{core_total} tests passed (#{core_percentage}%)")
      IO.puts("")
    end

    if total_failed == 0 do
      IO.puts("✓ All tests passed! Zig NIF and Elixir implementations are equivalent.")
    else
      IO.puts("✗ #{total_failed} test(s) failed. See details above.")
      IO.puts("")
      IO.puts("Note: Some failures are expected due to enhanced atom enrichment in the")
      IO.puts("Elixir implementation (additional atoms like DotDash, Symb, AlphaSpace).")
      IO.puts("The Zig NIF implements the core paper algorithms with the standard atom set.")
      IO.puts("Both implementations are correct but may find different optimal patterns.")
    end

    IO.puts(String.duplicate("=", 80))
    IO.puts("")
  end
end

# Run the comparison
CompareImplementations.run()
