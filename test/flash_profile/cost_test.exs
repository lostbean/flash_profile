defmodule FlashProfile.CostTest do
  use ExUnit.Case, async: true
  doctest FlashProfile.Cost

  alias FlashProfile.{Cost, Atom}

  describe "calculate/2" do
    test "returns 0.0 for empty pattern on empty strings" do
      assert Cost.calculate([], []) == 0.0
    end

    test "returns :infinity for empty pattern on non-empty strings" do
      assert Cost.calculate([], ["test"]) == :infinity
    end

    test "returns 0.0 for any pattern on empty strings" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      assert Cost.calculate([digit], []) == 0.0
    end

    test "returns :infinity when pattern doesn't match" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      assert Cost.calculate([digit], ["abc"]) == :infinity
    end

    test "calculates cost for pattern matching entirely" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      cost = Cost.calculate([digit], ["123"])
      # Dynamic weight is 1.0 (matches entire string)
      # Cost = 8.2 * 1.0 = 8.2
      assert_in_delta cost, 8.2, 0.01
    end

    test "calculates cost for Male/Female example from paper" do
      upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
      lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
      pattern = [upper, lower]
      strings = ["Male", "Female"]

      cost = Cost.calculate(pattern, strings)

      # Upper matches "M" (1/4) and "F" (1/6)
      # Average: (1/4 + 1/6) / 2 = 0.2083
      # Lower matches "ale" (3/4) and "emale" (5/6)
      # Average: (3/4 + 5/6) / 2 = 0.7917
      # Cost = 8.2 * 0.2083 + 9.1 * 0.7917 = 8.9125

      expected_upper_weight = (1.0 / 4.0 + 1.0 / 6.0) / 2.0
      expected_lower_weight = (3.0 / 4.0 + 5.0 / 6.0) / 2.0
      expected_cost = 8.2 * expected_upper_weight + 9.1 * expected_lower_weight

      assert_in_delta cost, expected_cost, 0.01
      assert_in_delta cost, 8.9125, 0.01
    end

    test "calculates cost with constant atoms" do
      pmc = Atom.constant("PMC")
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      pattern = [pmc, digit]
      strings = ["PMC123", "PMC456"]

      cost = Cost.calculate(pattern, strings)

      # PMC matches 3/6 = 0.5 in each string
      # Digit matches 3/6 = 0.5 in each string
      pmc_static_cost = 100.0 / 3.0
      expected = pmc_static_cost * 0.5 + 8.2 * 0.5

      assert_in_delta cost, expected, 0.01
    end

    test "returns :infinity when pattern only partially matches" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      pattern = [digit, digit]

      # First digit matches but second doesn't
      assert Cost.calculate(pattern, ["123abc"]) == :infinity
    end
  end

  describe "calculate_detailed/2" do
    test "returns detailed breakdown for valid pattern" do
      upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
      lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
      pattern = [upper, lower]
      strings = ["Male", "Female"]

      {:ok, {total_cost, breakdown}} = Cost.calculate_detailed(pattern, strings)

      assert length(breakdown) == 2
      assert is_float(total_cost)

      [{atom1, static1, weight1}, {atom2, static2, weight2}] = breakdown

      assert atom1.name == "Upper"
      assert_in_delta static1, 8.2, 0.01
      assert_in_delta weight1, 0.2083, 0.01

      assert atom2.name == "Lower"
      assert_in_delta static2, 9.1, 0.01
      assert_in_delta weight2, 0.7917, 0.01

      assert_in_delta total_cost, static1 * weight1 + static2 * weight2, 0.01
    end

    test "returns error when pattern doesn't match" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      assert {:error, :no_match} = Cost.calculate_detailed([digit], ["abc"])
    end

    test "returns ok with empty breakdown for empty pattern on empty strings" do
      assert {:ok, {cost, []}} = Cost.calculate_detailed([], [])
      assert cost == 0.0
    end

    test "returns error for empty pattern on non-empty strings" do
      assert {:error, :empty_pattern_non_empty_strings} =
               Cost.calculate_detailed([], ["test"])
    end
  end

  describe "compare/3" do
    test "returns :lt when first pattern has lower cost" do
      upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
      lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)

      alpha =
        Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

      pattern1 = [upper, lower]
      pattern2 = [alpha]
      strings = ["Male", "Female"]

      assert Cost.compare(pattern1, pattern2, strings) == :lt
    end

    test "returns :gt when second pattern has lower cost" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)

      alpha =
        Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

      pattern1 = [alpha]
      pattern2 = [digit]
      strings = ["123"]

      assert Cost.compare(pattern1, pattern2, strings) == :gt
    end

    test "returns :eq when both patterns have equal cost" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      pattern1 = [digit]
      pattern2 = [digit]

      assert Cost.compare(pattern1, pattern2, ["123"]) == :eq
    end

    test "returns :eq when both patterns have infinity cost" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      pattern1 = [digit]
      pattern2 = [digit]

      assert Cost.compare(pattern1, pattern2, ["abc"]) == :eq
    end

    test "returns :gt when first pattern has infinity cost" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)

      alpha =
        Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

      pattern1 = [digit]
      pattern2 = [alpha]
      strings = ["abc"]

      assert Cost.compare(pattern1, pattern2, strings) == :gt
    end

    test "returns :lt when second pattern has infinity cost" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)

      alpha =
        Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

      pattern1 = [alpha]
      pattern2 = [digit]
      strings = ["abc"]

      assert Cost.compare(pattern1, pattern2, strings) == :lt
    end
  end

  describe "min_cost/2" do
    test "returns nil for empty pattern list" do
      assert Cost.min_cost([], ["test"]) == nil
    end

    test "returns the only pattern when list has one element" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      pattern = [digit]

      {result_pattern, cost} = Cost.min_cost([pattern], ["123"])

      assert result_pattern == pattern
      assert_in_delta cost, 8.2, 0.01
    end

    test "returns pattern with minimum cost" do
      upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
      lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)

      alpha =
        Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

      pattern1 = [upper, lower]
      pattern2 = [alpha]
      strings = ["Male", "Female"]

      {best_pattern, cost} = Cost.min_cost([pattern1, pattern2], strings)

      assert best_pattern == pattern1
      assert_in_delta cost, 8.9125, 0.01
    end

    test "returns pattern with finite cost over infinity" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)

      alpha =
        Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)

      pattern1 = [digit]
      pattern2 = [alpha]
      strings = ["abc"]

      {best_pattern, cost} = Cost.min_cost([pattern1, pattern2], strings)

      assert best_pattern == pattern2
      assert_in_delta cost, 15.0, 0.01
    end

    test "handles all patterns having infinity cost" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)

      pattern1 = [digit]
      pattern2 = [upper]
      strings = ["abc"]

      {_best_pattern, cost} = Cost.min_cost([pattern1, pattern2], strings)

      assert cost == :infinity
    end
  end
end
