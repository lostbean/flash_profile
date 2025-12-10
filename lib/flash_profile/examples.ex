defmodule FlashProfile.Examples do
  @moduledoc """
  Interactive examples demonstrating FlashProfile capabilities.

  This module provides 8 comprehensive examples covering:

  1. **Categorical Enumeration** - Status columns with few distinct values
  2. **Structured Identifiers** - Account codes with prefix enumeration
  3. **Email Addresses** - Variable-length token patterns
  4. **Date/Time Patterns** - Fiscal quarters and ISO dates
  5. **Mixed Formats** - Multiple legitimate formats in one column
  6. **Anomaly Detection** - Identifying outliers in data
  7. **Pattern Building API** - Programmatic pattern construction
  8. **Tokenization** - Understanding string structure analysis

  ## Running Examples

  From the project directory:

      mix run -e "FlashProfile.Examples.run_all()"

  Or run individual examples:

      mix run -e "FlashProfile.Examples.example_categorical()"

  ## Example Output

  Each example prints formatted output showing:
  - Input data description
  - Discovered patterns with regex and coverage
  - Validation results where applicable
  """

  alias FlashProfile.{Pattern, Tokenizer}

  @doc """
  Runs all FlashProfile examples sequentially.

  Demonstrates the library's full capabilities through 8 scenarios.
  Prints formatted output to stdout.
  """
  @spec run_all() :: :ok
  def run_all do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("  FlashProfile Examples")
    IO.puts(String.duplicate("═", 70))

    example_categorical()
    example_structured_ids()
    example_emails()
    example_dates()
    example_mixed_formats()
    example_anomaly_detection()
    example_pattern_building()
    example_tokenization()

    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("  All examples completed!")
    IO.puts(String.duplicate("═", 70) <> "\n")
  end

  # ============================================================
  # Example 1: Categorical Enumeration
  # ============================================================

  @doc """
  Demonstrates categorical enumeration for status columns.

  Shows how FlashProfile enumerates all distinct values when there are
  few unique values with high repetition (typical status/state columns).
  """
  @spec example_categorical() :: :ok
  def example_categorical do
    header("1. Categorical Enumeration")

    IO.puts("Input: Status column with 4 distinct values, 10,000 total rows")
    IO.puts("")

    data =
      List.duplicate("active", 2500) ++
        List.duplicate("pending", 2500) ++
        List.duplicate("completed", 2500) ++
        List.duplicate("cancelled", 2500)

    {:ok, profile} = FlashProfile.profile(data)

    IO.puts("Discovered pattern:")
    IO.puts("  Regex: #{hd(profile.patterns).regex}")
    IO.puts("  Coverage: #{Float.round(hd(profile.patterns).coverage * 100, 1)}%")
    IO.puts("")
    IO.puts("✓ Enumerates exact values - 100% precise")
    IO.puts("✓ Would NOT match invalid values like 'inactive' or 'done'")
  end

  # ============================================================
  # Example 2: Structured Identifiers with Prefix Enumeration
  # ============================================================

  @doc """
  Demonstrates hybrid patterns for structured identifiers.

  Shows how FlashProfile enumerates a small set of prefixes while
  generalizing the numeric suffix - producing patterns like `(ACC|ORG)-\\d{5}`.
  """
  @spec example_structured_ids() :: :ok
  def example_structured_ids do
    header("2. Structured Identifiers with Prefix Enumeration")

    IO.puts("Input: Account references with 4 known prefixes")
    IO.puts("")

    data =
      for prefix <- ["ACC", "ORG", "ACCT", "ACME"],
          num <- 1..20 do
        "#{prefix}-#{String.pad_leading(Integer.to_string(num), 5, "0")}"
      end

    IO.puts("Sample values: #{Enum.take(data, 4) |> Enum.join(", ")}")
    IO.puts("")

    {:ok, profile} = FlashProfile.profile(data)

    IO.puts("Discovered pattern:")
    IO.puts("  Regex: #{hd(profile.patterns).regex}")
    IO.puts("  Coverage: #{Float.round(hd(profile.patterns).coverage * 100, 1)}%")
    IO.puts("")
    IO.puts("✓ Enumerates the valid prefixes (ACC|ACCT|ACME|ORG)")
    IO.puts("✓ Generalizes the numeric suffix (\\d{5})")
    IO.puts("✓ Single unified pattern - no fragmentation!")
  end

  # ============================================================
  # Example 3: Email Addresses
  # ============================================================

  @doc """
  Demonstrates pattern discovery for email addresses.

  Shows how FlashProfile handles variable-length tokens and
  produces patterns with character class repetition bounds.
  """
  @spec example_emails() :: :ok
  def example_emails do
    header("3. Email Addresses")

    IO.puts("Input: Email addresses with variable-length tokens")
    IO.puts("")

    data = [
      "alice.jones@company.org",
      "bob@test.io",
      "admin@company.org",
      "support.team@example.com",
      "info@startup.io"
    ]

    IO.puts("Values: #{Enum.join(data, ", ")}")
    IO.puts("")

    {:ok, profile} = FlashProfile.profile(data)

    IO.puts("Discovered pattern:")
    IO.puts("  Regex: #{hd(profile.patterns).regex}")
    IO.puts("  Pretty: #{hd(profile.patterns).pretty}")
    IO.puts("  Coverage: #{Float.round(hd(profile.patterns).coverage * 100, 1)}%")
    IO.puts("")

    # Test validation
    valid = "new.user@domain.net"
    invalid = "not-an-email"
    IO.puts("Validation tests:")
    IO.puts("  '#{valid}' → #{inspect(FlashProfile.validate(profile, valid))}")
    IO.puts("  '#{invalid}' → #{inspect(FlashProfile.validate(profile, invalid))}")
  end

  # ============================================================
  # Example 4: Date/Time Patterns
  # ============================================================

  @doc """
  Demonstrates pattern discovery for date and time formats.

  Shows handling of fiscal quarters (enumerated) and ISO dates (generalized).
  """
  @spec example_dates() :: :ok
  def example_dates do
    header("4. Date/Time Patterns")

    IO.puts("Input: Fiscal quarters")
    IO.puts("")

    data = ["2024-Q1", "2024-Q2", "2024-Q3", "2024-Q4", "2025-Q1", "2025-Q2"]

    IO.puts("Values: #{Enum.join(data, ", ")}")
    IO.puts("")

    {:ok, profile} = FlashProfile.profile(data)

    IO.puts("Discovered pattern:")
    IO.puts("  Regex: #{hd(profile.patterns).regex}")
    IO.puts("  Coverage: #{Float.round(hd(profile.patterns).coverage * 100, 1)}%")
    IO.puts("")
    IO.puts("✓ Enumerates valid quarters (Q1|Q2|Q3|Q4)")
    IO.puts("✓ Would NOT match invalid 'Q5' or 'Q9'")

    # ISO dates example
    IO.puts("\n--- ISO Dates ---")
    iso_data = ["2024-01-15", "2024-02-20", "2024-03-25", "2024-04-30"]
    {:ok, iso_profile} = FlashProfile.profile(iso_data)
    IO.puts("Values: #{Enum.join(iso_data, ", ")}")
    IO.puts("Regex: #{hd(iso_profile.patterns).regex}")
  end

  # ============================================================
  # Example 5: Mixed Formats
  # ============================================================

  @doc """
  Demonstrates multi-format column handling.

  Shows how FlashProfile discovers multiple patterns when a column
  contains legitimately different formats (e.g., codes, emails, statuses).
  """
  @spec example_mixed_formats() :: :ok
  def example_mixed_formats do
    header("5. Multi-Format Columns")

    IO.puts("Input: Column with multiple legitimate formats")
    IO.puts("")

    data =
      for(i <- 1..20, do: "CODE-#{String.pad_leading(Integer.to_string(i), 3, "0")}") ++
        for(i <- 1..20, do: "user#{i}@test.com") ++
        ["active", "pending", "completed"]

    IO.puts("Formats present:")
    IO.puts("  - Product codes: CODE-001, CODE-002, ...")
    IO.puts("  - Emails: user1@test.com, user2@test.com, ...")
    IO.puts("  - Statuses: active, pending, completed")
    IO.puts("")

    {:ok, profile} = FlashProfile.profile(data, max_clusters: 5)

    IO.puts("Discovered patterns (#{length(profile.patterns)}):")

    profile.patterns
    |> Enum.with_index(1)
    |> Enum.each(fn {p, idx} ->
      IO.puts(
        "  #{idx}. #{p.regex} (#{Float.round(p.coverage * 100, 1)}% coverage, #{p.matched_count} values)"
      )
    end)

    IO.puts("")
    IO.puts("Total coverage: #{Float.round(profile.stats.total_coverage * 100, 1)}%")
  end

  # ============================================================
  # Example 6: Anomaly Detection
  # ============================================================

  @doc """
  Demonstrates anomaly detection capabilities.

  Shows how FlashProfile identifies values that don't match the
  dominant patterns, useful for data quality assessment.
  """
  @spec example_anomaly_detection() :: :ok
  def example_anomaly_detection do
    header("6. Anomaly Detection")

    IO.puts("Input: 95 normal values + 5 anomalies")
    IO.puts("")

    normal = for i <- 1..95, do: "ID-#{String.pad_leading(Integer.to_string(i), 4, "0")}"
    anomalies = ["WEIRD_VALUE", "totally different", "12345", "???", "ID-"]

    data = normal ++ anomalies

    {:ok, profile} = FlashProfile.profile(data)

    IO.puts("Main pattern:")
    IO.puts("  Regex: #{hd(profile.patterns).regex}")
    IO.puts("  Coverage: #{Float.round(hd(profile.patterns).coverage * 100, 1)}%")
    IO.puts("")
    IO.puts("Detected anomalies (#{length(profile.anomalies)}):")

    profile.anomalies
    |> Enum.each(fn a ->
      IO.puts("  - #{inspect(a)}")
    end)
  end

  # ============================================================
  # Example 7: Pattern Building API
  # ============================================================

  @doc """
  Demonstrates the Pattern DSL for programmatic pattern building.

  Shows how to construct patterns using `FlashProfile.Pattern` functions
  and evaluate their properties (cost, specificity, matching).
  """
  @spec example_pattern_building() :: :ok
  def example_pattern_building do
    header("7. Pattern Building API")

    IO.puts("Building patterns programmatically:")
    IO.puts("")

    # Build a complex pattern
    pattern =
      Pattern.seq([
        Pattern.enum(["GET", "POST", "PUT", "DELETE"]),
        Pattern.literal(" /api/"),
        Pattern.char_class(:lower, 1, 20),
        Pattern.literal("/"),
        Pattern.char_class(:digit, 1, 10)
      ])

    IO.puts("Pattern structure:")
    IO.puts("  seq([")
    IO.puts("    enum([\"GET\", \"POST\", \"PUT\", \"DELETE\"]),")
    IO.puts("    literal(\" /api/\"),")
    IO.puts("    char_class(:lower, 1, 20),")
    IO.puts("    literal(\"/\"),")
    IO.puts("    char_class(:digit, 1, 10)")
    IO.puts("  ])")
    IO.puts("")
    IO.puts("Compiled regex: #{Pattern.to_regex(pattern)}")
    IO.puts("Pretty format: #{Pattern.pretty(pattern)}")
    IO.puts("Cost: #{Float.round(Pattern.cost(pattern), 2)}")
    IO.puts("Specificity: #{Float.round(Pattern.specificity(pattern), 2)}")
    IO.puts("")

    # Test matching
    test_values = [
      "GET /api/users/123",
      "POST /api/orders/45678",
      "PATCH /api/items/1",
      "GET /INVALID/path"
    ]

    IO.puts("Matching tests:")

    test_values
    |> Enum.each(fn v ->
      result = if Pattern.matches?(pattern, v), do: "✓", else: "✗"
      IO.puts("  #{result} #{inspect(v)}")
    end)
  end

  # ============================================================
  # Example 8: Tokenization Deep Dive
  # ============================================================

  @doc """
  Demonstrates the tokenization process and signature generation.

  Shows how `FlashProfile.Tokenizer` breaks strings into tokens and
  generates signatures used for clustering similar structures.
  """
  @spec example_tokenization() :: :ok
  def example_tokenization do
    header("8. Tokenization Deep Dive")

    values = ["ACC-00123", "user.name@example.com", "2024-Q1"]

    values
    |> Enum.each(fn value ->
      IO.puts("Value: #{inspect(value)}")
      tokens = Tokenizer.tokenize(value)

      IO.puts(
        "  Tokens: #{tokens |> Enum.map(fn t -> "{#{t.type}:#{inspect(t.value)}}" end) |> Enum.join(" ")}"
      )

      IO.puts("  Signature: #{Tokenizer.signature(value)}")
      IO.puts("  Compact:   #{Tokenizer.compact_signature(value)}")
      IO.puts("")
    end)

    IO.puts("Compact signatures enable smart clustering:")
    IO.puts("  'ACC-00123'   → 'U-D'")
    IO.puts("  'ACCT-00123'  → 'U-D'  (same cluster!)")
    IO.puts("  'ACME-00001'  → 'U-D'  (same cluster!)")
  end

  # ============================================================
  # Helpers
  # ============================================================
  defp header(title) do
    IO.puts("\n" <> String.duplicate("─", 70))
    IO.puts("  #{title}")
    IO.puts(String.duplicate("─", 70) <> "\n")
  end
end

# Run if executed directly
if System.get_env("RUN_EXAMPLES") == "true" do
  FlashProfile.Examples.run_all()
end
