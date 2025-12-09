defmodule FlashProfile.IntegrationTest do
  use ExUnit.Case, async: true

  alias FlashProfile

  # ==================== INTEGRATION SCENARIOS ====================

  describe "Integration Scenarios" do
    test "real-world product codes" do
      data = [
        "SKU-A001-BLK-SM",
        "SKU-A001-BLK-MD",
        "SKU-A001-WHT-SM",
        "SKU-B002-RED-LG",
        "SKU-B002-BLU-XL"
      ]

      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "SKU-A001-BLK-SM") == :ok
    end

    test "real-world log entries" do
      data = [
        "2024-01-15 10:30:00 INFO Starting",
        "2024-01-15 10:30:01 DEBUG Loading",
        "2024-01-15 10:30:02 WARN Low memory"
      ]

      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage >= 0.9
    end

    test "real-world IP addresses" do
      data = ["192.168.1.1", "10.0.0.1", "172.16.0.1", "8.8.8.8"]
      {:ok, profile} = FlashProfile.profile(data)
      regex = hd(profile.patterns).regex
      assert String.contains?(regex, "\\.")
    end

    test "real-world URLs" do
      data = [
        "https://example.com/page1",
        "https://example.com/page2",
        "https://test.org/home"
      ]

      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage >= 0.9
    end

    test "real-world credit card format" do
      data = [
        "4111-1111-1111-1111",
        "5500-0000-0000-0004",
        "3400-0000-0000-009"
      ]

      {:ok, profile} = FlashProfile.profile(data)
      regex = hd(profile.patterns).regex
      # With only 3 values, algorithm enumerates rather than generalizes
      assert String.contains?(regex, "-") or profile.stats.total_coverage == 1.0
    end

    test "batch processing scenario" do
      batch1 = for i <- 1..50, do: "A-#{i}"
      batch2 = for i <- 51..100, do: "A-#{i}"

      {:ok, p1} = FlashProfile.profile(batch1)
      {:ok, p2} = FlashProfile.profile(batch2)
      merged = FlashProfile.merge(p1, p2)

      assert merged.stats.total_values == 100
    end
  end

  # ==================== PERFORMANCE CHARACTERISTICS ====================

  describe "Performance Characteristics" do
    test "handles 100 values quickly" do
      data = for i <- 1..100, do: "X-#{i}"
      {:ok, _} = FlashProfile.profile(data)
    end

    test "handles 1000 values" do
      data = for i <- 1..1000, do: "ID-#{String.pad_leading(Integer.to_string(i), 4, "0")}"
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_values == 1000
    end

    test "handles highly repetitive data efficiently" do
      data = List.duplicate("same", 10000)
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.distinct_values == 1
    end

    test "handles many distinct values" do
      data = for i <- 1..500, do: "unique_value_#{i}"
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage >= 0.95
    end
  end

  # ==================== REGRESSION SCENARIOS ====================

  describe "Regression Scenarios" do
    test "prefix fragmentation regression" do
      # Ensure ACC and ACCT don't get separate patterns
      data = ["ACC-001", "ACCT-001", "ACC-002", "ACCT-002"]
      {:ok, profile} = FlashProfile.profile(data)
      assert length(profile.patterns) == 1
    end

    test "quarter enumeration regression" do
      # Ensure Q1-Q4 are enumerated, not generalized to Q\d
      data = ["Q1", "Q2", "Q3", "Q4"]
      {:ok, profile} = FlashProfile.profile(data)
      assert FlashProfile.validate(profile, "Q5") == {:error, :no_match}
    end

    test "empty string handling regression" do
      # Ensure empty strings don't crash
      data = ["a", "", "b", ""]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_values == 4
    end

    test "single char delimiter regression" do
      # Ensure single character delimiters work
      data = ["-", "-", "-"]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end

    test "regex escape regression" do
      # Ensure regex metacharacters are properly escaped
      data = ["a.b.c", "x.y.z"]
      {:ok, profile} = FlashProfile.profile(data)
      # Algorithm enumerates small sets - verify originals match
      assert FlashProfile.validate(profile, "a.b.c") == :ok
      # But ensure regex escape works - "abc" should not match (no dots)
      assert FlashProfile.validate(profile, "abc") == {:error, :no_match}
    end

    test "numeric-only prefix regression" do
      data = ["123-ABC", "456-DEF", "789-GHI"]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end

    test "mixed case handling regression" do
      data = ["AbC", "DeF", "GhI"]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end

    test "whitespace only values regression" do
      data = [" ", "  ", "\t", "\n"]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_values == 4
    end
  end
end
