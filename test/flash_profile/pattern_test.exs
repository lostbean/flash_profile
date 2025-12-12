defmodule FlashProfile.PatternTest do
  use ExUnit.Case, async: true
  doctest FlashProfile.Pattern

  alias FlashProfile.{Pattern, Atom}
  alias FlashProfile.Atoms.Defaults

  describe "empty/0" do
    test "returns empty pattern" do
      assert Pattern.empty() == []
    end
  end

  describe "matches?/2" do
    test "empty pattern matches empty string" do
      assert Pattern.matches?([], "")
    end

    test "empty pattern does not match non-empty string" do
      refute Pattern.matches?([], "abc")
      refute Pattern.matches?([], "x")
    end

    test "single atom pattern matches entirely" do
      digit = Defaults.get("Digit")
      pattern = [digit]

      assert Pattern.matches?(pattern, "123")
      assert Pattern.matches?(pattern, "9")
    end

    test "single atom pattern does not match partial string" do
      digit = Defaults.get("Digit")
      pattern = [digit]

      refute Pattern.matches?(pattern, "123abc")
      refute Pattern.matches?(pattern, "")
    end

    test "multi-atom pattern matches complete string" do
      upper = Defaults.get("Upper")
      dash = Atom.constant("-")
      digit = Defaults.get("Digit")
      pattern = [upper, dash, digit]

      assert Pattern.matches?(pattern, "A-123")
      assert Pattern.matches?(pattern, "Z-9")
    end

    test "multi-atom pattern requires all atoms to match" do
      upper = Defaults.get("Upper")
      dash = Atom.constant("-")
      digit = Defaults.get("Digit")
      pattern = [upper, dash, digit]

      refute Pattern.matches?(pattern, "AB123")
      refute Pattern.matches?(pattern, "A-")
      refute Pattern.matches?(pattern, "-123")
      refute Pattern.matches?(pattern, "A_123")
    end

    test "pattern with constant atoms" do
      pmc = Atom.constant("PMC")
      digit = Defaults.get("Digit")
      pattern = [pmc, digit]

      assert Pattern.matches?(pattern, "PMC123")
      assert Pattern.matches?(pattern, "PMC9876543")
    end

    test "pattern with fixed-width atoms" do
      digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
      dash = Atom.constant("-")
      digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
      pattern = [digit4, dash, digit2, dash, digit2]

      assert Pattern.matches?(pattern, "2023-01-15")
      refute Pattern.matches?(pattern, "23-01-15")
      refute Pattern.matches?(pattern, "2023-1-15")
    end

    test "greedy matching from left to right" do
      lower = Defaults.get("Lower")
      pattern = [lower, lower]

      # First Lower greedily matches all available characters, leaving nothing for second
      refute Pattern.matches?(pattern, "abc")
      refute Pattern.matches?(pattern, "a")
    end
  end

  describe "match/2" do
    test "returns ok with match details for valid pattern" do
      digit = Defaults.get("Digit")
      upper = Defaults.get("Upper")
      pattern = [upper, digit]

      assert {:ok, matches} = Pattern.match(pattern, "A123")
      assert length(matches) == 2

      [{atom1, matched1, pos1, len1}, {atom2, matched2, pos2, len2}] = matches

      assert atom1.name == "Upper"
      assert matched1 == "A"
      assert pos1 == 0
      assert len1 == 1

      assert atom2.name == "Digit"
      assert matched2 == "123"
      assert pos2 == 1
      assert len2 == 3
    end

    test "returns error for non-matching pattern" do
      digit = Defaults.get("Digit")
      pattern = [digit]

      assert {:error, :no_match} = Pattern.match(pattern, "abc")
    end

    test "returns error for partial match" do
      digit = Defaults.get("Digit")
      pattern = [digit]

      assert {:error, :no_match} = Pattern.match(pattern, "123abc")
    end

    test "empty pattern matches empty string" do
      assert {:ok, []} = Pattern.match([], "")
    end

    test "empty pattern does not match non-empty string" do
      assert {:error, :no_match} = Pattern.match([], "x")
    end
  end

  describe "match_lengths/2" do
    test "returns lengths for each matched atom" do
      upper = Defaults.get("Upper")
      digit = Defaults.get("Digit")
      pattern = [upper, digit]

      assert Pattern.match_lengths(pattern, "A123") == [1, 3]
      assert Pattern.match_lengths(pattern, "Z9") == [1, 1]
    end

    test "returns nil for non-matching pattern" do
      digit = Defaults.get("Digit")
      pattern = [digit]

      assert Pattern.match_lengths(pattern, "abc") == nil
    end

    test "handles variable-width atoms" do
      upper = Defaults.get("Upper")
      lower = Defaults.get("Lower")
      pattern = [upper, lower]

      assert Pattern.match_lengths(pattern, "Male") == [1, 3]
      assert Pattern.match_lengths(pattern, "Female") == [1, 5]
    end

    test "handles fixed-width atoms" do
      digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
      digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
      pattern = [digit4, digit2]

      assert Pattern.match_lengths(pattern, "202301") == [4, 2]
    end
  end

  describe "to_string/1" do
    test "formats empty pattern" do
      assert Pattern.to_string([]) == ""
    end

    test "formats single atom pattern" do
      digit = Defaults.get("Digit")
      pattern = [digit]

      assert Pattern.to_string(pattern) == "Digit+"
    end

    test "formats multi-atom pattern with separator" do
      upper = Defaults.get("Upper")
      lower = Defaults.get("Lower")
      pattern = [upper, lower]

      assert Pattern.to_string(pattern) == "Upper+ ◇ Lower+"
    end

    test "formats constant atoms with quotes" do
      pmc = Atom.constant("PMC")
      digit = Defaults.get("Digit")
      pattern = [pmc, digit]

      str = Pattern.to_string(pattern)
      assert String.contains?(str, "PMC")
      assert String.contains?(str, "Digit+")
      assert String.contains?(str, "◇")
    end

    test "formats fixed-width atoms with ×N notation" do
      digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
      dash = Atom.constant("-")
      digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
      pattern = [digit4, dash, digit2]

      str = Pattern.to_string(pattern)
      assert String.contains?(str, "Digit×4")
      assert String.contains?(str, "Digit×2")
    end
  end

  describe "concat/2" do
    test "concatenates two patterns" do
      upper = Defaults.get("Upper")
      lower = Defaults.get("Lower")
      digit = Defaults.get("Digit")

      p1 = [upper, lower]
      p2 = [digit]

      result = Pattern.concat(p1, p2)

      assert length(result) == 3
      assert Pattern.matches?(result, "Ab123")
    end

    test "concatenates empty patterns" do
      digit = Defaults.get("Digit")

      assert Pattern.concat([], [digit]) == [digit]
      assert Pattern.concat([digit], []) == [digit]
      assert Pattern.concat([], []) == []
    end
  end

  describe "append/2" do
    test "appends atom to pattern" do
      upper = Defaults.get("Upper")
      digit = Defaults.get("Digit")
      pattern = [upper]

      result = Pattern.append(pattern, digit)

      assert length(result) == 2
      assert Pattern.matches?(result, "A123")
    end

    test "appends to empty pattern" do
      digit = Defaults.get("Digit")

      result = Pattern.append([], digit)

      assert result == [digit]
    end
  end

  describe "length/1" do
    test "returns number of atoms in pattern" do
      upper = Defaults.get("Upper")
      digit = Defaults.get("Digit")

      assert Pattern.length([]) == 0
      assert Pattern.length([upper]) == 1
      assert Pattern.length([upper, digit]) == 2
    end
  end

  describe "empty?/1" do
    test "returns true for empty pattern" do
      assert Pattern.empty?([])
    end

    test "returns false for non-empty pattern" do
      digit = Defaults.get("Digit")

      refute Pattern.empty?([digit])
    end
  end

  describe "first/1" do
    test "returns first atom of pattern" do
      upper = Defaults.get("Upper")
      digit = Defaults.get("Digit")
      pattern = [upper, digit]

      first = Pattern.first(pattern)

      assert first.name == "Upper"
    end

    test "returns nil for empty pattern" do
      assert Pattern.first([]) == nil
    end
  end

  describe "last/1" do
    test "returns last atom of pattern" do
      upper = Defaults.get("Upper")
      digit = Defaults.get("Digit")
      pattern = [upper, digit]

      last = Pattern.last(pattern)

      assert last.name == "Digit"
    end

    test "returns nil for empty pattern" do
      assert Pattern.last([]) == nil
    end

    test "returns same atom for single-atom pattern" do
      digit = Defaults.get("Digit")

      assert Pattern.first([digit]) == Pattern.last([digit])
    end
  end

  describe "real-world patterns" do
    test "PMC identifier pattern" do
      pmc = Atom.constant("PMC")
      digit7 = Atom.char_class("Digit", ~c"0123456789", 7, 8.2)
      pattern = [pmc, digit7]

      assert Pattern.matches?(pattern, "PMC1234567")
      assert Pattern.matches?(pattern, "PMC9876543")
      refute Pattern.matches?(pattern, "PMC123")
      refute Pattern.matches?(pattern, "XYZ1234567")
    end

    test "date pattern YYYY-MM-DD" do
      digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
      dash = Atom.constant("-")
      digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
      pattern = [digit4, dash, digit2, dash, digit2]

      assert Pattern.matches?(pattern, "2023-01-15")
      assert Pattern.matches?(pattern, "2024-12-31")
      refute Pattern.matches?(pattern, "23-01-15")
      refute Pattern.matches?(pattern, "2023/01/15")
    end

    test "phone number pattern XXX-XXXX" do
      digit3 = Atom.char_class("Digit", ~c"0123456789", 3, 8.2)
      dash = Atom.constant("-")
      digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
      pattern = [digit3, dash, digit4]

      assert Pattern.matches?(pattern, "555-1234")
      assert Pattern.matches?(pattern, "123-9876")
      refute Pattern.matches?(pattern, "555-123")
      refute Pattern.matches?(pattern, "555.1234")
    end

    test "email-like pattern with variable-width atoms" do
      lower = Defaults.get("Lower")
      at = Atom.constant("@")
      alpha = Defaults.get("Alpha")
      pattern = [lower, at, alpha]

      assert Pattern.matches?(pattern, "user@example")
      assert Pattern.matches?(pattern, "test@Domain")
      refute Pattern.matches?(pattern, "User@example")
      refute Pattern.matches?(pattern, "user-example")
    end
  end
end
