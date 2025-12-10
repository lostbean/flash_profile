defmodule FlashProfile.Pattern do
  @moduledoc """
  Pattern DSL for representing regex-like patterns.

  This module defines a domain-specific language for patterns that can be:
  - Composed hierarchically
  - Evaluated for cost/complexity
  - Compiled to regex strings
  - Rendered for human readability

  ## Pattern Types

  - `literal(string)` - Exact string match
  - `char_class(type, min, max)` - Character class with repetition
  - `enum(values)` - Enumeration of alternatives
  - `seq(patterns)` - Sequence of patterns
  - `optional(pattern)` - Optional pattern (0 or 1)
  - `any()` - Wildcard (.+)
  """

  @type char_class_type :: :digit | :upper | :lower | :alpha | :alnum | :word | :any

  @type t ::
          {:literal, String.t()}
          | {:char_class, char_class_type(), pos_integer(), pos_integer() | :inf}
          | {:enum, [String.t()]}
          | {:seq, [t()]}
          | {:optional, t()}
          | {:any, pos_integer(), pos_integer() | :inf}

  # Constructors

  @doc "Creates a literal pattern."
  @spec literal(String.t()) :: t()
  def literal(string) when is_binary(string), do: {:literal, string}

  @doc "Creates a character class pattern with repetition bounds."
  @spec char_class(char_class_type(), pos_integer(), pos_integer() | :inf) :: t()
  def char_class(type, min \\ 1, max \\ 1) when is_atom(type) do
    {:char_class, type, min, max}
  end

  @doc "Creates an enumeration pattern."
  @spec enum([String.t()]) :: t()
  def enum(values) when is_list(values) do
    sorted = values |> Enum.uniq() |> Enum.sort()
    {:enum, sorted}
  end

  @doc "Creates a sequence pattern."
  @spec seq([t()]) :: t()
  def seq([single]), do: single
  def seq(patterns) when is_list(patterns), do: {:seq, patterns}

  @doc "Creates an optional pattern."
  @spec optional(t()) :: t()
  def optional(pattern), do: {:optional, pattern}

  @doc "Creates a wildcard pattern."
  @spec any(pos_integer(), pos_integer() | :inf) :: t()
  def any(min \\ 1, max \\ :inf), do: {:any, min, max}

  # Compilation to regex string

  @doc """
  Compiles a pattern to a regex string.

  ## Examples

      iex> Pattern.to_regex({:literal, "hello"})
      "hello"
      
      iex> Pattern.to_regex({:char_class, :digit, 3, 3})
      "\\\\d{3}"
      
      iex> Pattern.to_regex({:enum, ["ACC", "ORG"]})
      "(ACC|ORG)"
  """
  @spec to_regex(t()) :: String.t()
  def to_regex({:literal, string}) do
    Regex.escape(string)
  end

  def to_regex({:char_class, type, min, max}) do
    class = char_class_regex(type)
    quantifier = quantifier_regex(min, max)
    class <> quantifier
  end

  def to_regex({:enum, [single]}) do
    Regex.escape(single)
  end

  def to_regex({:enum, values}) do
    escaped = Enum.map(values, &Regex.escape/1)
    "(" <> Enum.join(escaped, "|") <> ")"
  end

  def to_regex({:seq, patterns}) do
    patterns
    |> Enum.map(&to_regex/1)
    |> Enum.join()
  end

  def to_regex({:optional, pattern}) do
    inner = to_regex(pattern)

    if needs_grouping?(pattern) do
      "(" <> inner <> ")?"
    else
      inner <> "?"
    end
  end

  def to_regex({:any, min, max}) do
    "." <> quantifier_regex(min, max)
  end

  defp char_class_regex(:digit), do: "\\d"
  defp char_class_regex(:upper), do: "[A-Z]"
  defp char_class_regex(:lower), do: "[a-z]"
  defp char_class_regex(:alpha), do: "[a-zA-Z]"
  defp char_class_regex(:alnum), do: "[a-zA-Z0-9]"
  defp char_class_regex(:word), do: "\\w"
  defp char_class_regex(:any), do: "."

  defp quantifier_regex(1, 1), do: ""
  defp quantifier_regex(0, 1), do: "?"
  defp quantifier_regex(0, :inf), do: "*"
  defp quantifier_regex(1, :inf), do: "+"
  defp quantifier_regex(n, n), do: "{#{n}}"
  defp quantifier_regex(min, :inf), do: "{#{min},}"
  defp quantifier_regex(min, max), do: "{#{min},#{max}}"

  defp needs_grouping?({:seq, _}), do: true
  defp needs_grouping?({:enum, values}) when length(values) > 1, do: true
  defp needs_grouping?(_), do: false

  # Cost calculation

  @doc """
  Calculates the cost of a pattern.

  Lower cost = better pattern. Factors:
  - Specificity: overly specific patterns (large enums) are penalized
  - Generality: overly general patterns (wildcards) are penalized
  - Complexity: more complex patterns cost more
  """
  @spec cost(t()) :: float()
  def cost({:literal, string}) do
    # Literals are cheap but become costly for long strings
    min(1.0 + String.length(string) * 0.1, 5.0)
  end

  def cost({:char_class, type, min, max}) do
    base = char_class_base_cost(type)
    range_cost = range_cost(min, max)
    base + range_cost
  end

  def cost({:enum, values}) do
    count = length(values)

    cond do
      count == 1 -> 1.0
      count <= 5 -> 1.0 + count * 0.2
      count <= 10 -> 2.0 + count * 0.3
      count <= 20 -> 4.0 + count * 0.4
      # Large enums are heavily penalized
      true -> 10.0 + count * 0.5
    end
  end

  def cost({:seq, patterns}) do
    patterns
    |> Enum.map(&cost/1)
    |> Enum.sum()
  end

  def cost({:optional, pattern}) do
    cost(pattern) + 0.5
  end

  def cost({:any, _min, _max}) do
    # Wildcards are expensive - prefer specific patterns
    10.0
  end

  defp char_class_base_cost(:digit), do: 1.0
  defp char_class_base_cost(:upper), do: 1.5
  defp char_class_base_cost(:lower), do: 1.5
  defp char_class_base_cost(:alpha), do: 2.0
  defp char_class_base_cost(:alnum), do: 2.5
  defp char_class_base_cost(:word), do: 3.0
  defp char_class_base_cost(:any), do: 5.0

  defp range_cost(n, n) when is_integer(n), do: 0.0
  defp range_cost(_, :inf), do: 1.0
  defp range_cost(min, max), do: 0.5 + (max - min) * 0.1

  # Pattern analysis

  @doc """
  Checks if a pattern matches a string.

  Returns `false` and logs a warning if the pattern cannot be compiled to a valid regex.
  """
  @spec matches?(t(), String.t()) :: boolean()
  def matches?(pattern, string) do
    regex_str = "^" <> to_regex(pattern) <> "$"

    case Regex.compile(regex_str) do
      {:ok, regex} ->
        Regex.match?(regex, string)

      {:error, reason} ->
        require Logger
        Logger.warning("Pattern compilation failed: #{inspect(reason)} for regex: #{regex_str}")
        false
    end
  end

  @doc """
  Returns the specificity of a pattern (0.0 = very general, 1.0 = very specific).
  """
  @spec specificity(t()) :: float()
  def specificity({:literal, _}), do: 1.0

  def specificity({:char_class, :digit, n, n}), do: 0.9
  def specificity({:char_class, :upper, n, n}), do: 0.85
  def specificity({:char_class, :lower, n, n}), do: 0.85
  def specificity({:char_class, :alpha, n, n}), do: 0.7
  def specificity({:char_class, :alnum, n, n}), do: 0.6
  def specificity({:char_class, _, _, _}), do: 0.5

  def specificity({:enum, values}) do
    count = length(values)

    cond do
      count == 1 -> 1.0
      count <= 5 -> 0.9
      count <= 10 -> 0.7
      count <= 20 -> 0.5
      true -> 0.3
    end
  end

  def specificity({:seq, patterns}) do
    patterns
    |> Enum.map(&specificity/1)
    |> Enum.sum()
    |> Kernel./(length(patterns))
  end

  def specificity({:optional, pattern}) do
    specificity(pattern) * 0.8
  end

  def specificity({:any, _, _}), do: 0.1

  @doc """
  Pretty prints a pattern for human readability.
  """
  @spec pretty(t()) :: String.t()
  def pretty({:literal, string}), do: inspect(string)

  def pretty({:char_class, type, min, max}) do
    type_str = Atom.to_string(type)
    range_str = format_range(min, max)
    "<#{type_str}#{range_str}>"
  end

  def pretty({:enum, values}) when length(values) <= 5 do
    "{" <> Enum.join(values, "|") <> "}"
  end

  def pretty({:enum, values}) do
    first_few = Enum.take(values, 3)
    "{" <> Enum.join(first_few, "|") <> "|...(#{length(values)} values)}"
  end

  def pretty({:seq, patterns}) do
    patterns
    |> Enum.map(&pretty/1)
    |> Enum.join(" ")
  end

  def pretty({:optional, pattern}) do
    "[" <> pretty(pattern) <> "]?"
  end

  def pretty({:any, min, max}) do
    "<any#{format_range(min, max)}>"
  end

  defp format_range(n, n), do: "{#{n}}"
  defp format_range(min, :inf), do: "{#{min}+}"
  defp format_range(min, max), do: "{#{min}-#{max}}"
end
