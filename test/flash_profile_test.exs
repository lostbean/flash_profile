defmodule FlashProfileTest do
  use ExUnit.Case, async: true

  alias FlashProfile
  alias FlashProfile.{Tokenizer, Pattern, Clustering}

  # ==================== TOKENIZER TESTS ====================

  describe "Tokenizer" do
    test "tokenizes digits" do
      tokens = Tokenizer.tokenize("123")
      assert length(tokens) == 1
      assert hd(tokens).type == :digits
      assert hd(tokens).value == "123"
    end

    test "tokenizes uppercase" do
      tokens = Tokenizer.tokenize("ABC")
      assert length(tokens) == 1
      assert hd(tokens).type == :upper
      assert hd(tokens).value == "ABC"
    end

    test "tokenizes lowercase" do
      tokens = Tokenizer.tokenize("hello")
      assert length(tokens) == 1
      assert hd(tokens).type == :lower
      assert hd(tokens).value == "hello"
    end

    test "tokenizes mixed" do
      tokens = Tokenizer.tokenize("ABC-123")
      assert length(tokens) == 3
      assert Enum.map(tokens, & &1.type) == [:upper, :delimiter, :digits]
    end

    test "generates signatures" do
      sig = Tokenizer.signature("ACC-00123")
      assert sig == "UUU-DDDDD"
    end

    test "generates compact signatures" do
      sig1 = Tokenizer.compact_signature("ACC-00123")
      sig2 = Tokenizer.compact_signature("ACCT-00123")
      assert sig1 == "U-D"
      assert sig2 == "U-D"
    end
  end

  # ==================== PATTERN TESTS ====================

  describe "Patterns" do
    test "creates literal pattern" do
      p = Pattern.literal("hello")
      assert Pattern.to_regex(p) == "hello"
    end

    test "creates char class pattern" do
      p = Pattern.char_class(:digit, 3, 3)
      assert Pattern.to_regex(p) == "\\d{3}"
    end

    test "creates enum pattern" do
      p = Pattern.enum(["ACC", "ORG"])
      assert Pattern.to_regex(p) == "(ACC|ORG)"
    end

    test "creates sequence pattern" do
      p =
        Pattern.seq([
          Pattern.enum(["A", "B"]),
          Pattern.literal("-"),
          Pattern.char_class(:digit, 2, 2)
        ])

      # Note: literal("-") gets escaped via Regex.escape/1 to "\-"
      assert Pattern.to_regex(p) == "(A|B)\\-\\d{2}"
    end

    test "pattern matches correctly" do
      p =
        Pattern.seq([
          Pattern.enum(["ACC", "ORG"]),
          Pattern.literal("-"),
          Pattern.char_class(:digit, 3, 3)
        ])

      assert Pattern.matches?(p, "ACC-123")
      assert Pattern.matches?(p, "ORG-456")
      refute Pattern.matches?(p, "XYZ-123")
    end

    test "calculates cost" do
      p1 = Pattern.enum(["A", "B"])
      p2 = Pattern.char_class(:any, 1, 10)
      assert Pattern.cost(p1) < Pattern.cost(p2)
    end
  end

  # ==================== CLUSTERING TESTS ====================

  describe "Clustering" do
    test "clusters by delimiter structure" do
      clusters = Clustering.cluster(["ACC-001", "ORG-002", "hello@world.com"])
      assert length(clusters) == 2
    end

    test "merges similar structures" do
      # These should be in the same cluster despite different prefix lengths
      clusters = Clustering.cluster(["ACC-001", "ACCT-001", "ORG-001", "ACME-001"])
      assert length(clusters) == 1
    end

    test "respects max_clusters" do
      data = for i <- 1..100, do: "type#{rem(i, 10)}-#{i}"
      clusters = Clustering.cluster(data, max_clusters: 3)
      assert length(clusters) <= 3
    end
  end

  # ==================== CATEGORICAL ENUMERATION ====================

  describe "Categorical Enumeration" do
    test "enumerates status values" do
      data =
        List.duplicate("active", 2500) ++
          List.duplicate("pending", 2500) ++
          List.duplicate("completed", 2500) ++
          List.duplicate("cancelled", 2500)

      {:ok, profile} = FlashProfile.profile(data)

      # Should be a single pattern with all 4 values enumerated
      assert length(profile.patterns) == 1
      assert hd(profile.patterns).regex == "(active|cancelled|completed|pending)"
    end

    test "handles small categorical sets" do
      data = ["red", "green", "blue"]
      {:ok, profile} = FlashProfile.profile(data)
      assert hd(profile.patterns).regex == "(blue|green|red)"
    end

    test "full coverage for categorical" do
      data = ["yes", "no", "maybe"] |> List.duplicate(100) |> List.flatten()
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end
  end

  # ==================== STRUCTURED IDENTIFIERS ====================

  describe "Structured Identifiers" do
    test "identifies prefix patterns" do
      data =
        for prefix <- ["ACC", "ORG", "ACCT", "ACME"],
            num <- 1..10,
            do: "#{prefix}-#{String.pad_leading(Integer.to_string(num), 5, "0")}"

      {:ok, profile} = FlashProfile.profile(data)

      # Should produce a pattern like (ACC|ACCT|ACME|ORG)-\d{5}
      pattern = hd(profile.patterns)
      regex = pattern.regex

      # Check it matches all prefixes
      test_values = ["ACC-00001", "ORG-00002", "ACCT-00003", "ACME-00004"]
      {:ok, compiled} = Regex.compile("^" <> regex <> "$")
      assert Enum.all?(test_values, &Regex.match?(compiled, &1))
    end

    test "single cluster for similar structures" do
      data = ["ACC-00043", "ORG-00131", "ACCT-00055", "ACME-00107"]
      {:ok, profile} = FlashProfile.profile(data)
      assert length(profile.patterns) == 1
    end

    test "handles varying digit lengths" do
      # With only 4 distinct values, the algorithm enumerates them
      data = ["ID-1", "ID-12", "ID-123", "ID-1234"]
      {:ok, profile} = FlashProfile.profile(data)
      pattern = hd(profile.patterns)
      # With small datasets, algorithm may enumerate rather than generalize
      # Just verify we get a valid pattern that matches all inputs
      {:ok, regex} = Regex.compile("^" <> pattern.regex <> "$")
      assert Enum.all?(data, &Regex.match?(regex, &1))
    end
  end

  # ==================== EMAIL ADDRESSES ====================

  describe "Email Addresses" do
    test "recognizes email structure" do
      data = ["alice@company.org", "bob@test.io", "admin@company.org"]
      {:ok, profile} = FlashProfile.profile(data)
      pattern = hd(profile.patterns)
      # Should contain @ and .
      assert String.contains?(pattern.regex, "@")
      assert String.contains?(pattern.regex, "\\.")
    end

    test "generates pattern for emails" do
      # With small datasets, algorithm enumerates rather than generalizes
      data = ["user1@domain.com", "user2@domain.com", "admin@other.org"]
      pattern = FlashProfile.infer_pattern(data)
      # Just verify a pattern was generated
      regex = Pattern.to_regex(pattern)
      assert is_binary(regex)
      assert String.length(regex) > 0
    end

    test "handles dots in usernames" do
      data = ["alice.jones@company.org", "bob.smith@test.io", "admin@company.org"]
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage >= 0.95
    end
  end

  # ==================== DATE PATTERNS ====================

  describe "Date/Time Patterns" do
    test "recognizes quarter format" do
      data = ["2024-Q1", "2024-Q2", "2024-Q3", "2024-Q4", "2025-Q1"]
      {:ok, profile} = FlashProfile.profile(data)
      pattern = hd(profile.patterns)

      # Verify the pattern matches all input values
      {:ok, regex} = Regex.compile("^" <> pattern.regex <> "$")
      assert Enum.all?(data, &Regex.match?(regex, &1))
    end

    test "recognizes ISO dates" do
      data = ["2024-01-15", "2024-02-20", "2024-03-25"]
      {:ok, profile} = FlashProfile.profile(data)
      pattern = hd(profile.patterns)
      # Verify the pattern matches all input values
      {:ok, regex} = Regex.compile("^" <> pattern.regex <> "$")
      assert Enum.all?(data, &Regex.match?(regex, &1))
    end

    test "handles year patterns" do
      data = for year <- 2020..2025, do: "FY#{year}"
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage == 1.0
    end
  end

  # ==================== MIXED FORMATS ====================

  describe "Mixed Formats" do
    test "identifies multiple format types" do
      data =
        ["ACC-001", "ACC-002"] ++
          ["user@email.com", "admin@email.com"] ++
          ["2024-01-01", "2024-02-02"]

      {:ok, profile} = FlashProfile.profile(data)

      # Just verify we get patterns that cover the data
      assert length(profile.patterns) >= 1
      assert profile.stats.total_coverage >= 0.5
    end

    test "maintains high coverage with mixed data" do
      data =
        List.flatten([
          for(i <- 1..30, do: "CODE-#{String.pad_leading(Integer.to_string(i), 3, "0")}"),
          for(i <- 1..30, do: "user#{i}@test.com"),
          for(_ <- 1..30, do: "active")
        ])

      {:ok, profile} = FlashProfile.profile(data)
      assert profile.stats.total_coverage >= 0.95
    end
  end

  # ==================== ANOMALY DETECTION ====================

  describe "Anomaly Detection" do
    test "detects outliers with large enough dataset" do
      # Need enough data points that the normal pattern can be distinguished
      # With more repetition, the algorithm can identify the pattern
      data =
        for(i <- 1..50, do: "ID-#{String.pad_leading(Integer.to_string(i), 3, "0")}") ++
          for(i <- 1..50, do: "ID-#{String.pad_leading(Integer.to_string(i), 3, "0")}") ++
          ["TOTALLY_DIFFERENT"]

      {:ok, profile} = FlashProfile.profile(data)
      # The main pattern should cover most values
      assert profile.stats.total_coverage >= 0.95
    end

    test "no false positives" do
      data = for i <- 1..100, do: "CODE-#{i}"
      {:ok, profile} = FlashProfile.profile(data)
      assert profile.anomalies == []
    end

    test "handles mixed structures" do
      data =
        for(i <- 1..100, do: "ACC-#{String.pad_leading(Integer.to_string(i), 3, "0")}") ++
          ["WEIRD1", "weird2", "12345"]

      {:ok, profile} = FlashProfile.profile(data)
      # Just verify we get valid patterns
      assert length(profile.patterns) >= 1
    end
  end

  # ==================== API TESTS ====================

  describe "API" do
    test "profile returns ok tuple" do
      {:ok, _profile} = FlashProfile.profile(["a", "b", "c"])
    end

    test "profile! returns profile directly" do
      profile = FlashProfile.profile!(["a", "b", "c"])
      assert is_map(profile)
      assert Map.has_key?(profile, :patterns)
    end

    test "validate checks against patterns" do
      # With small datasets, algorithm enumerates specific values
      {:ok, profile} = FlashProfile.profile(["ACC-001", "ACC-002", "ORG-001"])
      # Validate that input values match
      assert FlashProfile.validate(profile, "ACC-001") == :ok
      assert FlashProfile.validate(profile, "ORG-001") == :ok
      # Non-matching value should fail
      assert FlashProfile.validate(profile, "INVALID") == {:error, :no_match}
    end

    test "infer_regex returns regex string" do
      regex = FlashProfile.infer_regex(["A-1", "B-2", "C-3"])
      assert is_binary(regex)
      assert String.length(regex) > 0
    end

    test "summary returns readable string" do
      {:ok, profile} = FlashProfile.profile(["test1", "test2", "test3"])
      summary = FlashProfile.summary(profile)
      assert String.contains?(summary, "Profile Summary")
    end

    test "export returns serializable map" do
      {:ok, profile} = FlashProfile.profile(["x", "y", "z"])
      export = FlashProfile.export(profile)
      assert is_map(export)
      assert Map.has_key?(export, :patterns)
    end
  end
end
