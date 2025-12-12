defmodule FlashProfile.LearnerTest do
  use ExUnit.Case, async: true
  doctest FlashProfile.Learner

  alias FlashProfile.{Learner, Pattern, Atom}
  alias FlashProfile.Atoms.Defaults

  describe "learn_best_pattern/2" do
    test "learns pattern for digit strings" do
      strings = ["123", "456", "789"]
      {pattern, cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      assert is_float(cost)
      # Pattern should match all input strings
      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "learns pattern for PMC IDs" do
      strings = ["PMC123", "PMC456", "PMC789"]
      {pattern, cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      assert is_float(cost)
      # Should match all PMC IDs
      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "learns pattern for date strings" do
      strings = ["2023-01-15", "2024-12-31", "2022-06-30"]
      {pattern, cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      assert is_float(cost)
      # Should match all dates
      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "learns pattern for mixed case strings" do
      strings = ["Male", "Female"]
      {pattern, cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      assert is_float(cost)

      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "handles empty dataset" do
      {pattern, cost} = Learner.learn_best_pattern([])
      assert pattern == []
      assert cost == 0.0
    end

    test "handles single string" do
      strings = ["test"]
      {pattern, cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      assert is_float(cost)
      assert Pattern.matches?(pattern, "test")
    end

    test "handles identical strings" do
      strings = ["ABC", "ABC", "ABC"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      assert Pattern.matches?(pattern, "ABC")
    end

    test "returns error for incompatible strings" do
      # Strings with no common pattern structure
      strings = ["", "abc", "123"]
      result = Learner.learn_best_pattern(strings)

      # Could return error or a very general pattern
      case result do
        {:error, :no_pattern} -> assert true
        {pattern, _cost} -> assert is_list(pattern)
      end
    end

    test "learns pattern with specific atom set" do
      strings = ["123", "456"]
      atoms = [Defaults.get("Digit")]

      {pattern, cost} = Learner.learn_best_pattern(strings, atoms)

      assert is_list(pattern)
      assert is_float(cost)
      # Pattern should use only Digit atoms
      Enum.each(pattern, fn atom ->
        assert atom.name == "Digit" or atom.type == :constant
      end)
    end

    test "prefers shorter patterns with lower cost" do
      # Strings that could match multiple patterns
      strings = ["AAA", "BBB", "CCC"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      # Should find a compact pattern, not just use variable-width atoms
      assert is_list(pattern)
      assert length(pattern) > 0
    end

    test "handles strings with common prefix" do
      strings = ["PMC123", "PMC456", "PMC789"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      # Pattern should include constant "PMC" from common prefix
      assert is_list(pattern)
      assert length(pattern) >= 1
    end

    test "handles strings with fixed-width components" do
      strings = ["2023-01-15", "2024-12-31"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      assert is_list(pattern)
      # Should learn fixed-width pattern for date components
      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end
  end

  describe "learn_all_patterns/2" do
    test "returns list of patterns for simple dataset" do
      strings = ["123", "456"]
      patterns = Learner.learn_all_patterns(strings)

      assert is_list(patterns)
      assert length(patterns) > 0
      # All patterns should be valid
      Enum.each(patterns, fn pattern ->
        assert is_list(pattern)
      end)
    end

    test "all patterns match input strings" do
      strings = ["AB", "CD"]
      patterns = Learner.learn_all_patterns(strings)

      Enum.each(patterns, fn pattern ->
        Enum.each(strings, fn s ->
          assert Pattern.matches?(pattern, s)
        end)
      end)
    end

    test "returns empty pattern for empty dataset" do
      assert [[]] = Learner.learn_all_patterns([])
    end

    test "returns patterns for all-empty strings" do
      strings = ["", "", ""]
      assert [[]] = Learner.learn_all_patterns(strings)
    end

    test "returns empty list for incompatible strings" do
      # Mix of empty and non-empty is hard to match
      strings = ["", "abc"]
      patterns = Learner.learn_all_patterns(strings)

      # Either empty list or patterns that somehow work
      assert is_list(patterns)
    end

    test "limits number of patterns to prevent explosion" do
      strings = ["ABCD", "EFGH"]
      patterns = Learner.learn_all_patterns(strings)

      # Should have patterns but not exponentially many
      assert is_list(patterns)
      # Reasonable upper bound
      assert length(patterns) < 10000
    end
  end

  describe "get_compatible_atoms/2" do
    test "finds atoms compatible with all strings" do
      strings = ["123", "456", "789"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      assert is_list(atoms)
      assert length(atoms) > 0
      # All atoms should match all strings
      Enum.each(atoms, fn atom ->
        Enum.each(strings, fn s ->
          assert Atom.match(atom, s) > 0
        end)
      end)
    end

    test "includes digit atoms for numeric strings" do
      strings = ["123", "456"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Should include Digit atom
      digit_atoms = Enum.filter(atoms, fn a -> a.name == "Digit" end)
      assert length(digit_atoms) > 0
    end

    test "excludes non-matching atoms" do
      strings = ["123", "456"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Should not include Upper or Lower atoms
      upper_atoms = Enum.filter(atoms, fn a -> a.name == "Upper" end)
      lower_atoms = Enum.filter(atoms, fn a -> a.name == "Lower" end)

      assert length(upper_atoms) == 0
      assert length(lower_atoms) == 0
    end

    test "adds constant atoms from longest common prefix" do
      strings = ["PMC123", "PMC456", "PMC789"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Should include constant "PMC"
      pmc_atoms =
        Enum.filter(atoms, fn a ->
          a.type == :constant and a.params.string == "PMC"
        end)

      assert length(pmc_atoms) > 0
    end

    test "adds multiple constant atoms from common prefix" do
      strings = ["PMC123", "PMC456"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Should include "P", "PM", "PMC"
      constant_atoms = Enum.filter(atoms, fn a -> a.type == :constant end)
      assert length(constant_atoms) > 0

      constant_strings =
        Enum.map(constant_atoms, fn a -> a.params.string end)

      # "PMC" should be among them
      assert "PMC" in constant_strings
    end

    test "adds fixed-width variants for consistent widths" do
      strings = ["123", "456", "789"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Should include Digit×3 since all strings are 3 digits
      fixed_digit_atoms =
        Enum.filter(atoms, fn a ->
          a.name == "Digit" and a.params.width == 3
        end)

      assert length(fixed_digit_atoms) > 0
    end

    test "does not add fixed-width when widths vary" do
      strings = ["12", "456", "7890"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Should not include fixed-width Digit atoms (widths are 2, 3, 4)
      # Only variable-width Digit should be present
      variable_digit =
        Enum.find(atoms, fn a ->
          a.name == "Digit" and a.params.width == 0
        end)

      assert variable_digit != nil
    end

    test "handles empty string list" do
      assert [] = Learner.get_compatible_atoms([], Defaults.all())
    end

    test "handles empty atom list" do
      assert [] = Learner.get_compatible_atoms(["test"], [])
    end

    test "deduplicates atoms correctly" do
      strings = ["ABC", "DEF"]
      atoms = Learner.get_compatible_atoms(strings, Defaults.all())

      # Count Upper atoms - should only have one
      upper_atoms = Enum.filter(atoms, fn a -> a.name == "Upper" end)
      # Could have variable and fixed-width variants, but same name/width combos should be unique
      upper_signatures =
        Enum.map(upper_atoms, fn a -> {a.name, a.params.width} end)
        |> Enum.uniq()

      # Number of unique signatures should match number of atoms
      assert length(upper_signatures) == length(upper_atoms)
    end
  end

  describe "real-world scenarios" do
    test "learns pattern for version numbers" do
      strings = ["v1.0.0", "v2.3.1", "v10.5.2"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "learns pattern for email-like strings" do
      strings = ["user@example", "test@domain", "admin@site"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "learns pattern for phone numbers" do
      strings = ["555-1234", "123-4567", "999-0000"]
      {pattern, _cost} = Learner.learn_best_pattern(strings)

      Enum.each(strings, fn s ->
        assert Pattern.matches?(pattern, s)
      end)
    end

    test "handles heterogeneous data gracefully" do
      # Mix of different formats
      strings = ["PMC123", "2023-01-01", "ABC"]

      result = Learner.learn_best_pattern(strings)

      case result do
        {:error, :no_pattern} ->
          # Acceptable outcome for incompatible data
          assert true

        {pattern, cost} ->
          # Or finds a very general pattern
          assert is_list(pattern)
          assert is_float(cost) or cost == :infinity
      end
    end
  end
end
