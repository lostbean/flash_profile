defmodule FlashProfile.PatternSynthesizerTest do
  use ExUnit.Case, async: true

  doctest FlashProfile.PatternSynthesizer

  alias FlashProfile.{Pattern, PatternSynthesizer, Tokenizer}

  describe "Token alignment" do
    test "align_tokens aligns by position" do
      tokens1 = Tokenizer.tokenize("A-1")
      tokens2 = Tokenizer.tokenize("B-2")
      aligned = PatternSynthesizer.align_tokens([tokens1, tokens2])
      assert length(aligned) == 3
    end

    test "align_tokens handles different lengths" do
      tokens1 = Tokenizer.tokenize("A-1")
      tokens2 = Tokenizer.tokenize("B-2-3")
      aligned = PatternSynthesizer.align_tokens([tokens1, tokens2])
      assert length(aligned) == 5
    end
  end

  describe "Enumeration decision" do
    test "should_enumerate true for small sets" do
      assert PatternSynthesizer.should_enumerate?(3, 100, 10) == true
    end

    test "should_enumerate false for large sets" do
      assert PatternSynthesizer.should_enumerate?(50, 100, 10) == false
    end

    test "should_enumerate considers repetition" do
      # 10 distinct in 100 total = high repetition
      assert PatternSynthesizer.should_enumerate?(10, 100, 10) == true
    end
  end

  describe "Pattern synthesis" do
    test "synthesize creates pattern for identical strings" do
      pattern = PatternSynthesizer.synthesize(["ABC", "ABC", "ABC"])
      assert Pattern.matches?(pattern, "ABC")
    end

    test "synthesize enumerates small sets" do
      pattern = PatternSynthesizer.synthesize(["A", "B", "C"])
      regex = Pattern.to_regex(pattern)
      assert String.contains?(regex, "A")
      assert String.contains?(regex, "B")
      assert String.contains?(regex, "C")
    end

    test "synthesize generalizes large sets" do
      data = for i <- 1..100, do: "ID-#{String.pad_leading(Integer.to_string(i), 4, "0")}"
      pattern = PatternSynthesizer.synthesize(data)
      regex = Pattern.to_regex(pattern)
      # Should use \d not enumerate all numbers
      assert String.contains?(regex, "\\d")
    end

    test "synthesize handles delimiter patterns" do
      pattern = PatternSynthesizer.synthesize(["A-B", "C-D", "E-F"])
      # With only 3 values, algorithm enumerates for precision
      # Verify original values match
      assert Pattern.matches?(pattern, "A-B")
      assert Pattern.matches?(pattern, "C-D")
      regex = Pattern.to_regex(pattern)
      assert String.contains?(regex, "-")
    end

    test "synthesize handles mixed lengths" do
      pattern = PatternSynthesizer.synthesize(["A-1", "AA-12", "AAA-123"])
      # Should match all original values
      assert Pattern.matches?(pattern, "A-1")
      assert Pattern.matches?(pattern, "AA-12")
      assert Pattern.matches?(pattern, "AAA-123")
    end
  end

  describe "Pattern optimization" do
    test "optimize_pattern merges adjacent literals" do
      p = {:seq, [{:literal, "a"}, {:literal, "b"}, {:literal, "c"}]}
      optimized = PatternSynthesizer.optimize_pattern(p)
      assert optimized == {:literal, "abc"}
    end

    test "optimize_pattern merges adjacent char classes" do
      p = {:seq, [{:char_class, :digit, 2, 2}, {:char_class, :digit, 3, 3}]}
      optimized = PatternSynthesizer.optimize_pattern(p)
      assert optimized == {:char_class, :digit, 5, 5}
    end
  end

  describe "Evaluation" do
    test "evaluate returns coverage" do
      pattern = Pattern.enum(["A", "B"])
      eval = PatternSynthesizer.evaluate(pattern, ["A", "B", "C"])
      assert eval.coverage < 1.0
      assert eval.coverage > 0.5
    end

    test "evaluate returns matched_count" do
      pattern = Pattern.enum(["A", "B"])
      eval = PatternSynthesizer.evaluate(pattern, ["A", "B", "C"])
      assert eval.matched_count == 2
    end
  end

  describe "Best pattern selection" do
    test "synthesize_best returns pattern and evaluation" do
      {pattern, eval} = PatternSynthesizer.synthesize_best(["A-1", "B-2", "C-3"])
      assert is_tuple(pattern)
      assert is_map(eval)
      assert Map.has_key?(eval, :coverage)
    end
  end
end
