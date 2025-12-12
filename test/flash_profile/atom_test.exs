defmodule FlashProfile.AtomTest do
  use ExUnit.Case, async: true
  doctest FlashProfile.Atom

  alias FlashProfile.Atom
  alias FlashProfile.Atoms.Defaults

  describe "constant/1" do
    test "creates constant atom with correct properties" do
      atom = Atom.constant("PMC")

      assert atom.name == inspect("PMC")
      assert atom.type == :constant
      assert is_function(atom.matcher, 1)
      assert atom.params.string == "PMC"
      assert atom.params.length == 3
    end

    test "constant cost is proportional to 1/length" do
      short = Atom.constant("AB")
      long = Atom.constant("ABCDEFGH")

      # Shorter strings have higher cost
      assert Atom.static_cost(short) > Atom.static_cost(long)
      assert_in_delta Atom.static_cost(short), 100.0 / 2, 0.01
      assert_in_delta Atom.static_cost(long), 100.0 / 8, 0.01
    end
  end

  describe "char_class/3 - variable width" do
    test "creates variable-width character class atom" do
      digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)

      assert digit.name == "Digit"
      assert digit.type == :char_class
      assert digit.params.width == 0
      assert_in_delta digit.static_cost, 8.2, 0.01
    end

    test "stores character set in params" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)

      assert digit.params.chars == ~c"0123456789"
      assert MapSet.member?(digit.params.char_set, ?5)
      refute MapSet.member?(digit.params.char_set, ?a)
    end
  end

  describe "char_class/4 - fixed width" do
    test "creates fixed-width character class atom" do
      digit2 = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 2, 8.2)

      assert digit2.name == "Digit"
      assert digit2.type == :char_class
      assert digit2.params.width == 2
      # Fixed-width cost is base_cost / width
      assert_in_delta digit2.static_cost, 8.2 / 2, 0.01
    end

    test "fixed-width has lower cost than variable-width" do
      variable = Atom.char_class("Digit", ~c"0123456789", 8.2)
      fixed = Atom.char_class("Digit", ~c"0123456789", 3, 8.2)

      assert Atom.static_cost(fixed) < Atom.static_cost(variable)
    end
  end

  describe "regex/3" do
    test "creates regex atom from string pattern" do
      atom = Atom.regex("Email", "^[a-z]+@", 15.0)

      assert atom.name == "Email"
      assert atom.type == :regex
      assert_in_delta atom.static_cost, 15.0, 0.01
    end

    test "creates regex atom from compiled regex" do
      atom = Atom.regex("Email", ~r/^[a-z]+@/, 15.0)

      assert atom.name == "Email"
      assert atom.type == :regex
    end
  end

  describe "function/3" do
    test "creates function atom with custom matcher" do
      matcher = fn s ->
        cond do
          String.starts_with?(s, "http://") -> 7
          String.starts_with?(s, "https://") -> 8
          true -> 0
        end
      end

      atom = Atom.function("Protocol", matcher, 10.0)

      assert atom.name == "Protocol"
      assert atom.type == :function
      assert_in_delta atom.static_cost, 10.0, 0.01
    end
  end

  describe "match/2 - constant atom" do
    test "matches exact string prefix" do
      pmc = Atom.constant("PMC")

      assert Atom.match(pmc, "PMC12345") == 3
      assert Atom.match(pmc, "PMC") == 3
    end

    test "returns 0 for no match" do
      pmc = Atom.constant("PMC")

      assert Atom.match(pmc, "XYZ") == 0
      assert Atom.match(pmc, "PM") == 0
      assert Atom.match(pmc, "") == 0
    end

    test "case sensitive matching" do
      pmc = Atom.constant("PMC")

      assert Atom.match(pmc, "PMC123") == 3
      assert Atom.match(pmc, "pmc123") == 0
    end
  end

  describe "match/2 - variable-width char class" do
    test "matches longest prefix of allowed characters" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)

      assert Atom.match(digit, "123abc") == 3
      assert Atom.match(digit, "9") == 1
      assert Atom.match(digit, "12345") == 5
    end

    test "returns 0 when first character doesn't match" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)

      assert Atom.match(digit, "abc123") == 0
      assert Atom.match(digit, "") == 0
    end

    test "matches all characters if entire string is in class" do
      lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)

      assert Atom.match(lower, "hello") == 5
      assert Atom.match(lower, "world123") == 5
    end
  end

  describe "match/2 - fixed-width char class" do
    test "matches exactly width characters" do
      digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)

      assert Atom.match(digit2, "12345") == 2
      assert Atom.match(digit2, "99abc") == 2
    end

    test "returns 0 if not enough characters available" do
      digit3 = Atom.char_class("Digit", ~c"0123456789", 3, 8.2)

      assert Atom.match(digit3, "12") == 0
      assert Atom.match(digit3, "") == 0
    end

    test "returns 0 if any character in range doesn't match" do
      digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)

      assert Atom.match(digit2, "1a345") == 0
      assert Atom.match(digit2, "a1234") == 0
    end

    test "works with width of 1" do
      digit1 = Atom.char_class("Digit", ~c"0123456789", 1, 8.2)

      assert Atom.match(digit1, "5abc") == 1
      assert Atom.match(digit1, "abc") == 0
    end
  end

  describe "match/2 - regex atom" do
    test "matches regex pattern from start" do
      email = Atom.regex("Email", ~r/^[a-z]+@/, 15.0)

      assert Atom.match(email, "user@example.com") == 5
      assert Atom.match(email, "test@") == 5
    end

    test "returns 0 if pattern doesn't match from start" do
      email = Atom.regex("Email", ~r/^[a-z]+@/, 15.0)

      assert Atom.match(email, "123user@") == 0
      assert Atom.match(email, "User@") == 0
    end
  end

  describe "match/2 - function atom" do
    test "uses custom matcher function" do
      matcher = fn s ->
        cond do
          String.starts_with?(s, "http://") -> 7
          String.starts_with?(s, "https://") -> 8
          true -> 0
        end
      end

      atom = Atom.function("Protocol", matcher, 10.0)

      assert Atom.match(atom, "https://example.com") == 8
      assert Atom.match(atom, "http://example.com") == 7
      assert Atom.match(atom, "ftp://example.com") == 0
    end
  end

  describe "static_cost/1" do
    test "returns float for all atom types" do
      constant = Atom.constant("ABC")
      char_class = Atom.char_class("Digit", ~c"0123456789", 8.2)
      regex_atom = Atom.regex("Email", ~r/^[a-z]+@/, 15.0)

      assert is_float(Atom.static_cost(constant))
      assert is_float(Atom.static_cost(char_class))
      assert is_float(Atom.static_cost(regex_atom))
    end

    test "constant cost based on length" do
      short = Atom.constant("A")
      long = Atom.constant("ABCDEFGHIJ")

      assert_in_delta Atom.static_cost(short), 100.0, 0.01
      assert_in_delta Atom.static_cost(long), 10.0, 0.01
    end
  end

  describe "to_string/1" do
    test "formats constant atoms with quotes" do
      pmc = Atom.constant("PMC")
      dash = Atom.constant("-")

      assert Atom.to_string(pmc) == inspect("PMC")
      assert Atom.to_string(dash) == inspect("-")
    end

    test "formats char class atoms with name" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)
      upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)

      assert Atom.to_string(digit) == "Digit"
      assert Atom.to_string(upper) == "Upper"
    end

    test "formats regex atoms with name" do
      email = Atom.regex("Email", ~r/^[a-z]+@/, 15.0)

      assert Atom.to_string(email) == "Email"
    end
  end

  describe "matches_entirely?/2" do
    test "returns true when atom matches entire string" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)
      pmc = Atom.constant("PMC")

      assert Atom.matches_entirely?(digit, "123")
      assert Atom.matches_entirely?(pmc, "PMC")
    end

    test "returns false when atom matches only prefix" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)
      pmc = Atom.constant("PMC")

      refute Atom.matches_entirely?(digit, "123abc")
      refute Atom.matches_entirely?(pmc, "PMC456")
    end

    test "returns false when atom doesn't match at all" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)

      refute Atom.matches_entirely?(digit, "abc")
      refute Atom.matches_entirely?(digit, "")
    end
  end

  describe "with_fixed_width/2" do
    test "creates fixed-width variant of variable-width atom" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)
      digit3 = Atom.with_fixed_width(digit, 3)

      assert digit3.params.width == 3
      assert digit3.params.chars == digit.params.chars
      assert Atom.match(digit3, "12345") == 3
      assert Atom.match(digit3, "12") == 0
    end

    test "preserves character set from original atom" do
      lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
      lower5 = Atom.with_fixed_width(lower, 5)

      assert Atom.match(lower5, "hello") == 5
      assert Atom.match(lower5, "hell") == 0
      assert Atom.match(lower5, "hel12") == 0
    end

    test "adjusts cost for fixed-width" do
      digit = Atom.char_class("Digit", ~c"0123456789", 8.2)
      digit4 = Atom.with_fixed_width(digit, 4)

      # Fixed-width cost should be base_cost / width
      assert_in_delta Atom.static_cost(digit4), 8.2 / 4, 0.01
    end
  end

  describe "integration with Defaults" do
    test "Digit atom from defaults matches digits" do
      digit = Defaults.get("Digit")

      assert Atom.match(digit, "123abc") == 3
      assert Atom.match(digit, "abc") == 0
    end

    test "Upper atom from defaults matches uppercase" do
      upper = Defaults.get("Upper")

      assert Atom.match(upper, "ABC123") == 3
      assert Atom.match(upper, "abc") == 0
    end

    test "Lower atom from defaults matches lowercase" do
      lower = Defaults.get("Lower")

      assert Atom.match(lower, "abcABC") == 3
      assert Atom.match(lower, "ABC") == 0
    end
  end

  describe "Bin atom" do
    test "matches valid binary characters" do
      atom = Defaults.get("Bin")

      assert Atom.match(atom, "01010") == 5
      assert Atom.match(atom, "11111") == 5
      assert Atom.match(atom, "00000") == 5
    end

    test "stops at non-binary characters" do
      atom = Defaults.get("Bin")

      assert Atom.match(atom, "01012") == 4
      assert Atom.match(atom, "abc") == 0
      assert Atom.match(atom, "2") == 0
    end

    test "returns correct match length" do
      atom = Defaults.get("Bin")

      assert Atom.match(atom, "101abc") == 3
      assert Atom.match(atom, "1") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("Bin")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Hex atom" do
    test "matches valid hexadecimal characters" do
      atom = Defaults.get("Hex")

      assert Atom.match(atom, "deadBEEF123") == 11
      assert Atom.match(atom, "0123456789") == 10
      assert Atom.match(atom, "abcdefABCDEF") == 12
    end

    test "stops at non-hex characters" do
      atom = Defaults.get("Hex")

      assert Atom.match(atom, "abc123xyz") == 6
      assert Atom.match(atom, "xyz") == 0
      assert Atom.match(atom, "g") == 0
    end

    test "returns correct match length" do
      atom = Defaults.get("Hex")

      assert Atom.match(atom, "F00") == 3
      assert Atom.match(atom, "cafe!") == 4
    end

    test "handles empty string" do
      atom = Defaults.get("Hex")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Alpha atom" do
    test "matches valid alphabetic characters" do
      atom = Defaults.get("Alpha")

      assert Atom.match(atom, "ABCabc") == 6
      assert Atom.match(atom, "HelloWorld") == 10
      assert Atom.match(atom, "xyz") == 3
    end

    test "stops at non-alphabetic characters" do
      atom = Defaults.get("Alpha")

      assert Atom.match(atom, "abc123") == 3
      assert Atom.match(atom, "Hello-World") == 5
      assert Atom.match(atom, "test_case") == 4
    end

    test "returns correct match length" do
      atom = Defaults.get("Alpha")

      assert Atom.match(atom, "Test!") == 4
      assert Atom.match(atom, "a") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("Alpha")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "AlphaDigit atom" do
    test "matches valid alphanumeric characters" do
      atom = Defaults.get("AlphaDigit")

      assert Atom.match(atom, "abc123XYZ") == 9
      assert Atom.match(atom, "Test123") == 7
      assert Atom.match(atom, "12345abc") == 8
    end

    test "stops at non-alphanumeric characters" do
      atom = Defaults.get("AlphaDigit")

      assert Atom.match(atom, "abc-123") == 3
      assert Atom.match(atom, "test_case") == 4
      assert Atom.match(atom, "hello world") == 5
    end

    test "returns correct match length" do
      atom = Defaults.get("AlphaDigit")

      assert Atom.match(atom, "a1b2c3!") == 6
      assert Atom.match(atom, "x") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("AlphaDigit")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Space atom" do
    test "matches valid whitespace characters" do
      atom = Defaults.get("Space")

      assert Atom.match(atom, "   ") == 3
      assert Atom.match(atom, "\t\t") == 2
      assert Atom.match(atom, " \t\n") == 3
    end

    test "matches leading spaces and stops at non-space" do
      atom = Defaults.get("Space")

      assert Atom.match(atom, " abc") == 1
      assert Atom.match(atom, "  123") == 2
      assert Atom.match(atom, "\thello") == 1
    end

    test "returns 0 for non-whitespace start" do
      atom = Defaults.get("Space")

      assert Atom.match(atom, "abc") == 0
      assert Atom.match(atom, "123") == 0
    end

    test "handles empty string" do
      atom = Defaults.get("Space")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "AlphaDigitSpace atom" do
    test "matches alphanumeric and whitespace characters" do
      atom = Defaults.get("AlphaDigitSpace")

      assert Atom.match(atom, "abc 123") == 7
      assert Atom.match(atom, "Hello World") == 11
      assert Atom.match(atom, "test\t123") == 8
    end

    test "stops at other characters" do
      atom = Defaults.get("AlphaDigitSpace")

      assert Atom.match(atom, "abc!123") == 3
      assert Atom.match(atom, "hello-world") == 5
      assert Atom.match(atom, "test.case") == 4
    end

    test "returns correct match length" do
      atom = Defaults.get("AlphaDigitSpace")

      assert Atom.match(atom, "a b c-") == 5
      assert Atom.match(atom, " ") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("AlphaDigitSpace")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "DotDash atom" do
    test "matches valid dot and dash characters" do
      atom = Defaults.get("DotDash")

      assert Atom.match(atom, ".-.-") == 4
      assert Atom.match(atom, "...") == 3
      assert Atom.match(atom, "---") == 3
    end

    test "stops at non-dot-dash characters" do
      atom = Defaults.get("DotDash")

      assert Atom.match(atom, ".-a") == 2
      assert Atom.match(atom, ".123") == 1
      assert Atom.match(atom, "-_") == 1
    end

    test "returns correct match length" do
      atom = Defaults.get("DotDash")

      assert Atom.match(atom, "..--") == 4
      assert Atom.match(atom, ".") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("DotDash")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Punct atom" do
    test "matches valid punctuation characters" do
      atom = Defaults.get("Punct")

      assert Atom.match(atom, ".,:?/-") == 6
      assert Atom.match(atom, "...") == 3
      assert Atom.match(atom, ":://") == 4
    end

    test "stops at non-punctuation characters" do
      atom = Defaults.get("Punct")

      assert Atom.match(atom, ".a") == 1
      assert Atom.match(atom, ":123") == 1
      assert Atom.match(atom, ",hello") == 1
    end

    test "returns correct match length" do
      atom = Defaults.get("Punct")

      assert Atom.match(atom, ".,") == 2
      assert Atom.match(atom, "?!") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("Punct")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "AlphaDash atom" do
    test "matches valid alphabetic and dash characters" do
      atom = Defaults.get("AlphaDash")

      assert Atom.match(atom, "abc-def") == 7
      assert Atom.match(atom, "Hello-World") == 11
      assert Atom.match(atom, "test-") == 5
    end

    test "stops at non-alpha-dash characters" do
      atom = Defaults.get("AlphaDash")

      assert Atom.match(atom, "abc_def") == 3
      assert Atom.match(atom, "test123") == 4
      assert Atom.match(atom, "hello world") == 5
    end

    test "returns correct match length" do
      atom = Defaults.get("AlphaDash")

      assert Atom.match(atom, "a-b-c!") == 5
      assert Atom.match(atom, "-") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("AlphaDash")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Symb atom" do
    test "matches valid symbol characters" do
      atom = Defaults.get("Symb")

      assert Atom.match(atom, "-.,://@#") == 8
      assert Atom.match(atom, "$%&*()") == 6
      assert Atom.match(atom, "!~`+=<>?") == 8
    end

    test "stops at non-symbol characters" do
      atom = Defaults.get("Symb")

      assert Atom.match(atom, "-a") == 1
      assert Atom.match(atom, ".123") == 1
      assert Atom.match(atom, "@test") == 1
    end

    test "returns correct match length" do
      atom = Defaults.get("Symb")

      assert Atom.match(atom, "...") == 3
      assert Atom.match(atom, "#") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("Symb")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "AlphaSpace atom" do
    test "matches valid alphabetic and whitespace characters" do
      atom = Defaults.get("AlphaSpace")

      assert Atom.match(atom, "abc def") == 7
      assert Atom.match(atom, "Hello World") == 11
      assert Atom.match(atom, "test\tcase") == 9
    end

    test "stops at non-alpha-space characters" do
      atom = Defaults.get("AlphaSpace")

      assert Atom.match(atom, "abc123") == 3
      assert Atom.match(atom, "hello-world") == 5
      assert Atom.match(atom, "test.case") == 4
    end

    test "returns correct match length" do
      atom = Defaults.get("AlphaSpace")

      assert Atom.match(atom, "a b c-") == 5
      assert Atom.match(atom, " ") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("AlphaSpace")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Base64 atom" do
    test "matches valid Base64 characters" do
      atom = Defaults.get("Base64")

      assert Atom.match(atom, "abc123+=") == 8
      assert Atom.match(atom, "ABC123") == 6
      assert Atom.match(atom, "aGVsbG8=") == 8
    end

    test "stops at non-Base64 characters" do
      atom = Defaults.get("Base64")

      assert Atom.match(atom, "abc!") == 3
      assert Atom.match(atom, "test-case") == 4
      assert Atom.match(atom, "hello world") == 5
    end

    test "returns correct match length" do
      atom = Defaults.get("Base64")

      assert Atom.match(atom, "abc==!") == 5
      assert Atom.match(atom, "+") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("Base64")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "Any atom" do
    test "matches any printable character greedily" do
      atom = Defaults.get("Any")

      assert Atom.match(atom, "abc123") == 6
      assert Atom.match(atom, "Hello, World!") == 13
      assert Atom.match(atom, "test-case_123") == 13
    end

    test "matches all printable ASCII characters" do
      atom = Defaults.get("Any")

      assert Atom.match(atom, "!@#$%^&*()") == 10
      assert Atom.match(atom, "[]{}|\\") == 6
      assert Atom.match(atom, "~`+=<>?") == 7
    end

    test "returns correct match length" do
      atom = Defaults.get("Any")

      assert Atom.match(atom, "x") == 1
      assert Atom.match(atom, " ") == 1
    end

    test "handles empty string" do
      atom = Defaults.get("Any")
      assert Atom.match(atom, "") == 0
    end
  end

  describe "TitleCaseWord atom" do
    test "matches valid title case words" do
      atom = Defaults.get("TitleCaseWord")

      assert Atom.match(atom, "Hello") == 5
      assert Atom.match(atom, "World") == 5
      assert Atom.match(atom, "Test") == 4
    end

    test "does not match all uppercase words" do
      atom = Defaults.get("TitleCaseWord")

      assert Atom.match(atom, "HELLO") == 0
      assert Atom.match(atom, "WORLD") == 0
      assert Atom.match(atom, "ABC") == 0
    end

    test "does not match all lowercase words" do
      atom = Defaults.get("TitleCaseWord")

      assert Atom.match(atom, "hello") == 0
      assert Atom.match(atom, "world") == 0
      assert Atom.match(atom, "test") == 0
    end

    test "stops at mixed case or non-letter" do
      atom = Defaults.get("TitleCaseWord")

      assert Atom.match(atom, "HelloWorld") == 5
      assert Atom.match(atom, "Test123") == 4
      assert Atom.match(atom, "Hello-World") == 5
    end

    test "requires at least one lowercase letter after uppercase" do
      atom = Defaults.get("TitleCaseWord")

      assert Atom.match(atom, "H") == 0
      assert Atom.match(atom, "He") == 2
      assert Atom.match(atom, "Hi!") == 2
    end

    test "handles empty string" do
      atom = Defaults.get("TitleCaseWord")
      assert Atom.match(atom, "") == 0
    end
  end
end
