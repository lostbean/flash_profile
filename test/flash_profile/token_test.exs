defmodule FlashProfile.TokenTest do
  use ExUnit.Case, async: true

  alias FlashProfile.Token

  describe "Token creation" do
    test "creates token with all fields" do
      t = Token.new(:digits, "123", 5)
      assert t.type == :digits
      assert t.value == "123"
      assert t.length == 3
      assert t.position == 5
    end

    test "defaults position to 0" do
      t = Token.new(:upper, "ABC")
      assert t.position == 0
    end

    test "calculates length from value" do
      t = Token.new(:lower, "hello")
      assert t.length == 5
    end
  end

  describe "Signature characters" do
    test "signature_char for digits" do
      assert Token.signature_char(Token.new(:digits, "1")) == "D"
    end

    test "signature_char for upper" do
      assert Token.signature_char(Token.new(:upper, "A")) == "U"
    end

    test "signature_char for lower" do
      assert Token.signature_char(Token.new(:lower, "a")) == "L"
    end

    test "signature_char for alpha" do
      assert Token.signature_char(Token.new(:alpha, "Aa")) == "A"
    end

    test "signature_char for alnum" do
      assert Token.signature_char(Token.new(:alnum, "A1")) == "X"
    end

    test "signature_char for whitespace" do
      assert Token.signature_char(Token.new(:whitespace, " ")) == "_"
    end

    test "signature_char for delimiter returns value" do
      assert Token.signature_char(Token.new(:delimiter, "-")) == "-"
    end

    test "signature_char for literal returns value" do
      assert Token.signature_char(Token.new(:literal, "©")) == "©"
    end
  end

  describe "Full signatures" do
    test "signature expands for length > 1" do
      assert Token.signature(Token.new(:digits, "123")) == "DDD"
    end

    test "signature keeps delimiter value" do
      assert Token.signature(Token.new(:delimiter, "-")) == "-"
    end
  end

  describe "Compatibility" do
    test "same types are compatible" do
      assert Token.compatible?(Token.new(:digits, "1"), Token.new(:digits, "2"))
    end

    test "upper and lower are compatible" do
      assert Token.compatible?(Token.new(:upper, "A"), Token.new(:lower, "a"))
    end

    test "alpha compatible with upper" do
      assert Token.compatible?(Token.new(:alpha, "Aa"), Token.new(:upper, "B"))
    end

    test "digits and upper not compatible" do
      refute Token.compatible?(Token.new(:digits, "1"), Token.new(:upper, "A"))
    end
  end
end
