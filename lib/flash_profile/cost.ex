defmodule FlashProfile.Cost do
  @moduledoc """
  Cost function for FlashProfile patterns.

  The cost balances pattern specificity vs simplicity using:
  - Static cost: intrinsic cost of each atom (from atom definition)
  - Dynamic weight: fraction of string length matched by each atom

  Lower cost = better pattern.

  ## Cost Formula

  From the FlashProfile paper (Section 4.3):

  ```
  C_FP(P, S) = Σ Q(αi) · W(i, S | P)
  ```

  Where:
  - P = [α1, α2, ..., αk] is a pattern (list of atoms)
  - Q(αi) is the static cost of atom αi
  - W(i, S | P) is the dynamic weight for atom i

  ## Dynamic Weight Formula

  ```
  W(i, S | P) = (1/|S|) · Σ_{s∈S} (αi(si) / |s|)
  ```

  Where:
  - s1 = s (the original string)
  - si+1 = si[αi(si):] (remaining suffix after matching atom αi)
  - αi(si) is the length matched by atom i on string si
  - |s| is the total length of the original string

  The dynamic weight is the average fraction of the string length matched
  by that atom across all strings in S.

  ## Cost Meaning

  - Higher cost = less desirable pattern
  - Lower cost = more desirable pattern
  - Empty pattern on empty string set has cost 0
  - If pattern doesn't match all strings, cost is :infinity
  """

  alias FlashProfile.Atom

  @type cost :: float() | :infinity
  @type pattern :: [Atom.t()]

  @doc """
  Calculate the cost of a pattern over a dataset.

  Returns :infinity if pattern doesn't match all strings in the dataset.
  Returns 0.0 for empty pattern on empty dataset.

  ## Parameters

  - `pattern` - List of atoms forming the pattern
  - `strings` - List of strings to evaluate the pattern against

  ## Returns

  - `float()` - The cost of the pattern
  - `:infinity` - If the pattern doesn't match all strings

  ## Examples

      iex> alias FlashProfile.{Cost, Atom}
      iex> upper = Atom.char_class("Upper", ?A..?Z |> Enum.to_list(), 8.2)
      iex> lower = Atom.char_class("Lower", ?a..?z |> Enum.to_list(), 9.1)
      iex> pattern = [upper, lower]
      iex> strings = ["Male", "Female"]
      iex> cost = Cost.calculate(pattern, strings)
      iex> is_float(cost) and cost > 0
      true

      iex> alias FlashProfile.{Cost, Atom}
      iex> Cost.calculate([], [])
      0.0

      iex> alias FlashProfile.{Cost, Atom}
      iex> digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      iex> Cost.calculate([digit], ["abc"])
      :infinity
  """
  @spec calculate(pattern(), [String.t()]) :: cost()
  def calculate([], []), do: 0.0
  def calculate([], _strings), do: :infinity
  def calculate(_pattern, []), do: 0.0

  def calculate(pattern, strings) do
    case get_all_match_lengths(pattern, strings) do
      {:error, _} ->
        :infinity

      {:ok, all_lengths} ->
        # all_lengths is list of lists: [[len1, len2, ...], [len1, len2, ...], ...]
        # Each inner list is the lengths for one string

        # Calculate cost for each atom position
        pattern
        |> Enum.with_index()
        |> Enum.map(fn {atom, idx} ->
          static_cost = Atom.static_cost(atom)
          dynamic_weight = calculate_dynamic_weight(all_lengths, strings, idx)
          static_cost * dynamic_weight
        end)
        |> Enum.sum()
    end
  end

  @doc """
  Calculate cost with detailed breakdown per atom.

  Returns {:ok, {total_cost, breakdown}} or {:error, reason} where breakdown
  is a list of tuples containing {atom, static_cost, dynamic_weight} for each
  atom in the pattern.

  ## Parameters

  - `pattern` - List of atoms forming the pattern
  - `strings` - List of strings to evaluate the pattern against

  ## Returns

  - `{:ok, {total_cost, breakdown}}` - Success with detailed breakdown
  - `{:error, reason}` - Pattern doesn't match all strings

  ## Examples

      iex> alias FlashProfile.{Cost, Atom}
      iex> digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      iex> {:ok, {cost, breakdown}} = Cost.calculate_detailed([digit], ["123"])
      iex> is_float(cost) and length(breakdown) == 1
      true
  """
  @spec calculate_detailed(pattern(), [String.t()]) ::
          {:ok, {float(), [{Atom.t(), float(), float()}]}} | {:error, term()}
  def calculate_detailed([], []), do: {:ok, {0.0, []}}
  def calculate_detailed([], _strings), do: {:error, :empty_pattern_non_empty_strings}
  def calculate_detailed(_pattern, []), do: {:ok, {0.0, []}}

  def calculate_detailed(pattern, strings) do
    case get_all_match_lengths(pattern, strings) do
      {:error, reason} ->
        {:error, reason}

      {:ok, all_lengths} ->
        breakdown =
          pattern
          |> Enum.with_index()
          |> Enum.map(fn {atom, idx} ->
            static_cost = Atom.static_cost(atom)
            dynamic_weight = calculate_dynamic_weight(all_lengths, strings, idx)
            {atom, static_cost, dynamic_weight}
          end)

        total_cost =
          breakdown
          |> Enum.map(fn {_atom, static_cost, dynamic_weight} ->
            static_cost * dynamic_weight
          end)
          |> Enum.sum()

        {:ok, {total_cost, breakdown}}
    end
  end

  @doc """
  Compare two patterns by cost over the same dataset.

  Returns :lt if pattern1 has lower cost (is better), :eq if equal,
  or :gt if pattern2 has lower cost.

  ## Parameters

  - `pattern1` - First pattern to compare
  - `pattern2` - Second pattern to compare
  - `strings` - Dataset to evaluate both patterns against

  ## Returns

  - `:lt` - pattern1 is better (lower cost)
  - `:eq` - patterns have equal cost
  - `:gt` - pattern2 is better (lower cost)

  ## Examples

      iex> alias FlashProfile.{Cost, Atom}
      iex> digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      iex> alpha = Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)
      iex> Cost.compare([digit], [alpha], ["123"])
      :lt
  """
  @spec compare(pattern(), pattern(), [String.t()]) :: :lt | :eq | :gt
  def compare(pattern1, pattern2, strings) do
    cost1 = calculate(pattern1, strings)
    cost2 = calculate(pattern2, strings)

    cond do
      cost1 == :infinity and cost2 == :infinity -> :eq
      cost1 == :infinity -> :gt
      cost2 == :infinity -> :lt
      cost1 < cost2 -> :lt
      cost1 > cost2 -> :gt
      true -> :eq
    end
  end

  @doc """
  Find the minimum cost pattern from a list.

  Returns {pattern, cost} or nil if list is empty.

  ## Parameters

  - `patterns` - List of patterns to evaluate
  - `strings` - Dataset to evaluate patterns against

  ## Returns

  - `{pattern, cost}` - Best pattern and its cost
  - `nil` - If patterns list is empty

  ## Examples

      iex> alias FlashProfile.{Cost, Atom}
      iex> digit = Atom.char_class("Digit", ?0..?9 |> Enum.to_list(), 8.2)
      iex> alpha = Atom.char_class("Alpha", (?a..?z |> Enum.to_list()) ++ (?A..?Z |> Enum.to_list()), 15.0)
      iex> {best, _cost} = Cost.min_cost([[digit], [alpha]], ["123"])
      iex> best == [digit]
      true
  """
  @spec min_cost([pattern()], [String.t()]) :: {pattern(), cost()} | nil
  def min_cost([], _strings), do: nil

  def min_cost(patterns, strings) do
    patterns
    |> Enum.map(fn pattern ->
      {pattern, calculate(pattern, strings)}
    end)
    |> Enum.min_by(
      fn {_pattern, cost} ->
        case cost do
          :infinity -> :infinity
          c when is_float(c) -> c
        end
      end,
      fn
        :infinity, :infinity -> true
        :infinity, _ -> false
        _, :infinity -> true
        c1, c2 -> c1 <= c2
      end
    )
  end

  ## Private Helper Functions

  # Get match lengths for a pattern across all strings.
  # Returns {:ok, list of length lists} or {:error, :no_match}
  #
  # For each string, returns a list of lengths matched by each atom.
  # Example: pattern [Upper, Lower] on "Male" returns [1, 3]
  # (Upper matches "M" = 1 char, Lower matches "ale" = 3 chars)
  @spec get_all_match_lengths(pattern(), [String.t()]) ::
          {:ok, [[non_neg_integer()]]} | {:error, :no_match}
  defp get_all_match_lengths(pattern, strings) do
    results =
      Enum.map(strings, fn string ->
        match_pattern_lengths(pattern, string)
      end)

    if Enum.any?(results, &is_nil/1) do
      {:error, :no_match}
    else
      {:ok, results}
    end
  end

  # Match a pattern against a string and return the list of lengths
  # matched by each atom, or nil if the pattern doesn't fully match.
  #
  # The pattern must consume the entire string for a successful match.
  @spec match_pattern_lengths(pattern(), String.t()) :: [non_neg_integer()] | nil
  defp match_pattern_lengths(pattern, string) do
    {lengths, remaining} =
      Enum.reduce(pattern, {[], string}, fn atom, {lengths_acc, str} ->
        length = Atom.match(atom, str)

        if length > 0 do
          # Atom matched, consume that portion of the string
          new_remaining = String.slice(str, length..-1//1)
          {lengths_acc ++ [length], new_remaining}
        else
          # Atom didn't match, stop processing
          {lengths_acc ++ [0], str}
        end
      end)

    # Pattern must match entire string (no remainder)
    # and all atoms must have matched (no zeros in lengths)
    if remaining == "" and Enum.all?(lengths, &(&1 > 0)) do
      lengths
    else
      nil
    end
  end

  # Calculate the dynamic weight for a specific atom position.
  #
  # W(i, S | P) = (1/|S|) · Σ_{s∈S} (αi(si) / |s|)
  #
  # This is the average fraction of the original string length that
  # this atom matches across all strings.
  @spec calculate_dynamic_weight([[non_neg_integer()]], [String.t()], non_neg_integer()) ::
          float()
  defp calculate_dynamic_weight(all_lengths, strings, atom_index) do
    num_strings = length(strings)

    if num_strings == 0 do
      0.0
    else
      total =
        Enum.zip(all_lengths, strings)
        |> Enum.map(fn {lengths, string} ->
          atom_length = Enum.at(lengths, atom_index, 0)
          string_length = String.length(string)

          if string_length > 0 do
            atom_length / string_length
          else
            0.0
          end
        end)
        |> Enum.sum()

      total / num_strings
    end
  end
end
