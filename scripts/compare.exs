# FlashProfile Implementation Comparison
# Runs benchmarks with both backends and compares results
# Usage: mix run scripts/compare.exs

defmodule Compare do
  @fixtures_dir Path.join([__DIR__, "..", "test", "fixtures", "flash_profile_demo"])

  # Quick comparison datasets (homogeneous only for fast results)
  @datasets [
    "phones.json",
    "bool.json",
    "dates.json",
    "emails.json"
    # Excluded (take longer):
    # "hetero_dates.json",
    # "us_canada_zip_codes.json",
    # "motivating_example.json"
  ]

  def run do
    IO.puts("=== FlashProfile Implementation Comparison ===")
    IO.puts("Time: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts("")

    # Run with Zig backend
    IO.puts("--- Running with Zig backend ---")
    Application.put_env(:flash_profile, :backend, :zig)
    System.put_env("FLASH_PROFILE_BACKEND", "zig")
    # Force recompilation of atoms by clearing any cached state
    zig_results = run_all_benchmarks("zig")

    IO.puts("")

    # Run with Elixir backend
    IO.puts("--- Running with Elixir backend ---")
    Application.put_env(:flash_profile, :backend, :elixir)
    System.put_env("FLASH_PROFILE_BACKEND", "elixir")
    elixir_results = run_all_benchmarks("elixir")

    IO.puts("")

    # Compare results
    print_comparison(zig_results, elixir_results)
  end

  defp run_all_benchmarks(_backend_name) do
    @datasets
    |> Enum.map(fn filename ->
      data = load_fixture(filename)
      count = length(data)

      # Force atoms to be recreated with current backend setting
      # by clearing module state (atoms are created at call time)
      Code.ensure_loaded!(FlashProfile.Config)

      # Warm up
      _ = FlashProfile.learn_pattern(Enum.take(data, 3))

      # Benchmark learn_pattern
      {learn_time, {pattern, cost}} = :timer.tc(fn ->
        FlashProfile.learn_pattern(data)
      end)
      learn_ms = learn_time / 1000

      # Calculate coverage
      coverage = calculate_coverage(pattern, data)

      # Skip profile for homogeneous data (only learn_pattern)
      profile_ms = 0.0

      IO.puts("#{filename}: learn=#{Float.round(learn_ms, 1)}ms, profile=#{Float.round(profile_ms, 1)}ms")

      %{
        dataset: filename,
        count: count,
        learn_ms: learn_ms,
        profile_ms: profile_ms,
        cost: cost,
        coverage: coverage,
        pattern: FlashProfile.pattern_to_string(pattern)
      }
    end)
  end

  defp print_comparison(zig_results, elixir_results) do
    IO.puts("=" |> String.duplicate(70))
    IO.puts("PERFORMANCE COMPARISON (Zig vs Pure Elixir)")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    IO.puts(String.pad_trailing("Dataset", 30) <>
            String.pad_leading("Zig", 12) <>
            String.pad_leading("Elixir", 12) <>
            String.pad_leading("Speedup", 12))
    IO.puts("-" |> String.duplicate(66))

    speedups =
      Enum.zip(zig_results, elixir_results)
      |> Enum.map(fn {zig, elixir} ->
        zig_total = zig.learn_ms + zig.profile_ms
        elixir_total = elixir.learn_ms + elixir.profile_ms
        speedup = if zig_total > 0, do: elixir_total / zig_total, else: 1.0

        IO.puts(
          String.pad_trailing(zig.dataset, 30) <>
          String.pad_leading("#{Float.round(zig_total, 1)}ms", 12) <>
          String.pad_leading("#{Float.round(elixir_total, 1)}ms", 12) <>
          String.pad_leading("#{Float.round(speedup, 2)}x", 12)
        )

        speedup
      end)

    avg_speedup = Enum.sum(speedups) / length(speedups)
    IO.puts("-" |> String.duplicate(66))
    IO.puts(String.pad_trailing("Average speedup:", 54) <>
            String.pad_leading("#{Float.round(avg_speedup, 2)}x", 12))

    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("QUALITY COMPARISON")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    # Check if results are identical
    IO.puts(String.pad_trailing("Dataset", 30) <>
            String.pad_leading("Zig Cost", 12) <>
            String.pad_leading("Elixir Cost", 12) <>
            String.pad_leading("Match?", 10))
    IO.puts("-" |> String.duplicate(64))

    all_match =
      Enum.zip(zig_results, elixir_results)
      |> Enum.map(fn {zig, elixir} ->
        cost_match = abs(zig.cost - elixir.cost) < 0.01
        coverage_match = abs(zig.coverage - elixir.coverage) < 0.1
        match = cost_match and coverage_match

        IO.puts(
          String.pad_trailing(zig.dataset, 30) <>
          String.pad_leading("#{Float.round(zig.cost, 2)}", 12) <>
          String.pad_leading("#{Float.round(elixir.cost, 2)}", 12) <>
          String.pad_leading(if(match, do: "YES", else: "NO"), 10)
        )

        match
      end)
      |> Enum.all?()

    IO.puts("-" |> String.duplicate(64))
    IO.puts("")
    IO.puts("Results identical: #{if all_match, do: "YES", else: "NO"}")
    IO.puts("")

    # Total times
    zig_total = Enum.sum(Enum.map(zig_results, &(&1.learn_ms + &1.profile_ms)))
    elixir_total = Enum.sum(Enum.map(elixir_results, &(&1.learn_ms + &1.profile_ms)))

    IO.puts("=" |> String.duplicate(70))
    IO.puts("TOTALS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("Zig backend total:    #{Float.round(zig_total, 1)}ms")
    IO.puts("Elixir backend total: #{Float.round(elixir_total, 1)}ms")
    IO.puts("Overall speedup:      #{Float.round(elixir_total / zig_total, 2)}x")
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

# Run comparison
Compare.run()
