#!/usr/bin/env elixir
# FlashProfile Benchmark Suite
# Comprehensive performance testing for Zig vs Elixir implementations

defmodule FlashProfileBenchmark do
  @moduledoc """
  Comprehensive benchmark suite for FlashProfile.
  Tests pattern learning and profiling with varying input sizes and data types.
  """

  alias FlashProfile.{Learner, Profile, BigProfile}
  alias FlashProfile.Atoms.Defaults

  # Benchmark configuration
  @sizes [10, 20, 50, 100]
  @warmup_iterations 3
  @benchmark_iterations 10

  defmodule BenchmarkResult do
    defstruct [
      :test_name,
      :implementation,
      :size,
      :mean_time_us,
      :min_time_us,
      :max_time_us,
      :std_dev_us,
      :iterations
    ]
  end

  ## Data Generation Functions

  def generate_phone_numbers(count) do
    for i <- 1..count do
      area = :rand.uniform(900) + 99
      prefix = :rand.uniform(900) + 99
      suffix = String.pad_leading(Integer.to_string(i), 4, "0")
      "555-#{area}-#{suffix}"
    end
  end

  def generate_emails(count) do
    for i <- 1..count do
      "user#{i}@example.com"
    end
  end

  def generate_dates(count) do
    for i <- 1..count do
      year = 2020 + rem(i, 5)
      month = String.pad_leading(Integer.to_string(rem(i, 12) + 1), 2, "0")
      day = String.pad_leading(Integer.to_string(rem(i, 28) + 1), 2, "0")
      "#{year}-#{month}-#{day}"
    end
  end

  def generate_mixed(count) do
    phones = generate_phone_numbers(div(count, 3))
    emails = generate_emails(div(count, 3))
    dates = generate_dates(count - length(phones) - length(emails))
    Enum.shuffle(phones ++ emails ++ dates)
  end

  ## Timing Functions

  def time_microseconds(fun) do
    {time_us, result} = :timer.tc(fun)
    {time_us, result}
  end

  def benchmark_function(fun, iterations) do
    # Warmup
    for _ <- 1..@warmup_iterations, do: fun.()

    # Actual benchmark
    times = for _ <- 1..iterations do
      {time_us, _result} = time_microseconds(fun)
      time_us
    end

    calculate_statistics(times)
  end

  def calculate_statistics(times) do
    count = length(times)
    mean = Enum.sum(times) / count
    min = Enum.min(times)
    max = Enum.max(times)

    variance = Enum.reduce(times, 0, fn t, acc ->
      diff = t - mean
      acc + diff * diff
    end) / count

    std_dev = :math.sqrt(variance)

    %{
      mean: mean,
      min: min,
      max: max,
      std_dev: std_dev,
      count: count
    }
  end

  ## Benchmark Implementations

  def benchmark_learn_pattern_zig(strings, size) do
    stats = benchmark_function(fn ->
      FlashProfile.learn_pattern(strings)
    end, @benchmark_iterations)

    %BenchmarkResult{
      test_name: "learn_pattern",
      implementation: :zig,
      size: size,
      mean_time_us: stats.mean,
      min_time_us: stats.min,
      max_time_us: stats.max,
      std_dev_us: stats.std_dev,
      iterations: stats.count
    }
  end

  def benchmark_learn_pattern_elixir(strings, size) do
    atoms = Defaults.all()
    stats = benchmark_function(fn ->
      Learner.learn_best_pattern(strings, atoms)
    end, @benchmark_iterations)

    %BenchmarkResult{
      test_name: "learn_pattern",
      implementation: :elixir,
      size: size,
      mean_time_us: stats.mean,
      min_time_us: stats.min,
      max_time_us: stats.max,
      std_dev_us: stats.std_dev,
      iterations: stats.count
    }
  end

  def benchmark_profile_zig(strings, size) do
    # Only use Zig for smaller datasets (it currently falls back to Elixir for >30)
    if size <= 30 do
      stats = benchmark_function(fn ->
        # Force Zig by using Native directly
        FlashProfile.Native.profile(strings, 1, 3, 1.25)
      end, @benchmark_iterations)

      %BenchmarkResult{
        test_name: "profile",
        implementation: :zig,
        size: size,
        mean_time_us: stats.mean,
        min_time_us: stats.min,
        max_time_us: stats.max,
        std_dev_us: stats.std_dev,
        iterations: stats.count
      }
    else
      nil
    end
  end

  def benchmark_profile_elixir(strings, size) do
    stats = benchmark_function(fn ->
      Profile.profile(strings, 1, 3)
    end, @benchmark_iterations)

    %BenchmarkResult{
      test_name: "profile",
      implementation: :elixir,
      size: size,
      mean_time_us: stats.mean,
      min_time_us: stats.min,
      max_time_us: stats.max,
      std_dev_us: stats.std_dev,
      iterations: stats.count
    }
  end

  ## Result Formatting

  def format_time(microseconds) when microseconds < 1000 do
    "#{Float.round(microseconds, 2)} μs"
  end

  def format_time(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1000, 2)} ms"
  end

  def format_time(microseconds) do
    "#{Float.round(microseconds / 1_000_000, 2)} s"
  end

  def print_result(result) do
    IO.puts("  #{result.implementation |> Atom.to_string() |> String.upcase()}")
    IO.puts("    Size: #{result.size} strings")
    IO.puts("    Mean: #{format_time(result.mean_time_us)}")
    IO.puts("    Min:  #{format_time(result.min_time_us)}")
    IO.puts("    Max:  #{format_time(result.max_time_us)}")
    IO.puts("    StdDev: #{format_time(result.std_dev_us)}")
    IO.puts("    Iterations: #{result.iterations}")
  end

  def calculate_speedup(zig_result, elixir_result) when not is_nil(zig_result) and not is_nil(elixir_result) do
    speedup = elixir_result.mean_time_us / zig_result.mean_time_us

    cond do
      speedup > 1.0 ->
        IO.puts("  ✓ Zig is #{Float.round(speedup, 2)}x faster")
      speedup < 1.0 ->
        IO.puts("  ✗ Zig is #{Float.round(1/speedup, 2)}x slower")
      true ->
        IO.puts("  = Same performance")
    end

    speedup
  end

  def calculate_speedup(_, _), do: nil

  def analyze_scaling(results) do
    # Group by implementation and test
    grouped = Enum.group_by(results, fn r -> {r.implementation, r.test_name} end)

    Enum.each(grouped, fn {{impl, test}, data} ->
      sorted = Enum.sort_by(data, & &1.size)

      if length(sorted) >= 2 do
        # Calculate time ratios between consecutive sizes
        ratios = Enum.zip(sorted, tl(sorted))
        |> Enum.map(fn {r1, r2} ->
          size_ratio = r2.size / r1.size
          time_ratio = r2.mean_time_us / r1.mean_time_us
          {size_ratio, time_ratio, r1.size, r2.size}
        end)

        avg_time_growth = Enum.reduce(ratios, 0, fn {_sr, tr, _, _}, acc -> acc + tr end) / length(ratios)
        avg_size_growth = Enum.reduce(ratios, 0, fn {sr, _tr, _, _}, acc -> acc + sr end) / length(ratios)

        IO.puts("\n#{String.upcase(Atom.to_string(impl))} - #{test} Scaling Analysis:")
        Enum.each(ratios, fn {size_ratio, time_ratio, s1, s2} ->
          complexity = if size_ratio > 1.0, do: :math.log(time_ratio) / :math.log(size_ratio), else: 0
          IO.puts("  #{s1} → #{s2}: #{Float.round(time_ratio, 2)}x time for #{Float.round(size_ratio, 2)}x size (complexity ≈ O(n^#{Float.round(complexity, 2)}))")
        end)

        overall_complexity = if avg_size_growth > 1.0 do
          :math.log(avg_time_growth) / :math.log(avg_size_growth)
        else
          0
        end

        IO.puts("  Average: #{Float.round(avg_time_growth, 2)}x time for #{Float.round(avg_size_growth, 2)}x size")
        IO.puts("  Overall complexity: O(n^#{Float.round(overall_complexity, 2)})")
      end
    end)
  end

  def print_summary_table(results) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SUMMARY TABLE")
    IO.puts(String.duplicate("=", 80))

    # Group by test name and size
    grouped = Enum.group_by(results, fn r -> {r.test_name, r.size} end)

    # Print header
    IO.puts(String.pad_trailing("Test", 20) <>
            String.pad_trailing("Size", 10) <>
            String.pad_trailing("Zig", 20) <>
            String.pad_trailing("Elixir", 20) <>
            "Speedup")
    IO.puts(String.duplicate("-", 80))

    # Sort by test name and size
    grouped
    |> Enum.sort_by(fn {{test, size}, _} -> {test, size} end)
    |> Enum.each(fn {{test, size}, group_results} ->
      zig = Enum.find(group_results, fn r -> r.implementation == :zig end)
      elixir = Enum.find(group_results, fn r -> r.implementation == :elixir end)

      zig_time = if zig, do: format_time(zig.mean_time_us), else: "N/A"
      elixir_time = if elixir, do: format_time(elixir.mean_time_us), else: "N/A"

      speedup_str = if zig && elixir do
        speedup = elixir.mean_time_us / zig.mean_time_us
        "#{Float.round(speedup, 2)}x"
      else
        "N/A"
      end

      IO.puts(String.pad_trailing(test, 20) <>
              String.pad_trailing("#{size}", 10) <>
              String.pad_trailing(zig_time, 20) <>
              String.pad_trailing(elixir_time, 20) <>
              speedup_str)
    end)
  end

  ## Main Benchmark Runner

  def run_benchmarks do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("FlashProfile Performance Benchmark Suite")
    IO.puts(String.duplicate("=", 80))
    IO.puts("Warmup iterations: #{@warmup_iterations}")
    IO.puts("Benchmark iterations: #{@benchmark_iterations}")
    IO.puts("Test sizes: #{inspect(@sizes)}")
    IO.puts(String.duplicate("=", 80))

    all_results = []

    # Test 1: Phone Numbers - learn_pattern
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TEST 1: Pattern Learning - Phone Numbers (555-XXX-XXXX)")
    IO.puts(String.duplicate("=", 80))

    phone_results = for size <- @sizes do
      IO.puts("\n--- Size: #{size} ---")
      data = generate_phone_numbers(size)

      IO.puts("Running Zig implementation...")
      zig_result = benchmark_learn_pattern_zig(data, size)
      print_result(zig_result)

      IO.puts("\nRunning Elixir implementation...")
      elixir_result = benchmark_learn_pattern_elixir(data, size)
      print_result(elixir_result)

      IO.puts("\nComparison:")
      calculate_speedup(zig_result, elixir_result)

      [zig_result, elixir_result]
    end |> List.flatten()

    all_results = all_results ++ phone_results

    # Test 2: Email Addresses - learn_pattern
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TEST 2: Pattern Learning - Email Addresses (userX@example.com)")
    IO.puts(String.duplicate("=", 80))

    email_results = for size <- @sizes do
      IO.puts("\n--- Size: #{size} ---")
      data = generate_emails(size)

      IO.puts("Running Zig implementation...")
      zig_result = benchmark_learn_pattern_zig(data, size)
      print_result(zig_result)

      IO.puts("\nRunning Elixir implementation...")
      elixir_result = benchmark_learn_pattern_elixir(data, size)
      print_result(elixir_result)

      IO.puts("\nComparison:")
      calculate_speedup(zig_result, elixir_result)

      [zig_result, elixir_result]
    end |> List.flatten()

    all_results = all_results ++ email_results

    # Test 3: Dates - learn_pattern
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TEST 3: Pattern Learning - Dates (YYYY-MM-DD)")
    IO.puts(String.duplicate("=", 80))

    date_results = for size <- @sizes do
      IO.puts("\n--- Size: #{size} ---")
      data = generate_dates(size)

      IO.puts("Running Zig implementation...")
      zig_result = benchmark_learn_pattern_zig(data, size)
      print_result(zig_result)

      IO.puts("\nRunning Elixir implementation...")
      elixir_result = benchmark_learn_pattern_elixir(data, size)
      print_result(elixir_result)

      IO.puts("\nComparison:")
      calculate_speedup(zig_result, elixir_result)

      [zig_result, elixir_result]
    end |> List.flatten()

    all_results = all_results ++ date_results

    # Test 4: Profile Algorithm - Phone Numbers
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TEST 4: Profile Algorithm - Phone Numbers")
    IO.puts(String.duplicate("=", 80))

    profile_results = for size <- @sizes do
      IO.puts("\n--- Size: #{size} ---")
      data = generate_phone_numbers(size)

      zig_result = if size <= 30 do
        IO.puts("Running Zig implementation...")
        result = benchmark_profile_zig(data, size)
        print_result(result)
        result
      else
        IO.puts("Skipping Zig implementation (size > 30, would fall back to Elixir)")
        nil
      end

      IO.puts("\nRunning Elixir implementation...")
      elixir_result = benchmark_profile_elixir(data, size)
      print_result(elixir_result)

      if zig_result do
        IO.puts("\nComparison:")
        calculate_speedup(zig_result, elixir_result)
      end

      [zig_result, elixir_result] |> Enum.filter(&(&1 != nil))
    end |> List.flatten()

    all_results = all_results ++ profile_results

    # Test 5: Mixed Data - Profile Algorithm
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TEST 5: Profile Algorithm - Mixed Data (phones + emails + dates)")
    IO.puts(String.duplicate("=", 80))

    mixed_results = for size <- @sizes do
      IO.puts("\n--- Size: #{size} ---")
      data = generate_mixed(size)

      zig_result = if size <= 30 do
        IO.puts("Running Zig implementation...")
        result = benchmark_profile_zig(data, size)
        print_result(result)
        result
      else
        IO.puts("Skipping Zig implementation (size > 30, would fall back to Elixir)")
        nil
      end

      IO.puts("\nRunning Elixir implementation...")
      elixir_result = benchmark_profile_elixir(data, size)
      print_result(elixir_result)

      if zig_result do
        IO.puts("\nComparison:")
        calculate_speedup(zig_result, elixir_result)
      end

      [zig_result, elixir_result] |> Enum.filter(&(&1 != nil))
    end |> List.flatten()

    all_results = all_results ++ mixed_results

    # Final Analysis
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SCALING ANALYSIS")
    IO.puts(String.duplicate("=", 80))
    analyze_scaling(all_results)

    # Summary Table
    print_summary_table(all_results)

    # Overall Statistics
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("OVERALL STATISTICS")
    IO.puts(String.duplicate("=", 80))

    zig_results = Enum.filter(all_results, fn r -> r.implementation == :zig end)
    elixir_results = Enum.filter(all_results, fn r -> r.implementation == :elixir end)

    if length(zig_results) > 0 && length(elixir_results) > 0 do
      # Calculate speedups for matching test/size combinations
      speedups = for zig <- zig_results do
        matching_elixir = Enum.find(elixir_results, fn e ->
          e.test_name == zig.test_name && e.size == zig.size
        end)

        if matching_elixir do
          matching_elixir.mean_time_us / zig.mean_time_us
        else
          nil
        end
      end
      |> Enum.filter(&(&1 != nil))

      if length(speedups) > 0 do
        avg_speedup = Enum.sum(speedups) / length(speedups)
        min_speedup = Enum.min(speedups)
        max_speedup = Enum.max(speedups)

        IO.puts("Average Zig speedup: #{Float.round(avg_speedup, 2)}x")
        IO.puts("Best case speedup: #{Float.round(max_speedup, 2)}x")
        IO.puts("Worst case speedup: #{Float.round(min_speedup, 2)}x")
      end
    end

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("BENCHMARK COMPLETE")
    IO.puts(String.duplicate("=", 80))

    :ok
  end
end

# Run the benchmarks
FlashProfileBenchmark.run_benchmarks()
