defmodule FlashProfile.PatternSynthesizer do
  @moduledoc """
  Synthesizes optimal regex patterns for string clusters.

  This is the core algorithm that decides when to:
  - Enumerate values vs. use character classes
  - Use fixed length vs. variable length quantifiers
  - Merge similar token positions

  The synthesis follows the FlashProfile approach:
  1. Align tokens across all strings in a cluster
  2. For each position, decide the best pattern element
  3. Compose into a sequence pattern
  4. Optimize by merging adjacent similar elements
  """

  alias FlashProfile.{Token, Tokenizer, Pattern}

  @type synthesis_opts :: [
          enum_threshold: pos_integer(),
          length_tolerance: float(),
          prefer_specificity: boolean()
        ]

  @doc """
  Synthesizes the best pattern for a list of strings.

  ## Options

  - `:enum_threshold` - Max distinct values before switching to char class (default: 10)
  - `:length_tolerance` - Tolerance for length variation (default: 0.2)
  - `:prefer_specificity` - Prefer specific patterns over general (default: true)

  ## Examples

      iex> pattern = FlashProfile.PatternSynthesizer.synthesize(["A", "B", "C"])
      iex> FlashProfile.Pattern.to_regex(pattern)
      "(A|B|C)"

      iex> data = for p <- ["ACC", "ORG"], n <- 1..10, do: p <> "-" <> String.pad_leading(to_string(n), 3, "0")
      iex> pattern = FlashProfile.PatternSynthesizer.synthesize(data)
      iex> FlashProfile.Pattern.to_regex(pattern)
      "(ACC|ORG)\\\\-\\\\d{3}"
  """
  @spec synthesize([String.t()], synthesis_opts()) :: Pattern.t()
  def synthesize(strings, opts \\ []) when is_list(strings) and length(strings) > 0 do
    enum_threshold = Keyword.get(opts, :enum_threshold, 10)
    length_tolerance = Keyword.get(opts, :length_tolerance, 0.2)

    # Tokenize all strings
    token_lists = Enum.map(strings, &Tokenizer.tokenize/1)

    # Align tokens by position
    aligned = align_tokens(token_lists)

    # Synthesize pattern for each position
    position_patterns =
      aligned
      |> Enum.map(fn position_tokens ->
        synthesize_position(position_tokens, enum_threshold, length_tolerance)
      end)

    # Compose into sequence and optimize
    position_patterns
    |> Pattern.seq()
    |> optimize_pattern()
  end

  @doc """
  Aligns tokens across multiple tokenized strings.

  Returns a list of lists, where each inner list contains all tokens
  that appear at that position across all strings.
  """
  @spec align_tokens([[Token.t()]]) :: [[Token.t()]]
  def align_tokens(token_lists) do
    max_len = token_lists |> Enum.map(&length/1) |> Enum.max()

    0..(max_len - 1)
    |> Enum.map(fn idx ->
      token_lists
      |> Enum.map(&Enum.at(&1, idx))
      |> Enum.filter(&(&1 != nil))
    end)
  end

  @doc """
  Synthesizes a pattern element for a single token position.
  """
  @spec synthesize_position([Token.t()], pos_integer(), float()) :: Pattern.t()
  def synthesize_position(tokens, enum_threshold, length_tolerance) do
    # Group tokens by type
    by_type = Enum.group_by(tokens, & &1.type)
    types = Map.keys(by_type)

    cond do
      # Single type - straightforward case
      length(types) == 1 ->
        [type] = types
        type_tokens = Map.get(by_type, type)
        synthesize_single_type(type, type_tokens, enum_threshold, length_tolerance)

      # Mixed upper/lower - could be :alpha
      types -- [:upper, :lower] == [] ->
        all_tokens = List.flatten(Map.values(by_type))
        synthesize_alpha_tokens(all_tokens, enum_threshold, length_tolerance)

      # Multiple types - need alternation or generalization
      true ->
        synthesize_mixed_types(by_type, enum_threshold)
    end
  end

  defp synthesize_single_type(:delimiter, tokens, _enum_threshold, _tolerance) do
    values = tokens |> Enum.map(& &1.value) |> Enum.uniq()

    case values do
      [single] -> Pattern.literal(single)
      multiple -> Pattern.enum(multiple)
    end
  end

  defp synthesize_single_type(:whitespace, tokens, _enum_threshold, _tolerance) do
    lengths = tokens |> Enum.map(& &1.length)
    {min_len, max_len} = {Enum.min(lengths), Enum.max(lengths)}

    if min_len == max_len do
      Pattern.literal(String.duplicate(" ", min_len))
    else
      Pattern.char_class(:any, min_len, max_len)
    end
  end

  defp synthesize_single_type(:literal, tokens, enum_threshold, _tolerance) do
    values = tokens |> Enum.map(& &1.value) |> Enum.uniq()

    if length(values) <= enum_threshold do
      Pattern.enum(values)
    else
      # Fall back to any
      lengths = Enum.map(tokens, & &1.length)
      Pattern.any(Enum.min(lengths), Enum.max(lengths))
    end
  end

  defp synthesize_single_type(type, tokens, enum_threshold, length_tolerance) do
    values = tokens |> Enum.map(& &1.value) |> Enum.uniq()
    lengths = tokens |> Enum.map(& &1.length)
    distinct_count = length(values)

    # Decide: enumerate or generalize?
    should_enumerate = should_enumerate?(distinct_count, length(tokens), enum_threshold)

    if should_enumerate do
      Pattern.enum(values)
    else
      # Use character class with appropriate length bounds
      {min_len, max_len} = length_bounds(lengths, length_tolerance)
      char_class_type = token_type_to_char_class(type)
      Pattern.char_class(char_class_type, min_len, max_len)
    end
  end

  defp synthesize_alpha_tokens(tokens, enum_threshold, length_tolerance) do
    values = tokens |> Enum.map(& &1.value) |> Enum.uniq()
    lengths = tokens |> Enum.map(& &1.length)
    distinct_count = length(values)

    should_enumerate = should_enumerate?(distinct_count, length(tokens), enum_threshold)

    if should_enumerate do
      Pattern.enum(values)
    else
      {min_len, max_len} = length_bounds(lengths, length_tolerance)
      Pattern.char_class(:alpha, min_len, max_len)
    end
  end

  defp synthesize_mixed_types(by_type, enum_threshold) do
    # Collect all values across types
    all_values =
      by_type
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.value)
      |> Enum.uniq()

    if length(all_values) <= enum_threshold do
      Pattern.enum(all_values)
    else
      # Find most general type that covers all
      lengths =
        by_type
        |> Map.values()
        |> List.flatten()
        |> Enum.map(& &1.length)

      Pattern.char_class(:alnum, Enum.min(lengths), Enum.max(lengths))
    end
  end

  @doc """
  Determines whether to enumerate values or use a character class.

  Factors:
  - Distinct count vs. total count ratio
  - Absolute distinct count
  - Threshold setting
  """
  @spec should_enumerate?(pos_integer(), pos_integer(), pos_integer()) :: boolean()
  def should_enumerate?(distinct_count, total_count, threshold) do
    cond do
      # Always enumerate very small sets
      distinct_count <= 5 -> true
      # Never enumerate if exceeds threshold
      distinct_count > threshold -> false
      # Enumerate if coverage is high (same values repeat)
      distinct_count <= total_count * 0.3 -> true
      # Default: don't enumerate
      true -> false
    end
  end

  defp length_bounds(lengths, _tolerance) do
    {Enum.min(lengths), Enum.max(lengths)}
  end

  defp token_type_to_char_class(:digits), do: :digit
  defp token_type_to_char_class(:upper), do: :upper
  defp token_type_to_char_class(:lower), do: :lower
  defp token_type_to_char_class(:alpha), do: :alpha
  defp token_type_to_char_class(:alnum), do: :alnum
  defp token_type_to_char_class(_), do: :any

  @doc """
  Optimizes a pattern by merging adjacent similar elements.
  """
  @spec optimize_pattern(Pattern.t()) :: Pattern.t()
  def optimize_pattern({:seq, patterns}) do
    optimized =
      patterns
      |> merge_adjacent_literals()
      |> merge_adjacent_char_classes()

    case optimized do
      [single] -> single
      multiple -> {:seq, multiple}
    end
  end

  def optimize_pattern(pattern), do: pattern

  defp merge_adjacent_literals(patterns) do
    patterns
    |> Enum.reduce([], fn
      {:literal, s2}, [{:literal, s1} | rest] ->
        [{:literal, s1 <> s2} | rest]

      pattern, acc ->
        [pattern | acc]
    end)
    |> Enum.reverse()
  end

  defp merge_adjacent_char_classes(patterns) do
    patterns
    |> Enum.reduce([], fn
      {:char_class, type, min2, max2}, [{:char_class, type, min1, max1} | rest] ->
        # Same type - merge
        [{:char_class, type, min1 + min2, add_bounds(max1, max2)} | rest]

      pattern, acc ->
        [pattern | acc]
    end)
    |> Enum.reverse()
  end

  defp add_bounds(:inf, _), do: :inf
  defp add_bounds(_, :inf), do: :inf
  defp add_bounds(a, b), do: a + b

  @doc """
  Evaluates pattern quality against a dataset.

  Returns metrics:
  - coverage: fraction of values matched
  - precision: estimated fraction of matches that are valid
  - cost: pattern complexity cost
  """
  @spec evaluate(Pattern.t(), [String.t()]) :: map()
  def evaluate(pattern, strings) do
    regex_str = "^" <> Pattern.to_regex(pattern) <> "$"

    case Regex.compile(regex_str) do
      {:ok, regex} ->
        matches = Enum.filter(strings, &Regex.match?(regex, &1))
        coverage = length(matches) / max(length(strings), 1)

        %{
          coverage: coverage,
          matched_count: length(matches),
          total_count: length(strings),
          cost: Pattern.cost(pattern),
          specificity: Pattern.specificity(pattern),
          regex: regex_str
        }

      {:error, reason} ->
        %{
          coverage: 0.0,
          matched_count: 0,
          total_count: length(strings),
          cost: :infinity,
          specificity: 0.0,
          regex: regex_str,
          error: reason
        }
    end
  end

  @doc """
  Generates multiple candidate patterns and returns the best one.
  """
  @spec synthesize_best([String.t()], synthesis_opts()) :: {Pattern.t(), map()}
  def synthesize_best(strings, opts \\ []) do
    candidates = [
      synthesize(strings, Keyword.put(opts, :enum_threshold, 5)),
      synthesize(strings, Keyword.put(opts, :enum_threshold, 10)),
      synthesize(strings, Keyword.put(opts, :enum_threshold, 20)),
      synthesize(strings, Keyword.put(opts, :enum_threshold, 50))
    ]

    candidates
    |> Enum.map(fn pattern -> {pattern, evaluate(pattern, strings)} end)
    |> Enum.filter(fn {_, eval} -> eval.coverage >= 0.95 end)
    |> Enum.min_by(fn {_, eval} -> eval.cost end, fn ->
      List.first(candidates) |> then(&{&1, evaluate(&1, strings)})
    end)
  end
end
