defmodule FlashProfile.PatternTest do
  use ExUnit.Case, async: true

  alias FlashProfile.Pattern

  describe "Constructors" do
    test "literal creates literal pattern" do
      p = Pattern.literal("hello")
      assert p == {:literal, "hello"}
    end

    test "char_class creates char_class pattern" do
      p = Pattern.char_class(:digit, 2, 5)
      assert p == {:char_class, :digit, 2, 5}
    end

    test "char_class defaults to {1,1}" do
      p = Pattern.char_class(:digit)
      assert p == {:char_class, :digit, 1, 1}
    end

    test "enum creates sorted unique enum" do
      p = Pattern.enum(["C", "A", "B", "A"])
      assert p == {:enum, ["A", "B", "C"]}
    end

    test "seq unwraps single element" do
      p = Pattern.seq([Pattern.literal("x")])
      assert p == {:literal, "x"}
    end

    test "seq wraps multiple elements" do
      p = Pattern.seq([Pattern.literal("a"), Pattern.literal("b")])
      assert p == {:seq, [{:literal, "a"}, {:literal, "b"}]}
    end

    test "optional wraps pattern" do
      p = Pattern.optional(Pattern.literal("x"))
      assert p == {:optional, {:literal, "x"}}
    end

    test "any creates any pattern" do
      p = Pattern.any(1, 10)
      assert p == {:any, 1, 10}
    end
  end

  describe "Regex generation - literals" do
    test "to_regex escapes special chars in literal" do
      assert Pattern.to_regex({:literal, "a.b*c"}) == "a\\.b\\*c"
    end

    test "to_regex handles plain literal" do
      assert Pattern.to_regex({:literal, "hello"}) == "hello"
    end
  end

  describe "Regex generation - char classes" do
    test "to_regex digit class" do
      assert Pattern.to_regex({:char_class, :digit, 1, 1}) == "\\d"
    end

    test "to_regex upper class" do
      assert Pattern.to_regex({:char_class, :upper, 1, 1}) == "[A-Z]"
    end

    test "to_regex lower class" do
      assert Pattern.to_regex({:char_class, :lower, 1, 1}) == "[a-z]"
    end

    test "to_regex alpha class" do
      assert Pattern.to_regex({:char_class, :alpha, 1, 1}) == "[a-zA-Z]"
    end

    test "to_regex alnum class" do
      assert Pattern.to_regex({:char_class, :alnum, 1, 1}) == "[a-zA-Z0-9]"
    end

    test "to_regex word class" do
      assert Pattern.to_regex({:char_class, :word, 1, 1}) == "\\w"
    end
  end

  describe "Quantifiers" do
    test "quantifier {n} for fixed length" do
      assert Pattern.to_regex({:char_class, :digit, 3, 3}) == "\\d{3}"
    end

    test "quantifier {n,} for min only" do
      assert Pattern.to_regex({:char_class, :digit, 2, :inf}) == "\\d{2,}"
    end

    test "quantifier {n,m} for range" do
      assert Pattern.to_regex({:char_class, :digit, 2, 5}) == "\\d{2,5}"
    end

    test "quantifier + for {1,inf}" do
      assert Pattern.to_regex({:char_class, :digit, 1, :inf}) == "\\d+"
    end

    test "quantifier * for {0,inf}" do
      assert Pattern.to_regex({:char_class, :digit, 0, :inf}) == "\\d*"
    end

    test "quantifier ? for {0,1}" do
      assert Pattern.to_regex({:char_class, :digit, 0, 1}) == "\\d?"
    end
  end

  describe "Enums" do
    test "to_regex single enum value (no parens)" do
      assert Pattern.to_regex({:enum, ["only"]}) == "only"
    end

    test "to_regex multiple enum values" do
      assert Pattern.to_regex({:enum, ["A", "B", "C"]}) == "(A|B|C)"
    end

    test "to_regex escapes enum values" do
      assert Pattern.to_regex({:enum, ["a.b", "c*d"]}) == "(a\\.b|c\\*d)"
    end
  end

  describe "Sequences" do
    test "to_regex concatenates sequence" do
      p = {:seq, [{:literal, "X"}, {:char_class, :digit, 2, 2}]}
      assert Pattern.to_regex(p) == "X\\d{2}"
    end
  end

  describe "Optional" do
    test "to_regex optional simple" do
      assert Pattern.to_regex({:optional, {:literal, "x"}}) == "x?"
    end

    test "to_regex optional groups complex" do
      p = {:optional, {:seq, [{:literal, "a"}, {:literal, "b"}]}}
      assert Pattern.to_regex(p) == "(ab)?"
    end
  end

  describe "Any" do
    test "to_regex any with quantifier" do
      assert Pattern.to_regex({:any, 1, 5}) == ".{1,5}"
    end
  end

  describe "Pattern matching" do
    test "matches? returns true for match" do
      p =
        Pattern.seq([
          Pattern.enum(["A", "B"]),
          Pattern.literal("-"),
          Pattern.char_class(:digit, 2, 2)
        ])

      assert Pattern.matches?(p, "A-12")
    end

    test "matches? returns false for no match" do
      p =
        Pattern.seq([
          Pattern.enum(["A", "B"]),
          Pattern.literal("-"),
          Pattern.char_class(:digit, 2, 2)
        ])

      refute Pattern.matches?(p, "C-12")
    end

    test "matches? requires full string match" do
      p = Pattern.literal("abc")
      assert Pattern.matches?(p, "abc")
      refute Pattern.matches?(p, "abcd")
      refute Pattern.matches?(p, "xabc")
    end
  end

  describe "Cost calculation" do
    test "cost increases with enum size" do
      c1 = Pattern.cost({:enum, ["A", "B"]})
      c2 = Pattern.cost({:enum, ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]})
      assert c2 > c1
    end

    test "cost prefers specific over general" do
      c1 = Pattern.cost({:char_class, :digit, 3, 3})
      c2 = Pattern.cost({:any, 1, 10})
      assert c1 < c2
    end

    test "cost sums sequence elements" do
      c1 = Pattern.cost({:literal, "a"})
      c2 = Pattern.cost({:literal, "b"})
      c_seq = Pattern.cost({:seq, [{:literal, "a"}, {:literal, "b"}]})
      assert abs(c_seq - (c1 + c2)) < 0.01
    end
  end

  describe "Specificity" do
    test "specificity highest for literal" do
      assert Pattern.specificity({:literal, "x"}) == 1.0
    end

    test "specificity lowest for any" do
      assert Pattern.specificity({:any, 1, 10}) == 0.1
    end

    test "specificity high for small enum" do
      assert Pattern.specificity({:enum, ["A", "B"]}) >= 0.9
    end
  end

  describe "Pretty printing" do
    test "pretty prints literal" do
      assert Pattern.pretty({:literal, "hello"}) == "\"hello\""
    end

    test "pretty prints char class" do
      p = Pattern.pretty({:char_class, :digit, 3, 3})
      assert String.contains?(p, "digit")
      assert String.contains?(p, "3")
    end

    test "pretty prints small enum" do
      p = Pattern.pretty({:enum, ["A", "B", "C"]})
      assert p == "{A|B|C}"
    end

    test "pretty truncates large enum" do
      p = Pattern.pretty({:enum, Enum.map(1..20, &Integer.to_string/1)})
      assert String.contains?(p, "...")
      assert String.contains?(p, "20 values")
    end
  end
end
