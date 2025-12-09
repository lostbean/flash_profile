defmodule FlashProfile.CostModel do
  @moduledoc """
  Cost model for evaluating and comparing patterns.

  The cost model balances multiple factors:
  - **Coverage**: How many values does the pattern match?
  - **Precision**: How specific is the pattern? (Would it match invalid values?)
  - **Complexity**: How complex is the pattern to understand?
  - **Interpretability**: How useful is the pattern for humans?

  ## Scoring

  Patterns are scored on a scale where lower is better.
  The total score combines weighted factors:

      score = w_coverage * (1 - coverage) +
              w_precision * (1 - precision) +
              w_complexity * complexity +
              w_interpretability * (1 - interpretability)
  """

  alias FlashProfile.Pattern

  @type weights :: %{
          coverage: float(),
          precision: float(),
          complexity: float(),
          interpretability: float()
        }

  @default_weights %{
    coverage: 2.0,
    precision: 1.5,
    complexity: 1.0,
    interpretability: 0.5
  }

  @doc """
  Calculates the total cost score for a pattern against a dataset.

  ## Options

  - `:weights` - Custom weights for factors (default: balanced)
  - `:sample_invalid` - Sample of invalid values for precision estimation
  """
  @spec score(Pattern.t(), [String.t()], keyword()) :: float()
  def score(pattern, strings, opts \\ []) do
    weights = Keyword.get(opts, :weights, @default_weights)
    sample_invalid = Keyword.get(opts, :sample_invalid, [])

    coverage = calculate_coverage(pattern, strings)
    precision = estimate_precision(pattern, strings, sample_invalid)
    complexity = calculate_complexity(pattern)
    interpretability = calculate_interpretability(pattern)

    weights.coverage * (1.0 - coverage) +
      weights.precision * (1.0 - precision) +
      weights.complexity * complexity +
      weights.interpretability * (1.0 - interpretability)
  end

  @doc """
  Calculates pattern coverage (fraction of strings matched).
  """
  @spec calculate_coverage(Pattern.t(), [String.t()]) :: float()
  def calculate_coverage(_pattern, []), do: 0.0

  def calculate_coverage(pattern, strings) do
    regex = compile_pattern(pattern)

    matched = Enum.count(strings, &Regex.match?(regex, &1))
    matched / length(strings)
  end

  @doc """
  Estimates pattern precision.

  Precision = P(valid | matched)

  Without knowing all possible invalid values, we estimate based on:
  1. Pattern specificity (from the pattern structure)
  2. Testing against sample invalid values if provided
  """
  @spec estimate_precision(Pattern.t(), [String.t()], [String.t()]) :: float()
  def estimate_precision(pattern, valid_strings, invalid_samples) do
    base_precision = Pattern.specificity(pattern)

    if invalid_samples == [] do
      base_precision
    else
      # Empirical precision from samples
      regex = compile_pattern(pattern)
      valid_matched = Enum.count(valid_strings, &Regex.match?(regex, &1))
      invalid_matched = Enum.count(invalid_samples, &Regex.match?(regex, &1))
      total_matched = valid_matched + invalid_matched

      if total_matched == 0 do
        base_precision
      else
        empirical = valid_matched / total_matched
        # Combine with base estimate
        (base_precision + empirical) / 2
      end
    end
  end

  @doc """
  Calculates pattern complexity (normalized to 0-1 range).
  """
  @spec calculate_complexity(Pattern.t()) :: float()
  def calculate_complexity(pattern) do
    raw_cost = Pattern.cost(pattern)
    # Normalize: assume max reasonable cost is 50
    min(raw_cost / 50.0, 1.0)
  end

  @doc """
  Calculates pattern interpretability (how readable is it).
  """
  @spec calculate_interpretability(Pattern.t()) :: float()
  def calculate_interpretability(pattern) do
    # Count pattern elements
    element_count = count_elements(pattern)
    _enum_count = count_enums(pattern)
    max_enum_size = max_enum_size(pattern)

    cond do
      # Very simple patterns are highly interpretable
      element_count <= 3 and max_enum_size <= 5 -> 1.0
      element_count <= 5 and max_enum_size <= 10 -> 0.8
      element_count <= 7 and max_enum_size <= 15 -> 0.6
      # Complex patterns are less interpretable
      element_count > 10 or max_enum_size > 30 -> 0.3
      true -> 0.5
    end
  end

  defp count_elements({:seq, patterns}), do: length(patterns)
  defp count_elements({:optional, p}), do: 1 + count_elements(p)
  defp count_elements(_), do: 1

  defp count_enums({:seq, patterns}), do: Enum.sum(Enum.map(patterns, &count_enums/1))
  defp count_enums({:enum, _}), do: 1
  defp count_enums({:optional, p}), do: count_enums(p)
  defp count_enums(_), do: 0

  defp max_enum_size({:seq, patterns}),
    do: Enum.max(Enum.map(patterns, &max_enum_size/1), fn -> 0 end)

  defp max_enum_size({:enum, values}), do: length(values)
  defp max_enum_size({:optional, p}), do: max_enum_size(p)
  defp max_enum_size(_), do: 0

  defp compile_pattern(pattern) do
    regex_str = "^" <> Pattern.to_regex(pattern) <> "$"
    {:ok, regex} = Regex.compile(regex_str)
    regex
  end

  @doc """
  Compares two patterns and returns the better one for the given data.
  """
  @spec compare(Pattern.t(), Pattern.t(), [String.t()], keyword()) ::
          {:first, float()} | {:second, float()} | {:tie, float()}
  def compare(pattern1, pattern2, strings, opts \\ []) do
    score1 = score(pattern1, strings, opts)
    score2 = score(pattern2, strings, opts)

    cond do
      abs(score1 - score2) < 0.01 -> {:tie, score1}
      score1 < score2 -> {:first, score1}
      true -> {:second, score2}
    end
  end

  @doc """
  Ranks multiple patterns by their scores.
  """
  @spec rank([Pattern.t()], [String.t()], keyword()) :: [{Pattern.t(), float()}]
  def rank(patterns, strings, opts \\ []) do
    patterns
    |> Enum.map(fn p -> {p, score(p, strings, opts)} end)
    |> Enum.sort_by(fn {_, s} -> s end)
  end

  @doc """
  Generates a detailed evaluation report for a pattern.
  """
  @spec evaluate(Pattern.t(), [String.t()], keyword()) :: map()
  def evaluate(pattern, strings, opts \\ []) do
    sample_invalid = Keyword.get(opts, :sample_invalid, [])

    coverage = calculate_coverage(pattern, strings)
    precision = estimate_precision(pattern, strings, sample_invalid)
    complexity = calculate_complexity(pattern)
    interpretability = calculate_interpretability(pattern)

    regex = compile_pattern(pattern)
    matched = Enum.filter(strings, &Regex.match?(regex, &1))
    unmatched = Enum.reject(strings, &Regex.match?(regex, &1))

    %{
      pattern: pattern,
      regex: Pattern.to_regex(pattern),
      pretty: Pattern.pretty(pattern),
      metrics: %{
        coverage: coverage,
        precision: precision,
        complexity: complexity,
        interpretability: interpretability,
        total_score: score(pattern, strings, opts)
      },
      stats: %{
        total_strings: length(strings),
        matched_count: length(matched),
        unmatched_count: length(unmatched),
        unmatched_sample: Enum.take(unmatched, 5)
      }
    }
  end

  @doc """
  Suggests threshold for enumeration vs. generalization.

  Based on:
  - Total distinct values
  - Value frequency distribution
  - Pattern context
  """
  @spec suggest_enum_threshold([String.t()]) :: pos_integer()
  def suggest_enum_threshold(values) do
    distinct = Enum.uniq(values)
    distinct_count = length(distinct)
    total_count = length(values)

    # Calculate frequency distribution
    freq = Enum.frequencies(values)
    _max_freq = freq |> Map.values() |> Enum.max(fn -> 1 end)
    avg_freq = total_count / max(distinct_count, 1)

    cond do
      # Very categorical: few values, high repetition
      distinct_count <= 10 and avg_freq >= 3 -> distinct_count + 5
      # Semi-categorical: moderate values, some repetition
      distinct_count <= 30 and avg_freq >= 2 -> 10
      # High cardinality: many values
      distinct_count <= 100 -> 5
      # Very high cardinality
      true -> 3
    end
  end
end
