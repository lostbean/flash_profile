# FlashProfile Backend Comparison Benchmark
# Usage:
#   mix run scripts/benchmark_comparison.exs
#
# This script benchmarks both Zig and Elixir backends and compares them.

defmodule BenchmarkComparison do
  alias FlashProfile.{Learner, Profile}
  alias FlashProfile.Clustering.Dissimilarity
  alias FlashProfile.Atoms.Defaults

  @iterations 5

  # Test datasets
  @pmc_ids ["PMC123", "PMC456", "PMC789"]
  @dates ["2023-01-15", "2024-06-30", "2025-12-01"]
  @pmc_ids_large ["PMC1234567", "PMC9876543", "PMC5555555", "PMC1111111", "PMC9999999"]

  def run do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("FlashProfile Backend Comparison Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Iterations per test: #{@iterations}")
    IO.puts("Time: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts("")

    atoms = Defaults.all()

    # Run with both backends
    results_zig = run_with_backend(:zig, atoms)
    results_elixir = run_with_backend(:elixir, atoms)

    # Print comparison
    print_comparison(results_zig, results_elixir)
  end

  defp run_with_backend(backend, atoms) do
    # Set backend via environment variable
    System.put_env("FLASH_PROFILE_BACKEND", to_string(backend))

    # Force reload config
    :ok = Application.stop(:flash_profile)
    :ok = Application.start(:flash_profile)

    IO.puts("\nRunning with #{backend} backend...")

    results = %{
      learn_pmc_3: benchmark_fn(fn -> Learner.learn_best_pattern(@pmc_ids, atoms) end),
      learn_dates_3: benchmark_fn(fn -> Learner.learn_best_pattern(@dates, atoms) end),
      learn_pmc_5: benchmark_fn(fn -> Learner.learn_best_pattern(@pmc_ids_large, atoms) end),
      dissimilarity_pmc: benchmark_fn(fn -> Dissimilarity.compute("PMC123", "PMC456", atoms) end),
      dissimilarity_dates: benchmark_fn(fn -> Dissimilarity.compute("2023-01-15", "2024-06-30", atoms) end),
      profile_pmc: benchmark_fn(fn -> Profile.profile(@pmc_ids_large, 1, 2, atoms: atoms) end)
    }

    IO.puts("#{backend} backend complete.")
    results
  end

  defp benchmark_fn(func) do
    # Warmup
    _ = func.()

    # Benchmark
    times =
      Enum.map(1..@iterations, fn _ ->
        {time, _result} = :timer.tc(func)
        time
      end)

    avg_time = Enum.sum(times) / @iterations
    min_time = Enum.min(times)
    max_time = Enum.max(times)

    %{avg: avg_time, min: min_time, max: max_time}
  end

  defp print_comparison(results_zig, results_elixir) do
    IO.puts("\n" <> ("=" |> String.duplicate(80)))
    IO.puts("Performance Comparison (Zig vs Elixir)")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("")

    tests = [
      {:learn_pmc_3, "Learner: PMC IDs (3 strings)"},
      {:learn_dates_3, "Learner: Dates (3 strings)"},
      {:learn_pmc_5, "Learner: PMC IDs (5 strings)"},
      {:dissimilarity_pmc, "Dissimilarity: PMC pair"},
      {:dissimilarity_dates, "Dissimilarity: Date pair"},
      {:profile_pmc, "Profile: PMC IDs (5 strings)"}
    ]

    Enum.each(tests, fn {key, name} ->
      zig = results_zig[key]
      elixir = results_elixir[key]

      speedup = elixir.avg / zig.avg
      speedup_str = Float.round(speedup, 2)

      IO.puts("#{name}")
      IO.puts("  Zig:    #{format_time(zig.avg)} (min: #{format_time(zig.min)}, max: #{format_time(zig.max)})")
      IO.puts("  Elixir: #{format_time(elixir.avg)} (min: #{format_time(elixir.min)}, max: #{format_time(elixir.max)})")
      IO.puts("  Speedup: #{speedup_str}x faster with Zig")
      IO.puts("")
    end)

    # Overall statistics
    all_speedups =
      tests
      |> Enum.map(fn {key, _} ->
        results_elixir[key].avg / results_zig[key].avg
      end)

    avg_speedup = Enum.sum(all_speedups) / length(all_speedups)
    min_speedup = Enum.min(all_speedups)
    max_speedup = Enum.max(all_speedups)

    IO.puts("=" |> String.duplicate(80))
    IO.puts("Overall Statistics")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("  Average speedup: #{Float.round(avg_speedup, 2)}x")
    IO.puts("  Min speedup:     #{Float.round(min_speedup, 2)}x")
    IO.puts("  Max speedup:     #{Float.round(max_speedup, 2)}x")
    IO.puts("")
  end

  defp format_time(microseconds) when microseconds < 1000 do
    "#{Float.round(microseconds, 2)} μs"
  end

  defp format_time(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1000, 2)} ms"
  end

  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1_000_000, 2)} sec"
  end
end

# Run the benchmark
BenchmarkComparison.run()
