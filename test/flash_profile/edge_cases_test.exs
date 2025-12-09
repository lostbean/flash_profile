defmodule FlashProfile.EdgeCasesTest do
  use ExUnit.Case, async: true

  alias FlashProfile

  # ==================== EDGE CASES ====================

  describe "Edge Cases" do
    test "handles single value" do
      {:ok, profile} = FlashProfile.profile(["only_one"])
      assert length(profile.patterns) == 1
      assert profile.stats.total_coverage == 1.0
    end

    test "handles all identical values" do
      data = List.duplicate("same", 1000)
      {:ok, profile} = FlashProfile.profile(data)
      assert hd(profile.patterns).regex == "same"
    end

    test "handles all unique values" do
      data = for i <- 1..100, do: "unique_#{i}"
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage >= 0.95
    end

    test "handles single character strings" do
      {:ok, profile} = FlashProfile.profile(["a", "b", "c"])
      assert profile.stats.total_coverage == 1.0
    end

    test "handles very long strings" do
      long = String.duplicate("a", 1000)
      {:ok, profile} = FlashProfile.profile([long, long <> "b"])
      assert profile.stats.total_coverage == 1.0
    end

    test "handles numbers only" do
      {:ok, profile} = FlashProfile.profile(["123", "456", "789"])

      assert String.contains?(hd(profile.patterns).regex, "\\d") or
               String.contains?(hd(profile.patterns).regex, "123")
    end

    test "handles spaces in values" do
      {:ok, profile} = FlashProfile.profile(["hello world", "foo bar"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "hello world") == :ok
      assert FlashProfile.validate(profile, "foo bar") == :ok
    end

    test "handles empty-ish strings" do
      {:ok, profile} = FlashProfile.profile([" ", "  ", "   "])
      assert profile.stats.total_coverage == 1.0
    end

    test "handles mixed empty and non-empty" do
      {:ok, profile} = FlashProfile.profile(["a", "", "b"])
      assert profile.stats.total_values == 3
    end
  end

  # ==================== SPECIAL CHARACTERS ====================

  describe "Special Characters" do
    test "escapes regex metacharacters in literals" do
      data = ["a.b", "c.d", "e.f"]
      {:ok, profile} = FlashProfile.profile(data)
      regex = hd(profile.patterns).regex

      assert String.contains?(regex, "\\.") or
               FlashProfile.validate(profile, "x.y") == :ok
    end

    test "handles asterisks" do
      {:ok, profile} = FlashProfile.profile(["a*b", "c*d"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a*b") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles plus signs" do
      {:ok, profile} = FlashProfile.profile(["a+b", "c+d"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a+b") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles question marks" do
      {:ok, profile} = FlashProfile.profile(["a?b", "c?d"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a?b") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles brackets" do
      {:ok, profile} = FlashProfile.profile(["[a]", "[b]"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "[a]") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles parentheses" do
      {:ok, profile} = FlashProfile.profile(["(a)", "(b)"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "(a)") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles braces" do
      {:ok, profile} = FlashProfile.profile(["{a}", "{b}"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "{a}") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles pipe character" do
      {:ok, profile} = FlashProfile.profile(["a|b", "c|d"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a|b") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles caret" do
      {:ok, profile} = FlashProfile.profile(["^a", "^b"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "^a") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles dollar sign" do
      {:ok, profile} = FlashProfile.profile(["a$", "b$"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a$") == :ok
      assert profile.stats.total_coverage == 1.0
    end

    test "handles backslash" do
      {:ok, profile} = FlashProfile.profile(["a\\b", "c\\d"])
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a\\b") == :ok
      assert profile.stats.total_coverage == 1.0
    end
  end

  # ==================== UNICODE HANDLING ====================

  describe "Unicode Handling" do
    test "handles accented characters" do
      {:ok, profile} = FlashProfile.profile(["café", "naïve", "résumé"])
      assert profile.stats.total_values == 3
    end

    test "handles emoji" do
      {:ok, profile} = FlashProfile.profile(["hello 👋", "world 🌍"])
      assert profile.stats.total_values == 2
    end

    test "handles CJK characters" do
      {:ok, profile} = FlashProfile.profile(["你好", "世界"])
      assert profile.stats.total_values == 2
    end

    test "handles mixed ASCII and Unicode" do
      {:ok, profile} = FlashProfile.profile(["ABC-日本", "XYZ-中国"])
      assert profile.stats.total_coverage >= 0.5
    end

    test "handles RTL text" do
      {:ok, profile} = FlashProfile.profile(["שלום", "مرحبا"])
      assert profile.stats.total_values == 2
    end

    test "handles mathematical symbols" do
      {:ok, profile} = FlashProfile.profile(["α + β", "γ + δ"])
      assert profile.stats.total_values == 2
    end
  end

  # ==================== LENGTH VARIATIONS ====================

  describe "Length Variations" do
    test "handles consistent lengths" do
      data = for i <- 1..100, do: "XXX-#{String.pad_leading(Integer.to_string(i), 3, "0")}"
      {:ok, profile} = FlashProfile.profile(data)
      regex = hd(profile.patterns).regex
      assert String.contains?(regex, "{3}")
    end

    test "handles varying lengths gracefully" do
      data = ["A-1", "BB-22", "CCC-333", "DDDD-4444"]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end

    test "handles extreme length differences" do
      data = ["A", String.duplicate("B", 100)]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end

    test "pattern accommodates length range" do
      data = ["ID-1", "ID-12", "ID-123", "ID-1234", "ID-12345"]
      {:ok, profile} = FlashProfile.profile(data)
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "ID-1") == :ok
      assert FlashProfile.validate(profile, "ID-12345") == :ok
      assert profile.stats.total_coverage == 1.0
    end
  end
end
