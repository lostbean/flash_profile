# FlashProfile Quality Validation
# Compares learned patterns against paper's expected results
# Usage: mix run scripts/validate_quality.exs

defmodule QualityValidation do
  @fixtures_dir Path.join([__DIR__, "..", "test", "fixtures", "flash_profile_demo"])

  # Expected results from the FlashProfile paper
  # Quick validation (homogeneous datasets only)
  @expected_patterns %{
    "phones.json" => %{
      description: "[Digit]{3} · '-' · [Digit]{3} · '-' · [Digit]{4}",
      coverage: 100.0,
      max_cost: 50.0,
      required_atoms: ["Digit"]
    },
    "bool.json" => %{
      description: "'yes' | 'no' OR [Lower]+",
      coverage: 100.0,
      max_cost: 30.0,
      required_atoms: []  # Either constants or Lower
    },
    "dates.json" => %{
      description: "[Digit]{2} · '.' · [Digit]{2} · '.2016'",
      coverage: 100.0,
      max_cost: 50.0,
      required_atoms: ["Digit"]
    },
    "emails.json" => %{
      description: "[Lower]+ · '.' · [Lower]+ · '@' · [Lower]+ · '.com'",
      coverage: 100.0,
      max_cost: 70.0,
      required_atoms: ["Lower"]
    }
    # Heterogeneous datasets (excluded for quick validation - take longer):
    # "hetero_dates.json" => %{min_clusters: 3, max_clusters: 7, ...}
    # "us_canada_zip_codes.json" => %{min_clusters: 4, max_clusters: 10, ...}
    # "motivating_example.json" => %{min_clusters: 3, max_clusters: 7, max_time_ms: 60_000}
  }

  def run do
    IO.puts("=== FlashProfile Quality Validation ===")
    IO.puts("")

    results =
      @expected_patterns
      |> Enum.map(fn {filename, expected} ->
        validate_fixture(filename, expected)
      end)

    # Summary
    passed = Enum.count(results, & &1.passed)
    total = length(results)
    IO.puts("=== Summary ===")
    IO.puts("Passed: #{passed}/#{total}")

    if passed == total do
      IO.puts("Status: ALL PASS")
    else
      IO.puts("Status: SOME FAILURES")
      failed = Enum.filter(results, &(!&1.passed))
      IO.puts("Failed: #{Enum.map(failed, & &1.dataset) |> Enum.join(", ")}")
    end

    results
  end

  defp validate_fixture(filename, expected) do
    data = load_fixture(filename)
    _count = length(data)
    IO.puts("#{filename}:")
    IO.puts("  Expected: #{expected.description}")

    # Check if this is homogeneous (learn_pattern) or heterogeneous (profile)
    is_heterogeneous = Map.has_key?(expected, :min_clusters)

    result =
      if is_heterogeneous do
        validate_heterogeneous(data, expected)
      else
        validate_homogeneous(data, expected)
      end

    status = if result.passed, do: "PASS", else: "FAIL"
    IO.puts("  Status: #{status}")
    IO.puts("")

    Map.put(result, :dataset, filename)
  end

  defp validate_homogeneous(data, expected) do
    {pattern, cost} = FlashProfile.learn_pattern(data)
    pattern_str = FlashProfile.pattern_to_string(pattern)

    IO.puts("  Learned: #{pattern_str}")
    IO.puts("  Cost: #{Float.round(cost, 2)}")

    # Calculate coverage
    coverage = calculate_coverage(pattern, data)
    IO.puts("  Coverage: #{Float.round(coverage, 1)}%")

    # Check required atoms
    atoms_present =
      if expected.required_atoms != [] do
        pattern_str_lower = String.downcase(pattern_str)
        Enum.all?(expected.required_atoms, fn atom ->
          String.contains?(pattern_str_lower, String.downcase(atom))
        end)
      else
        true
      end

    passed =
      coverage >= expected.coverage and
        cost <= expected.max_cost and
        atoms_present

    %{
      passed: passed,
      pattern: pattern_str,
      cost: cost,
      coverage: coverage
    }
  end

  defp validate_heterogeneous(data, expected) do
    {time_us, profile} = :timer.tc(fn ->
      FlashProfile.profile(data)
    end)
    time_ms = time_us / 1000

    cluster_count = length(profile)
    IO.puts("  Clusters: #{cluster_count} (expected: #{expected.min_clusters}-#{expected.max_clusters})")
    IO.puts("  Time: #{Float.round(time_ms, 2)}ms")

    # Calculate total coverage
    total_matched =
      profile
      |> Enum.flat_map(fn entry -> entry.data end)
      |> length()

    coverage = total_matched / length(data) * 100
    IO.puts("  Coverage: #{Float.round(coverage, 1)}%")

    # Check constraints
    clusters_ok = cluster_count >= expected.min_clusters and cluster_count <= expected.max_clusters
    coverage_ok = coverage >= expected.coverage
    time_ok = if Map.has_key?(expected, :max_time_ms), do: time_ms <= expected.max_time_ms, else: true

    passed = clusters_ok and coverage_ok and time_ok

    if not time_ok do
      IO.puts("  WARNING: Exceeded time limit (#{expected.max_time_ms}ms)")
    end

    %{
      passed: passed,
      cluster_count: cluster_count,
      coverage: coverage,
      time_ms: time_ms
    }
  end

  defp calculate_coverage(pattern, data) do
    matched = Enum.count(data, fn s -> FlashProfile.matches?(pattern, s) end)
    matched / length(data) * 100
  end

  defp load_fixture(filename) do
    path = Path.join(@fixtures_dir, filename)
    {:ok, content} = File.read(path)
    # Use OTP 27+ built-in JSON decoder
    fixture = :json.decode(content)
    Map.get(fixture, "Data", [])
  end
end

# Run validation
QualityValidation.run()
