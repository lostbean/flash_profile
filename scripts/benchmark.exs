# FlashProfile Performance Benchmark
# Usage:
#   mix run scripts/benchmark.exs                    # Run with Zig backend (default)
#   FLASH_PROFILE_BACKEND=elixir mix run scripts/benchmark.exs  # Run with pure Elixir

defmodule Benchmark do
  @fixtures_dir Path.join([__DIR__, "..", "test", "fixtures", "flash_profile_demo"])

  # Default datasets - quick benchmark
  @datasets [
    {"phones.json", :small},
    {"bool.json", :small},
    {"dates.json", :medium},
    {"emails.json", :small},
    {"hetero_dates.json", :small}
    # Excluded by default (take longer):
    # {"us_canada_zip_codes.json", :medium},
    # {"motivating_example.json", :large}
    # {"ipv4.json", :scale}
  ]

  def run do
    backend = FlashProfile.Config.backend()
    IO.puts("=== FlashProfile Performance Benchmark ===")
    IO.puts("Backend: #{backend}")
    IO.puts("Time: #{DateTime.utc_now() |> DateTime.to_string()}")
    IO.puts("")

    results =
      @datasets
      |> Enum.map(fn {filename, size} ->
        data = load_fixture(filename)
        count = length(data)
        IO.puts("Dataset: #{filename} (#{count} strings, #{size})")

        # Warm up - run once to ensure code is loaded
        _ = FlashProfile.learn_pattern(Enum.take(data, 3))

        # Benchmark learn_pattern
        {learn_time, result} = :timer.tc(fn ->
          FlashProfile.learn_pattern(data)
        end)
        learn_ms = learn_time / 1000

        {pattern, cost} =
          case result do
            {p, c} when is_float(c) -> {p, c}
            :no_pattern -> {nil, 0.0}
            _ -> {nil, 0.0}
          end

        IO.puts("  learn_pattern: #{Float.round(learn_ms, 2)}ms (cost: #{Float.round(cost, 2)})")

        # Benchmark profile (only for heterogeneous data or medium+ size)
        profile_ms =
          if size in [:medium, :large] or String.contains?(filename, "hetero") do
            {profile_time, profile_result} = :timer.tc(fn ->
              FlashProfile.profile(data)
            end)
            ms = profile_time / 1000
            cluster_count = length(profile_result)
            IO.puts("  profile:       #{Float.round(ms, 2)}ms (#{cluster_count} clusters)")
            ms
          else
            nil
          end

        IO.puts("")

        %{
          dataset: filename,
          size: size,
          count: count,
          learn_ms: learn_ms,
          profile_ms: profile_ms,
          pattern: pattern,
          cost: cost
        }
      end)

    # Summary
    IO.puts("=== Summary ===")
    total_learn = results |> Enum.map(& &1.learn_ms) |> Enum.sum()
    total_profile = results |> Enum.map(& &1.profile_ms) |> Enum.reject(&is_nil/1) |> Enum.sum()
    IO.puts("Total learn_pattern time: #{Float.round(total_learn, 2)}ms")
    IO.puts("Total profile time: #{Float.round(total_profile, 2)}ms")
    IO.puts("Total time: #{Float.round(total_learn + total_profile, 2)}ms")

    results
  end

  def run_with_ipv4 do
    IO.puts("=== Running with IPv4 dataset (scale test) ===")
    IO.puts("Backend: #{FlashProfile.Config.backend()}")
    IO.puts("")

    data = load_fixture("ipv4.json")
    count = length(data)
    IO.puts("Dataset: ipv4.json (#{count} strings)")

    {learn_time, result} = :timer.tc(fn ->
      FlashProfile.learn_pattern(data)
    end)
    cost = case result do
      {_, c} when is_float(c) -> c
      _ -> 0.0
    end
    IO.puts("  learn_pattern: #{Float.round(learn_time / 1000, 2)}ms (cost: #{Float.round(cost, 2)})")
  end

  defp load_fixture(filename) do
    path = Path.join(@fixtures_dir, filename)
    {:ok, content} = File.read(path)
    # Use OTP 27+ built-in JSON decoder
    fixture = :json.decode(content)
    Map.get(fixture, "Data", [])
  end
end

# Run the benchmark
Benchmark.run()
