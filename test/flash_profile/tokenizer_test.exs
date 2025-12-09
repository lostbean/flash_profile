defmodule FlashProfile.TokenizerTest do
  use ExUnit.Case, async: true

  alias FlashProfile.Tokenizer

  describe "Basic tokenization" do
    test "tokenizes empty string" do
      assert Tokenizer.tokenize("") == []
    end

    test "tokenizes single digit" do
      tokens = Tokenizer.tokenize("5")
      assert length(tokens) == 1
      assert hd(tokens).type == :digits
    end

    test "tokenizes consecutive digits" do
      tokens = Tokenizer.tokenize("12345")
      assert length(tokens) == 1
      assert hd(tokens).value == "12345"
    end

    test "tokenizes uppercase letters" do
      tokens = Tokenizer.tokenize("ABC")
      assert length(tokens) == 1
      assert hd(tokens).type == :upper
    end

    test "tokenizes lowercase letters" do
      tokens = Tokenizer.tokenize("abc")
      assert length(tokens) == 1
      assert hd(tokens).type == :lower
    end

    test "tokenizes mixed case separately" do
      tokens = Tokenizer.tokenize("ABCdef")
      assert length(tokens) == 2
      assert Enum.at(tokens, 0).type == :upper
      assert Enum.at(tokens, 1).type == :lower
    end
  end

  describe "Delimiters" do
    test "tokenizes single delimiter" do
      tokens = Tokenizer.tokenize("-")
      assert length(tokens) == 1
      assert hd(tokens).type == :delimiter
    end

    test "tokenizes multiple different delimiters separately" do
      tokens = Tokenizer.tokenize("-_.")
      assert length(tokens) == 3
      assert Enum.all?(tokens, &(&1.type == :delimiter))
    end

    test "recognizes common delimiters" do
      delimiters = "-_./\\@#$%^&*()+=[]{}|;:'\",<>?!`~"
      tokens = Tokenizer.tokenize(delimiters)
      assert Enum.all?(tokens, &(&1.type == :delimiter))
    end
  end

  describe "Whitespace" do
    test "tokenizes single space" do
      tokens = Tokenizer.tokenize(" ")
      assert length(tokens) == 1
      assert hd(tokens).type == :whitespace
    end

    test "groups consecutive whitespace" do
      tokens = Tokenizer.tokenize("   ")
      assert length(tokens) == 1
      assert hd(tokens).length == 3
    end

    test "handles tabs" do
      tokens = Tokenizer.tokenize("\t")
      assert length(tokens) == 1
      assert hd(tokens).type == :whitespace
    end

    test "handles newlines" do
      tokens = Tokenizer.tokenize("\n")
      assert length(tokens) == 1
      assert hd(tokens).type == :whitespace
    end
  end

  describe "Complex strings" do
    test "tokenizes ACC-123 correctly" do
      tokens = Tokenizer.tokenize("ACC-123")
      types = Enum.map(tokens, & &1.type)
      assert types == [:upper, :delimiter, :digits]
    end

    test "tokenizes email correctly" do
      tokens = Tokenizer.tokenize("user@domain.com")
      types = Enum.map(tokens, & &1.type)
      assert types == [:lower, :delimiter, :lower, :delimiter, :lower]
    end

    test "tokenizes date correctly" do
      tokens = Tokenizer.tokenize("2024-01-15")
      types = Enum.map(tokens, & &1.type)
      assert types == [:digits, :delimiter, :digits, :delimiter, :digits]
    end
  end

  describe "Positions" do
    test "tracks token positions" do
      tokens = Tokenizer.tokenize("AB-12")
      positions = Enum.map(tokens, & &1.position)
      assert positions == [0, 2, 3]
    end
  end

  describe "Signatures" do
    test "signature for simple string" do
      assert Tokenizer.signature("ABC") == "UUU"
    end

    test "signature for complex string" do
      assert Tokenizer.signature("ABC-123") == "UUU-DDD"
    end

    test "compact_signature collapses repeats" do
      assert Tokenizer.compact_signature("ABCDEF-123456") == "U-D"
    end

    test "compact_signature preserves delimiters" do
      assert Tokenizer.compact_signature("A-B.C") == "U-U.U"
    end
  end

  describe "Options" do
    test "merge_alpha combines upper and lower" do
      tokens = Tokenizer.tokenize("ABCdef", merge_alpha: true)
      assert length(tokens) == 1
      assert hd(tokens).type == :alpha
    end

    test "merge_alpha preserves non-alpha" do
      tokens = Tokenizer.tokenize("ABC-def", merge_alpha: true)
      assert length(tokens) == 3
    end
  end

  describe "Tokenize with positions" do
    test "tokenize_with_positions returns ranges" do
      result = Tokenizer.tokenize_with_positions("AB-12")
      [{t1, {0, 2}}, {t2, {2, 3}}, {t3, {3, 5}}] = result
      assert t1.value == "AB"
      assert t2.value == "-"
      assert t3.value == "12"
    end
  end
end
