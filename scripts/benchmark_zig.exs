# FlashProfile Zig NIF Performance Benchmark
# Usage: mix run scripts/benchmark_zig.exs
#
# This script benchmarks the low-level Zig NIF functions directly,
# testing core functions with varying dataset sizes and types.

defmodule ZigBenchmark do
  @moduledoc """
  Direct benchmark of Zig NIF implementations in FlashProfile.
  Tests core functions with varying dataset sizes and types.
  """

  # Number of iterations for averaging
  @iterations 10

  # Test datasets
  @test_data %{
    pmc_small: ["PMC123", "PMC456", "PMC789"],
    pmc_medium: ["PMC100", "PMC200", "PMC300", "PMC400", "PMC500", "PMC600", "PMC700"],
    dates_small: ["2023-01-15", "2024-06-30", "2025-12-01"],
    dates_medium: ["2023-01-15", "2024-06-30", "2025-12-01", "2022-03-20", "2021-11-05",
                   "2020-08-12", "2019-04-25"],
    mixed_small: ["ABC123", "DEF456", "GHI789"],
    mixed_medium: ["ABC123", "DEF456", "GHI789", "JKL012", "MNO345", "PQR678", "STU901"],
    emails_small: ["user@example.com", "admin@test.org", "info@site.net"],
    phones_small: ["555-1234", "555-5678", "555-9012"],
    lower_only: ["abc", "def", "ghi"],
    upper_only: ["ABC", "DEF", "GHI"],
    digits_only: ["123", "456", "789"],
    heterogeneous: ["PMC123", "2023-01-15", "user@example.com", "555-1234", "ABC-def-123"]
  }

  def run do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("FlashProfile Zig NIF Performance Benchmark")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Time: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts("Iterations per test: #{@iterations}")
    IO.puts("")

    results = %{
      learn_pattern: benchmark_learn_pattern(),
      dissimilarity: benchmark_dissimilarity(),
      profile: benchmark_profile()
    }

    print_summary(results)
    results
  end

  # ===========================================================================
  # Benchmark: learn_pattern_nif/1
  # ===========================================================================

  defp benchmark_learn_pattern do
    IO.puts("-" |> String.duplicate(80))
    IO.puts("Benchmarking: FlashProfile.Native.learn_pattern_nif/1")
    IO.puts("-" |> String.duplicate(80))
    IO.puts("")

    results =
      [
        {:pmc_small, @test_data.pmc_small},
        {:pmc_medium, @test_data.pmc_medium},
        {:dates_small, @test_data.dates_small},
        {:dates_medium, @test_data.dates_medium},
        {:mixed_small, @test_data.mixed_small},
        {:mixed_medium, @test_data.mixed_medium},
        {:emails_small, @test_data.emails_small},
        {:phones_small, @test_data.phones_small},
        {:lower_only, @test_data.lower_only},
        {:upper_only, @test_data.upper_only},
        {:digits_only, @test_data.digits_only},
        {:heterogeneous, @test_data.heterogeneous}
      ]
      |> Enum.map(fn {name, data} ->
        benchmark_function(
          "learn_pattern",
          name,
          data,
          fn strings ->
            FlashProfile.Native.learn_pattern_nif(strings)
          end
        )
      end)

    IO.puts("")
    results
  end

  # ===========================================================================
  # Benchmark: dissimilarity_nif/2
  # ===========================================================================

  defp benchmark_dissimilarity do
    IO.puts("-" |> String.duplicate(80))
    IO.puts("Benchmarking: FlashProfile.Native.dissimilarity_nif/2")
    IO.puts("-" |> String.duplicate(80))
    IO.puts("")

    test_pairs = [
      {:pmc_pair, {"PMC123", "PMC456"}},
      {:date_pair, {"2023-01-15", "2024-06-30"}},
      {:mixed_pair, {"ABC123", "DEF456"}},
      {:email_pair, {"user@example.com", "admin@test.org"}},
      {:phone_pair, {"555-1234", "555-5678"}},
      {:lower_pair, {"abc", "def"}},
      {:upper_pair, {"ABC", "DEF"}},
      {:digit_pair, {"123", "456"}},
      {:similar_strings, {"hello", "hallo"}},
      {:dissimilar_strings, {"abc123", "XYZ-999"}}
    ]

    results =
      test_pairs
      |> Enum.map(fn {name, {str1, str2}} ->
        benchmark_function(
          "dissimilarity",
          name,
          {str1, str2},
          fn {s1, s2} ->
            FlashProfile.Native.dissimilarity_nif(s1, s2)
          end
        )
      end)

    IO.puts("")
    results
  end

  # ===========================================================================
  # Benchmark: profile_nif/4
  # ===========================================================================

  defp benchmark_profile do
    IO.puts("-" |> String.duplicate(80))
    IO.puts("Benchmarking: FlashProfile.Native.profile_nif/4")
    IO.puts("-" |> String.duplicate(80))
    IO.puts("")

    # Profile uses: (strings, min_patterns, max_patterns, theta)
    test_configs = [
      {:pmc_small_1_3, @test_data.pmc_small, 1, 3, 1.25},
      {:pmc_medium_1_5, @test_data.pmc_medium, 1, 5, 1.25},
      {:dates_small_1_3, @test_data.dates_small, 1, 3, 1.25},
      {:mixed_medium_1_5, @test_data.mixed_medium, 1, 5, 1.25},
      {:heterogeneous_1_10, @test_data.heterogeneous, 1, 10, 1.25},
      {:pmc_medium_tight_theta, @test_data.pmc_medium, 1, 5, 1.1},
      {:pmc_medium_loose_theta, @test_data.pmc_medium, 1, 5, 2.0}
    ]

    results =
      test_configs
      |> Enum.map(fn {name, data, min_p, max_p, theta} ->
        benchmark_function(
          "profile",
          name,
          {data, min_p, max_p, theta},
          fn {strings, min_patterns, max_patterns, th} ->
            FlashProfile.Native.profile_nif(strings, min_patterns, max_patterns, th)
          end
        )
      end)

    IO.puts("")
    results
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  defp benchmark_function(function_name, test_name, input, fun) do
    # Warm-up run
    _ = fun.(input)

    # Timed runs
    times =
      for _ <- 1..@iterations do
        {time_us, result} = :timer.tc(fun, [input])
        {time_us, result}
      end

    times_only = Enum.map(times, fn {t, _} -> t end)
    results_list = Enum.map(times, fn {_, r} -> r end)

    # Calculate statistics
    avg_us = Enum.sum(times_only) / @iterations
    min_us = Enum.min(times_only)
    max_us = Enum.max(times_only)

    # Get a representative result (first successful one)
    sample_result = Enum.at(results_list, 0)

    # Print results
    input_desc = format_input(input)
    result_desc = format_result(function_name, sample_result)

    IO.puts("Test: #{test_name}")
    IO.puts("  Input: #{input_desc}")
    IO.puts("  Avg: #{format_time(avg_us)} | Min: #{format_time(min_us)} | Max: #{format_time(max_us)}")
    IO.puts("  Result: #{result_desc}")
    IO.puts("")

    %{
      function: function_name,
      test: test_name,
      input: input,
      avg_us: avg_us,
      min_us: min_us,
      max_us: max_us,
      result: sample_result
    }
  end

  defp format_input(input) when is_list(input) do
    "#{length(input)} strings: #{inspect(Enum.take(input, 3))}#{if length(input) > 3, do: "...", else: ""}"
  end

  defp format_input({str1, str2}) when is_binary(str1) and is_binary(str2) do
    "pair: (#{inspect(str1)}, #{inspect(str2)})"
  end

  defp format_input({strings, min_p, max_p, theta}) when is_list(strings) do
    "#{length(strings)} strings, min=#{min_p}, max=#{max_p}, θ=#{theta}"
  end

  defp format_input(other), do: inspect(other)

  defp format_result("learn_pattern", {:ok, {pattern, cost}}) do
    pattern_str = Enum.join(pattern, ", ")
    "pattern=[#{pattern_str}], cost=#{Float.round(cost, 2)}"
  end

  defp format_result("learn_pattern", {:error, reason}) do
    "error: #{reason}"
  end

  defp format_result("dissimilarity", {:ok, cost}) do
    "cost=#{Float.round(cost, 2)}"
  end

  defp format_result("dissimilarity", {:error, reason}) do
    "error: #{reason}"
  end

  defp format_result("profile", {:ok, clusters}) when is_list(clusters) do
    cluster_count = length(clusters)
    total_strings = clusters |> Enum.map(&length(Map.get(&1, :indices, []))) |> Enum.sum()
    "#{cluster_count} clusters covering #{total_strings} strings"
  end

  defp format_result("profile", {:error, reason}) do
    "error: #{reason}"
  end

  defp format_result(_, result), do: inspect(result)

  defp format_time(us) when is_integer(us) and us < 1000 do
    "#{Float.round(us / 1, 1)}μs"
  end

  defp format_time(us) when is_integer(us) and us < 1_000_000 do
    "#{Float.round(us / 1000, 2)}ms"
  end

  defp format_time(us) when is_integer(us) do
    "#{Float.round(us / 1_000_000, 2)}s"
  end

  defp format_time(us) when is_float(us) and us < 1000 do
    "#{Float.round(us, 1)}μs"
  end

  defp format_time(us) when is_float(us) and us < 1_000_000 do
    "#{Float.round(us / 1000, 2)}ms"
  end

  defp format_time(us) when is_float(us) do
    "#{Float.round(us / 1_000_000, 2)}s"
  end

  defp print_summary(results) do
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Summary")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("")

    # learn_pattern summary
    learn_results = results.learn_pattern
    learn_avg = learn_results |> Enum.map(& &1.avg_us) |> Enum.sum() |> Kernel./(length(learn_results))
    learn_min = learn_results |> Enum.map(& &1.min_us) |> Enum.min()
    learn_max = learn_results |> Enum.map(& &1.max_us) |> Enum.max()

    IO.puts("learn_pattern_nif (#{length(learn_results)} tests):")
    IO.puts("  Average across all tests: #{format_time(learn_avg)}")
    IO.puts("  Fastest single run: #{format_time(learn_min)}")
    IO.puts("  Slowest single run: #{format_time(learn_max)}")
    IO.puts("")

    # dissimilarity summary
    diss_results = results.dissimilarity
    diss_avg = diss_results |> Enum.map(& &1.avg_us) |> Enum.sum() |> Kernel./(length(diss_results))
    diss_min = diss_results |> Enum.map(& &1.min_us) |> Enum.min()
    diss_max = diss_results |> Enum.map(& &1.max_us) |> Enum.max()

    IO.puts("dissimilarity_nif (#{length(diss_results)} tests):")
    IO.puts("  Average across all tests: #{format_time(diss_avg)}")
    IO.puts("  Fastest single run: #{format_time(diss_min)}")
    IO.puts("  Slowest single run: #{format_time(diss_max)}")
    IO.puts("")

    # profile summary
    prof_results = results.profile
    prof_avg = prof_results |> Enum.map(& &1.avg_us) |> Enum.sum() |> Kernel./(length(prof_results))
    prof_min = prof_results |> Enum.map(& &1.min_us) |> Enum.min()
    prof_max = prof_results |> Enum.map(& &1.max_us) |> Enum.max()

    IO.puts("profile_nif (#{length(prof_results)} tests):")
    IO.puts("  Average across all tests: #{format_time(prof_avg)}")
    IO.puts("  Fastest single run: #{format_time(prof_min)}")
    IO.puts("  Slowest single run: #{format_time(prof_max)}")
    IO.puts("")

    # Overall summary
    total_tests = length(learn_results) + length(diss_results) + length(prof_results)
    total_avg = (learn_avg + diss_avg + prof_avg) / 3

    IO.puts("Overall:")
    IO.puts("  Total tests run: #{total_tests}")
    IO.puts("  Average time per operation: #{format_time(total_avg)}")
    IO.puts("")
  end
end

# Run the benchmark
ZigBenchmark.run()
