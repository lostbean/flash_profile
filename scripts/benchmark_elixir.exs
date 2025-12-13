# Pure Elixir Implementation Benchmark
# Usage:
#   FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark_elixir.exs
#
# This script benchmarks the pure Elixir implementation of FlashProfile functions:
# - FlashProfile.Learner.learn_best_pattern/2
# - FlashProfile.Clustering.Dissimilarity.compute/3
# - FlashProfile.Profile.profile/4

defmodule BenchmarkElixir do
  alias FlashProfile.{Learner, Profile}
  alias FlashProfile.Clustering.Dissimilarity
  alias FlashProfile.Atoms.Defaults

  @iterations 10

  # Test datasets matching the Zig benchmark
  @pmc_ids ["PMC123", "PMC456", "PMC789"]
  @dates ["2023-01-15", "2024-06-30", "2025-12-01"]
  @mixed ["ABC123", "DEF456", "GHI789"]

  # Larger datasets for profile testing
  @pmc_ids_large ["PMC1234567", "PMC9876543", "PMC5555555", "PMC1111111", "PMC9999999"]
  @dates_large [
    "2023-01-15",
    "2024-06-30",
    "2025-12-01",
    "2022-03-17",
    "2021-11-22",
    "2020-08-05",
    "2019-12-25",
    "2018-07-04",
    "2017-02-14",
    "2016-10-31"
  ]
  @mixed_large [
    "ABC123",
    "DEF456",
    "GHI789",
    "JKL012",
    "MNO345",
    "PQR678",
    "STU901",
    "VWX234",
    "YZA567",
    "BCD890"
  ]

  def run do
    # Verify we're using pure Elixir backend
    backend = FlashProfile.Config.backend()

    if backend != :elixir do
      IO.puts("ERROR: This benchmark requires pure Elixir backend")
      IO.puts("Please run with: FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark_elixir.exs")
      System.halt(1)
    end

    IO.puts("=" |> String.duplicate(80))
    IO.puts("FlashProfile Pure Elixir Implementation Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Backend: #{backend}")
    IO.puts("Iterations per test: #{@iterations}")
    IO.puts("Time: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts("")

    # Get default atoms
    atoms = Defaults.all()
    IO.puts("Default atoms: #{length(atoms)} (#{Enum.map(atoms, & &1.name) |> Enum.join(", ")})")
    IO.puts("")

    # Run benchmarks
    benchmark_learner(atoms)
    benchmark_dissimilarity(atoms)
    benchmark_profile(atoms)

    IO.puts("\n" <> ("=" |> String.duplicate(80)))
    IO.puts("Benchmark Complete")
    IO.puts("=" |> String.duplicate(80))
  end

  defp benchmark_learner(atoms) do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("1. FlashProfile.Learner.learn_best_pattern/2")
    IO.puts("=" |> String.duplicate(80))

    datasets = [
      {"PMC IDs (3 strings)", @pmc_ids},
      {"Dates (3 strings)", @dates},
      {"Mixed (3 strings)", @mixed},
      {"PMC IDs (5 strings)", @pmc_ids_large},
      {"Dates (10 strings)", @dates_large},
      {"Mixed (10 strings)", @mixed_large}
    ]

    Enum.each(datasets, fn {name, data} ->
      benchmark_learn_pattern(name, data, atoms)
    end)

    IO.puts("")
  end

  defp benchmark_learn_pattern(name, strings, atoms) do
    # Warmup
    _ = Learner.learn_best_pattern(strings, atoms)

    # Benchmark
    times =
      Enum.map(1..@iterations, fn _ ->
        {time, result} = :timer.tc(fn ->
          Learner.learn_best_pattern(strings, atoms)
        end)
        {time, result}
      end)

    avg_time = times |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> Kernel.div(@iterations)
    {pattern, cost} = hd(times) |> elem(1)

    # Format pattern for display
    pattern_str = format_pattern(pattern)

    IO.puts("Dataset: #{name}")
    IO.puts("  Average time: #{format_time(avg_time)}")
    IO.puts("  Pattern: #{pattern_str}")
    IO.puts("  Cost: #{Float.round(cost, 2)}")
    IO.puts("")
  end

  defp benchmark_dissimilarity(atoms) do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("2. FlashProfile.Clustering.Dissimilarity.compute/3")
    IO.puts("=" |> String.duplicate(80))

    test_pairs = [
      {"Same PMC IDs", "PMC123", "PMC456"},
      {"Same date format", "2023-01-15", "2024-06-30"},
      {"Same mixed format", "ABC123", "DEF456"},
      {"Different formats (PMC vs Date)", "PMC123", "2023-01-15"},
      {"Different formats (Date vs Mixed)", "2023-01-15", "ABC123"},
      {"Identical strings", "PMC123", "PMC123"}
    ]

    Enum.each(test_pairs, fn {name, str1, str2} ->
      benchmark_dissimilarity_pair(name, str1, str2, atoms)
    end)

    IO.puts("")
  end

  defp benchmark_dissimilarity_pair(name, str1, str2, atoms) do
    # Warmup
    _ = Dissimilarity.compute(str1, str2, atoms)

    # Benchmark
    times =
      Enum.map(1..@iterations, fn _ ->
        {time, result} = :timer.tc(fn ->
          Dissimilarity.compute(str1, str2, atoms)
        end)
        {time, result}
      end)

    avg_time = times |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> Kernel.div(@iterations)
    dissimilarity = hd(times) |> elem(1)

    IO.puts("Pair: #{name}")
    IO.puts("  Strings: \"#{str1}\" vs \"#{str2}\"")
    IO.puts("  Average time: #{format_time(avg_time)}")
    IO.puts("  Dissimilarity: #{format_dissimilarity(dissimilarity)}")
    IO.puts("")
  end

  defp benchmark_profile(atoms) do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("3. FlashProfile.Profile.profile/4")
    IO.puts("=" |> String.duplicate(80))

    datasets = [
      {"PMC IDs (5 strings)", @pmc_ids_large, 1, 2},
      {"Dates (10 strings)", @dates_large, 1, 3},
      {"Mixed (10 strings)", @mixed_large, 1, 3},
      {"Heterogeneous (PMC + Dates)", @pmc_ids_large ++ @dates_large, 2, 5}
    ]

    Enum.each(datasets, fn {name, data, min_patterns, max_patterns} ->
      benchmark_profile_dataset(name, data, min_patterns, max_patterns, atoms)
    end)

    IO.puts("")
  end

  defp benchmark_profile_dataset(name, strings, min_patterns, max_patterns, atoms) do
    # Warmup
    _ = Profile.profile(strings, min_patterns, max_patterns, atoms: atoms)

    # Benchmark
    times =
      Enum.map(1..@iterations, fn _ ->
        {time, result} = :timer.tc(fn ->
          Profile.profile(strings, min_patterns, max_patterns, atoms: atoms)
        end)
        {time, result}
      end)

    avg_time = times |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> Kernel.div(@iterations)
    entries = hd(times) |> elem(1)

    IO.puts("Dataset: #{name}")
    IO.puts("  Strings: #{length(strings)}, Patterns: #{min_patterns}..#{max_patterns}")
    IO.puts("  Average time: #{format_time(avg_time)}")
    IO.puts("  Clusters found: #{length(entries)}")

    # Show each cluster
    Enum.each(entries, fn entry ->
      pattern_str = format_pattern(entry.pattern)
      cost_str = format_cost(entry.cost)
      IO.puts("    - Pattern: #{pattern_str}, Cost: #{cost_str}, Size: #{length(entry.data)}")
    end)

    IO.puts("")
  end

  # Helper functions

  defp format_time(microseconds) when microseconds < 1000 do
    "#{microseconds} μs"
  end

  defp format_time(microseconds) when microseconds < 1_000_000 do
    ms = Float.round(microseconds / 1000, 2)
    "#{ms} ms (#{microseconds} μs)"
  end

  defp format_time(microseconds) do
    ms = Float.round(microseconds / 1000, 2)
    sec = Float.round(microseconds / 1_000_000, 2)
    "#{sec} sec (#{ms} ms)"
  end

  defp format_pattern(nil), do: "nil (learning failed)"

  defp format_pattern(pattern) when is_list(pattern) do
    pattern
    |> Enum.map(fn atom ->
      case atom.type do
        :constant -> atom.params.string
        :char_class ->
          case atom.params.width do
            0 -> atom.name
            w -> "#{atom.name}×#{w}"
          end
        _ -> atom.name
      end
    end)
    |> Enum.join(", ")
  end

  defp format_dissimilarity(:infinity), do: "∞"
  defp format_dissimilarity(value) when is_float(value), do: Float.round(value, 2)

  defp format_cost(:infinity), do: "∞"
  defp format_cost(value) when is_float(value), do: Float.round(value, 2)
end

# Run the benchmark
BenchmarkElixir.run()
