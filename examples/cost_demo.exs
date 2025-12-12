# Cost Module Demonstration
# Run with: mix run examples/cost_demo.exs

alias FlashProfile.{Cost, Atom}

defmodule CostDemo do
  @moduledoc """
  Demonstrates the FlashProfile.Cost module with examples from the paper.
  """

  def print_header(title) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts(title)
    IO.puts(String.duplicate("=", 70))
  end

  def print_pattern(pattern, name \\ "Pattern") do
    pattern_str =
      pattern
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(" ◇ ")

    IO.puts("#{name}: #{pattern_str}")
  end

  def print_cost_breakdown(pattern, strings) do
    case Cost.calculate_detailed(pattern, strings) do
      {:ok, {total, breakdown}} ->
        IO.puts("\nCost Breakdown:")
        IO.puts("  " <> String.duplicate("-", 60))

        Enum.each(breakdown, fn {atom, static, weight} ->
          contribution = static * weight
          IO.puts("  #{String.pad_trailing(atom.name, 15)} | " <>
                  "Static: #{:io_lib.format("~.3f", [static])} | " <>
                  "Weight: #{:io_lib.format("~.4f", [weight])} | " <>
                  "Cost: #{:io_lib.format("~.4f", [contribution])}")
        end)

        IO.puts("  " <> String.duplicate("-", 60))
        IO.puts("  Total Cost: #{:io_lib.format("~.4f", [total])}\n")
        total

      {:error, reason} ->
        IO.puts("\nError: #{inspect(reason)}")
        :infinity
    end
  end

  def demo_basic_examples do
    print_header("1. BASIC EXAMPLES")

    # Example 1: Simple digit pattern
    IO.puts("\nExample 1a: Single character class matching entirely")
    digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
    strings = ["123", "456", "789"]
    print_pattern([digit])
    IO.puts("Strings: #{inspect(strings)}")
    print_cost_breakdown([digit], strings)

    # Example 1b: Pattern that doesn't match
    IO.puts("\nExample 1b: Pattern that doesn't match")
    strings = ["abc"]
    print_pattern([digit])
    IO.puts("Strings: #{inspect(strings)}")
    cost = Cost.calculate([digit], strings)
    IO.puts("Cost: #{inspect(cost)}")
  end

  def demo_paper_example do
    print_header("2. EXAMPLE FROM PAPER (Section 4.3)")

    upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
    lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
    alpha = Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

    strings = ["Male", "Female"]
    IO.puts("Dataset: #{inspect(strings)}")

    # Pattern 1: Upper ◇ Lower
    IO.puts("\nPattern 1:")
    pattern1 = [upper, lower]
    print_pattern(pattern1)
    IO.puts("\nHow it matches:")
    IO.puts("  'Male'   -> Upper:'M' (1/4) + Lower:'ale' (3/4)")
    IO.puts("  'Female' -> Upper:'F' (1/6) + Lower:'emale' (5/6)")
    cost1 = print_cost_breakdown(pattern1, strings)

    # Pattern 2: Alpha
    IO.puts("\nPattern 2:")
    pattern2 = [alpha]
    print_pattern(pattern2)
    IO.puts("\nHow it matches:")
    IO.puts("  'Male'   -> Alpha:'Male' (4/4)")
    IO.puts("  'Female' -> Alpha:'Female' (6/6)")
    cost2 = print_cost_breakdown(pattern2, strings)

    # Compare
    IO.puts("\nComparison:")
    IO.puts("  Pattern 1 cost: #{:io_lib.format("~.4f", [cost1])}")
    IO.puts("  Pattern 2 cost: #{:io_lib.format("~.4f", [cost2])}")
    IO.puts("  Better pattern: Pattern 1 (lower cost)")
    IO.puts("  Cost.compare(pattern1, pattern2, strings) = #{inspect(Cost.compare(pattern1, pattern2, strings))}")
  end

  def demo_constant_patterns do
    print_header("3. PATTERNS WITH CONSTANTS")

    pmc = Atom.constant("PMC")
    digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)

    strings = ["PMC123", "PMC456"]
    IO.puts("Dataset: #{inspect(strings)}")

    pattern = [pmc, digit]
    print_pattern(pattern)
    IO.puts("\nHow it matches:")
    IO.puts("  'PMC123' -> \"PMC\":'PMC' (3/6) + Digit:'123' (3/6)")
    IO.puts("  'PMC456' -> \"PMC\":'PMC' (3/6) + Digit:'456' (3/6)")
    print_cost_breakdown(pattern, strings)
  end

  def demo_complex_patterns do
    print_header("4. COMPARING MULTIPLE PATTERNS")

    # Define atoms
    upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
    lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
    digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
    alphanum = Atom.char_class("AlphaNum",
      (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()) ++ (?0..?9 |> Enum.to_list()),
      12.0)

    strings = ["User123", "Admin456"]
    IO.puts("Dataset: #{inspect(strings)}")

    patterns = [
      [upper, lower, digit],
      [alphanum],
      [upper, alphanum]
    ]

    IO.puts("\nEvaluating #{length(patterns)} patterns:")

    _costs =
      Enum.with_index(patterns, 1)
      |> Enum.map(fn {pattern, idx} ->
        IO.puts("\n--- Pattern #{idx} ---")
        print_pattern(pattern)
        cost = print_cost_breakdown(pattern, strings)
        {pattern, cost}
      end)

    {best_pattern, best_cost} = Cost.min_cost(patterns, strings)

    IO.puts("\nBest Pattern:")
    print_pattern(best_pattern, "  Winner")
    IO.puts("  Cost: #{:io_lib.format("~.4f", [best_cost])}")
  end

  def demo_edge_cases do
    print_header("5. EDGE CASES")

    # Empty cases
    IO.puts("\nCase 1: Empty pattern on empty strings")
    cost = Cost.calculate([], [])
    IO.puts("  Cost.calculate([], []) = #{inspect(cost)}")

    IO.puts("\nCase 2: Empty pattern on non-empty strings")
    cost = Cost.calculate([], ["test"])
    IO.puts("  Cost.calculate([], [\"test\"]) = #{inspect(cost)}")

    IO.puts("\nCase 3: Any pattern on empty strings")
    digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
    cost = Cost.calculate([digit], [])
    IO.puts("  Cost.calculate([digit], []) = #{inspect(cost)}")

    # Partial match
    IO.puts("\nCase 4: Pattern partially matches (remainder left)")
    pattern = [digit, digit]
    cost = Cost.calculate(pattern, ["123abc"])
    IO.puts("  Pattern: Digit ◇ Digit")
    IO.puts("  String: \"123abc\"")
    IO.puts("  Cost: #{inspect(cost)} (pattern must consume entire string)")
  end

  def run do
    IO.puts("\n")
    IO.puts(String.duplicate("*", 70))
    IO.puts(String.duplicate("*", 70))
    IO.puts("***" <> String.pad_leading("", 64) <> "***")
    IO.puts("***" <> String.pad_leading("FlashProfile Cost Module Demonstration", 52) <> String.pad_trailing("", 12) <> "***")
    IO.puts("***" <> String.pad_leading("", 64) <> "***")
    IO.puts(String.duplicate("*", 70))
    IO.puts(String.duplicate("*", 70))

    demo_basic_examples()
    demo_paper_example()
    demo_constant_patterns()
    demo_complex_patterns()
    demo_edge_cases()

    print_header("DEMONSTRATION COMPLETE")
    IO.puts("")
  end
end

CostDemo.run()
