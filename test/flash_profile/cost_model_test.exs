defmodule FlashProfile.CostModelTest do
  use ExUnit.Case, async: true

  alias FlashProfile.{Pattern, CostModel}

  describe "Coverage" do
    test "calculate_coverage returns 1.0 for full match" do
      pattern = Pattern.enum(["A", "B", "C"])
      assert CostModel.calculate_coverage(pattern, ["A", "B", "C"]) == 1.0
    end

    test "calculate_coverage returns 0.0 for no match" do
      pattern = Pattern.enum(["A", "B"])
      assert CostModel.calculate_coverage(pattern, ["X", "Y", "Z"]) == 0.0
    end

    test "calculate_coverage returns partial" do
      pattern = Pattern.enum(["A", "B"])
      coverage = CostModel.calculate_coverage(pattern, ["A", "B", "C", "D"])
      assert coverage == 0.5
    end

    test "calculate_coverage handles empty list" do
      pattern = Pattern.literal("X")
      assert CostModel.calculate_coverage(pattern, []) == 0.0
    end
  end

  describe "Precision estimation" do
    test "estimate_precision high for specific patterns" do
      pattern = Pattern.enum(["A", "B"])
      assert CostModel.estimate_precision(pattern, ["A", "B"], []) >= 0.8
    end

    test "estimate_precision uses invalid samples" do
      pattern = Pattern.char_class(:upper, 1, 1)
      # Pattern matches both valid and invalid
      prec = CostModel.estimate_precision(pattern, ["A", "B"], ["X", "Y"])
      assert prec <= 1.0
    end
  end

  describe "Complexity" do
    test "calculate_complexity returns 0-1 range" do
      pattern = Pattern.literal("test")
      c = CostModel.calculate_complexity(pattern)
      assert c >= 0.0
      assert c <= 1.0
    end

    test "calculate_complexity higher for complex patterns" do
      simple = Pattern.literal("a")

      complex =
        Pattern.seq([
          Pattern.enum(Enum.map(1..20, &Integer.to_string/1)),
          Pattern.char_class(:alnum, 1, 100),
          Pattern.any(1, 50)
        ])

      assert CostModel.calculate_complexity(simple) < CostModel.calculate_complexity(complex)
    end
  end

  describe "Interpretability" do
    test "calculate_interpretability high for simple patterns" do
      pattern = Pattern.seq([Pattern.literal("X"), Pattern.char_class(:digit, 3, 3)])
      assert CostModel.calculate_interpretability(pattern) >= 0.8
    end

    test "calculate_interpretability lower for large enums" do
      pattern = Pattern.enum(Enum.map(1..50, &Integer.to_string/1))
      assert CostModel.calculate_interpretability(pattern) < 0.5
    end
  end

  describe "Overall score" do
    test "score combines all factors" do
      pattern = Pattern.enum(["A", "B"])
      s = CostModel.score(pattern, ["A", "B", "C"])
      assert is_float(s)
    end

    test "score lower is better" do
      good = Pattern.enum(["A", "B", "C"])
      bad = Pattern.any(1, 10)
      assert CostModel.score(good, ["A", "B", "C"]) < CostModel.score(bad, ["A", "B", "C"])
    end
  end

  describe "Comparison" do
    test "compare identifies better pattern" do
      p1 = Pattern.enum(["A", "B"])
      p2 = Pattern.any(1, 5)
      assert {:first, _} = CostModel.compare(p1, p2, ["A", "B"])
    end
  end

  describe "Ranking" do
    test "rank orders patterns by score" do
      patterns = [
        Pattern.any(1, 10),
        Pattern.enum(["A", "B"]),
        Pattern.char_class(:upper, 1, 1)
      ]

      ranked = CostModel.rank(patterns, ["A", "B"])
      {first, _} = hd(ranked)
      # Best pattern should be first
      assert first == Pattern.enum(["A", "B"])
    end
  end

  describe "Evaluation report" do
    test "evaluate returns comprehensive report" do
      pattern = Pattern.enum(["A", "B"])
      report = CostModel.evaluate(pattern, ["A", "B", "C"])
      assert Map.has_key?(report, :metrics)
      assert Map.has_key?(report, :stats)
      assert Map.has_key?(report.metrics, :coverage)
      assert Map.has_key?(report.stats, :unmatched_sample)
    end
  end

  describe "Threshold suggestion" do
    test "suggest_enum_threshold for categorical data" do
      values =
        List.duplicate("A", 100) ++ List.duplicate("B", 100) ++ List.duplicate("C", 100)

      threshold = CostModel.suggest_enum_threshold(values)
      assert threshold >= 3
      assert threshold <= 15
    end

    test "suggest_enum_threshold for high cardinality" do
      values = for i <- 1..1000, do: "ID-#{i}"
      threshold = CostModel.suggest_enum_threshold(values)
      assert threshold <= 5
    end
  end
end
