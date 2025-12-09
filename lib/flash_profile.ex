defmodule FlashProfile do
  @moduledoc """
  FlashProfile - Automatic regex pattern discovery for string columns.

  Given a column of string values, FlashProfile discovers regex patterns that
  accurately describe the structural format of the data.

  ## Features

  - **Automatic clustering**: Groups strings by structural similarity
  - **Smart enumeration**: Enumerates categorical values, generalizes high-cardinality data
  - **Cost-optimized patterns**: Balances specificity, coverage, and complexity
  - **Anomaly detection**: Identifies outliers that don't match the main patterns

  ## Usage

      # Basic profiling
      {:ok, profile} = FlashProfile.profile(["ACC-001", "ACC-002", "ORG-003"])
      
      # Get the regex patterns
      patterns = FlashProfile.patterns(profile)
      
      # Validate new values
      FlashProfile.validate(profile, "ACC-999")  # => :ok
      FlashProfile.validate(profile, "INVALID")  # => {:error, :no_match}
      
      # Find anomalies
      anomalies = FlashProfile.anomalies(profile)

  ## Options

  - `:max_clusters` - Maximum number of pattern clusters (default: 5)
  - `:min_coverage` - Minimum coverage for a pattern to be included (default: 0.01)
  - `:enum_threshold` - Max distinct values before generalizing (default: 10)
  - `:detect_anomalies` - Whether to identify anomalies (default: true)
  """

  alias FlashProfile.{Clustering, PatternSynthesizer, Pattern}

  @type profile :: %{
          patterns: [pattern_info()],
          anomalies: [String.t()],
          stats: profile_stats(),
          options: keyword()
        }

  @type pattern_info :: %{
          pattern: Pattern.t(),
          regex: String.t(),
          coverage: float(),
          matched_count: non_neg_integer(),
          members: [String.t()]
        }

  @type profile_stats :: %{
          total_values: non_neg_integer(),
          distinct_values: non_neg_integer(),
          pattern_count: non_neg_integer(),
          total_coverage: float(),
          anomaly_count: non_neg_integer()
        }

  @default_opts [
    max_clusters: 5,
    min_coverage: 0.01,
    enum_threshold: 10,
    detect_anomalies: true,
    length_tolerance: 0.2
  ]

  @doc """
  Profiles a column of string values.

  Returns a profile containing:
  - Discovered patterns with coverage statistics
  - Anomalies (values that don't match any pattern)
  - Overall statistics

  ## Examples

      iex> {:ok, profile} = FlashProfile.profile(["active", "pending", "completed"])
      iex> hd(profile.patterns).regex
      "(active|completed|pending)"
      
      iex> {:ok, profile} = FlashProfile.profile(["ACC-001", "ACC-002", "ORG-123"])
      iex> hd(profile.patterns).regex
      "(ACC|ORG)-\\\\d{3}"
  """
  @spec profile([String.t()], keyword()) :: {:ok, profile()} | {:error, term()}
  def profile(strings, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    with {:ok, strings} <- validate_input(strings) do
      do_profile(strings, opts)
    end
  end

  @doc """
  Profiles a column and returns the result directly (raises on error).
  """
  @spec profile!([String.t()], keyword()) :: profile()
  def profile!(strings, opts \\ []) do
    case profile(strings, opts) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, "Failed to profile: #{inspect(reason)}"
    end
  end

  defp validate_input([]), do: {:error, :empty_input}

  defp validate_input(strings) when is_list(strings) do
    if Enum.all?(strings, &is_binary/1) do
      {:ok, strings}
    else
      {:error, :non_string_values}
    end
  end

  defp validate_input(_), do: {:error, :not_a_list}

  defp do_profile(strings, opts) do
    max_clusters = Keyword.get(opts, :max_clusters)
    min_coverage = Keyword.get(opts, :min_coverage)
    enum_threshold = Keyword.get(opts, :enum_threshold)
    detect_anomalies = Keyword.get(opts, :detect_anomalies)

    # Check for categorical column (few distinct values)
    distinct_values = Enum.uniq(strings)
    distinct_count = length(distinct_values)

    # If highly categorical, just enumerate all values
    if distinct_count <= enum_threshold do
      pattern = Pattern.enum(distinct_values)
      pattern_info = build_pattern_info(pattern, strings, strings)

      {:ok,
       %{
         patterns: [pattern_info],
         anomalies: [],
         stats: build_stats(strings, [pattern_info], []),
         options: opts
       }}
    else
      # Cluster and synthesize patterns
      clusters = Clustering.cluster(strings, max_clusters: max_clusters)

      # Synthesize pattern for each cluster
      pattern_infos =
        clusters
        |> Enum.map(fn cluster ->
          {pattern, _eval} =
            PatternSynthesizer.synthesize_best(cluster.members, enum_threshold: enum_threshold)

          build_pattern_info(pattern, cluster.members, strings)
        end)
        |> Enum.filter(fn info -> info.coverage >= min_coverage end)
        |> Enum.sort_by(& &1.coverage, :desc)

      # Find anomalies
      anomalies =
        if detect_anomalies do
          find_anomalies(strings, pattern_infos)
        else
          []
        end

      {:ok,
       %{
         patterns: pattern_infos,
         anomalies: anomalies,
         stats: build_stats(strings, pattern_infos, anomalies),
         options: opts
       }}
    end
  end

  defp build_pattern_info(pattern, members, all_strings) do
    regex_str = Pattern.to_regex(pattern)
    full_regex_str = "^" <> regex_str <> "$"
    {:ok, regex} = Regex.compile(full_regex_str)

    matched = Enum.filter(all_strings, &Regex.match?(regex, &1))
    coverage = length(matched) / length(all_strings)

    %{
      pattern: pattern,
      regex: regex_str,
      pretty: Pattern.pretty(pattern),
      coverage: coverage,
      matched_count: length(matched),
      members: members,
      cost: Pattern.cost(pattern),
      specificity: Pattern.specificity(pattern)
    }
  end

  defp build_stats(strings, pattern_infos, anomalies) do
    total_matched =
      pattern_infos
      |> Enum.map(& &1.matched_count)
      |> Enum.sum()
      |> min(length(strings))

    %{
      total_values: length(strings),
      distinct_values: strings |> Enum.uniq() |> length(),
      pattern_count: length(pattern_infos),
      total_coverage: min(total_matched / length(strings), 1.0),
      anomaly_count: length(anomalies)
    }
  end

  defp find_anomalies(strings, pattern_infos) do
    regexes =
      Enum.map(pattern_infos, fn info ->
        {:ok, regex} = Regex.compile("^" <> info.regex <> "$")
        regex
      end)

    Enum.filter(strings, fn string ->
      not Enum.any?(regexes, &Regex.match?(&1, string))
    end)
  end

  @doc """
  Returns just the patterns from a profile.
  """
  @spec patterns(profile()) :: [Pattern.t()]
  def patterns(%{patterns: pattern_infos}) do
    Enum.map(pattern_infos, & &1.pattern)
  end

  @doc """
  Returns the regex strings from a profile.
  """
  @spec regexes(profile()) :: [String.t()]
  def regexes(%{patterns: pattern_infos}) do
    Enum.map(pattern_infos, & &1.regex)
  end

  @doc """
  Validates a value against the profile patterns.

  Returns `:ok` if the value matches at least one pattern,
  or `{:error, :no_match}` if it doesn't match any.
  """
  @spec validate(profile(), String.t()) :: :ok | {:error, :no_match}
  def validate(%{patterns: pattern_infos}, value) do
    matched =
      Enum.any?(pattern_infos, fn info ->
        {:ok, regex} = Regex.compile("^" <> info.regex <> "$")
        Regex.match?(regex, value)
      end)

    if matched, do: :ok, else: {:error, :no_match}
  end

  @doc """
  Returns the anomalies from a profile.
  """
  @spec anomalies(profile()) :: [String.t()]
  def anomalies(%{anomalies: anomalies}), do: anomalies

  @doc """
  Returns a summary of the profile.
  """
  @spec summary(profile()) :: String.t()
  def summary(%{patterns: patterns, stats: stats, anomalies: anomalies}) do
    pattern_lines =
      patterns
      |> Enum.with_index(1)
      |> Enum.map(fn {info, idx} ->
        "  #{idx}. #{info.regex} (#{Float.round(info.coverage * 100, 1)}% coverage)"
      end)

    anomaly_section =
      if length(anomalies) > 0 do
        samples = anomalies |> Enum.take(5) |> Enum.map(&"    - #{inspect(&1)}")

        [
          "",
          "Anomalies (#{length(anomalies)} values):",
          Enum.join(samples, "\n")
        ]
        |> Enum.join("\n")
      else
        ""
      end

    """
    Profile Summary
    ===============
    Total values: #{stats.total_values}
    Distinct values: #{stats.distinct_values}
    Pattern coverage: #{Float.round(stats.total_coverage * 100, 1)}%

    Patterns (#{stats.pattern_count}):
    #{Enum.join(pattern_lines, "\n")}
    #{anomaly_section}
    """
  end

  @doc """
  Merges two profiles into one.

  Useful when profiling data in batches.
  """
  @spec merge(profile(), profile()) :: profile()
  def merge(profile1, profile2) do
    all_strings =
      (Enum.flat_map(profile1.patterns, & &1.members) ++
         Enum.flat_map(profile2.patterns, & &1.members))
      |> Enum.uniq()

    # Re-profile the combined data
    profile!(all_strings, profile1.options)
  end

  @doc """
  Exports the profile patterns as a map suitable for serialization.
  """
  @spec export(profile()) :: map()
  def export(%{patterns: patterns, stats: stats}) do
    %{
      patterns:
        Enum.map(patterns, fn info ->
          %{
            regex: info.regex,
            pretty: info.pretty,
            coverage: info.coverage,
            matched_count: info.matched_count,
            specificity: info.specificity
          }
        end),
      stats: stats
    }
  end

  @doc """
  Quickly infers a single pattern for a list of strings.

  For simple use cases where you just need one pattern.
  """
  @spec infer_pattern([String.t()], keyword()) :: Pattern.t()
  def infer_pattern(strings, opts \\ []) do
    enum_threshold = Keyword.get(opts, :enum_threshold, 10)
    PatternSynthesizer.synthesize(strings, enum_threshold: enum_threshold)
  end

  @doc """
  Quickly infers a regex string for a list of strings.
  """
  @spec infer_regex([String.t()], keyword()) :: String.t()
  def infer_regex(strings, opts \\ []) do
    strings
    |> infer_pattern(opts)
    |> Pattern.to_regex()
  end
end
