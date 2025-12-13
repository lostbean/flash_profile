defmodule FlashProfile.Pattern do
  @moduledoc """
  Implementation of patterns for FlashProfile.

  A **pattern** is simply a sequence of atoms. The pattern `Empty` denotes an empty
  sequence, which only matches the empty string `ε`. We use the concatenation
  operator `◇` for sequencing atoms.

  ## Pattern Matching Rules

  Pattern `P` describes string `s` iff:
  - `s ≠ ε` (non-empty) OR `s = ε` and `P` is empty
  - `∀i ∈ {1,...,k}: αi(si) > 0` (each atom matches a non-empty prefix)
  - `sk+1 = ε` (entire string consumed)

  Where `s1 = s` and `si+1 = si[αi(si):]` (remaining suffix after matching atom `αi`)

  ## Matching Algorithm

  Patterns match **greedily from left to right**:
  1. Start at position `0` of the string
  2. For each atom in order:
     - Call `atom.match(remaining_string)`
     - If result is `0`, pattern doesn't match
     - Otherwise, consume that many characters and continue
  3. After all atoms, check if entire string is consumed

  ## Examples

  ```elixir
  iex> alias FlashProfile.{Pattern, Atom}
  iex> alias FlashProfile.Atoms.CharClass
  iex> digit = CharClass.digit()
  iex> upper = CharClass.upper()
  iex> dash = Atom.constant("-")
  iex> pattern = [upper, dash, digit]
  iex> Pattern.matches?(pattern, "A-123")
  true
  iex> Pattern.matches?(pattern, "AB-123")
  true
  iex> Pattern.matches?(pattern, "A-")
  false
  ```
  """

  alias FlashProfile.Atom

  @type t :: [Atom.t()]

  @doc """
  Create an empty pattern (matches only empty string).

  ## Examples

      iex> FlashProfile.Pattern.empty()
      []
  """
  @spec empty() :: t()
  def empty(), do: []

  @doc """
  Check if a pattern matches a string entirely.

  Returns `true` if the pattern describes the string. An empty pattern `[]`
  only matches empty string `""`. Each atom must match a non-empty prefix,
  and together they must consume the entire string.

  ## Examples

  ```elixir
  iex> alias FlashProfile.{Pattern, Atom}
  iex> alias FlashProfile.Atoms.CharClass
  iex> digit = CharClass.digit()
  iex> pattern = [digit]
  iex> Pattern.matches?(pattern, "123")
  true
  iex> Pattern.matches?(pattern, "123abc")
  false
  iex> Pattern.matches?([], "")
  true
  iex> Pattern.matches?([], "abc")
  false
  ```
  """
  @spec matches?(t(), String.t()) :: boolean()
  def matches?(pattern, string) when is_list(pattern) and is_binary(string) do
    case do_match(pattern, string, 0, []) do
      {:ok, _matches} -> true
      {:error, :no_match} -> false
    end
  end

  @doc """
  Match a pattern against a string, returning match details.

  Returns `{:ok, matches}` with list of `{atom, matched_substring, start_pos, length}`
  or `{:error, :no_match}` if pattern doesn't match.

  ## Examples

  ```elixir
  iex> alias FlashProfile.{Pattern, Atom}
  iex> alias FlashProfile.Atoms.CharClass
  iex> digit = CharClass.digit()
  iex> upper = CharClass.upper()
  iex> dash = Atom.constant("-")
  iex> pattern = [upper, dash, digit]
  iex> {:ok, matches} = Pattern.match(pattern, "A-123")
  iex> length(matches)
  3
  iex> Pattern.match(pattern, "invalid")
  {:error, :no_match}
  ```
  """
  @spec match(t(), String.t()) ::
          {:ok, list({Atom.t(), String.t(), non_neg_integer(), non_neg_integer()})}
          | {:error, :no_match}
  def match(pattern, string) when is_list(pattern) and is_binary(string) do
    do_match(pattern, string, 0, [])
  end

  @doc """
  Get the lengths matched by each atom for a string.

  Returns list of lengths, or `nil` if pattern doesn't match.
  Used for cost calculation.

  ## Examples

  ```elixir
  iex> alias FlashProfile.{Pattern, Atom}
  iex> alias FlashProfile.Atoms.CharClass
  iex> digit = CharClass.digit()
  iex> upper = CharClass.upper()
  iex> pattern = [upper, digit]
  iex> Pattern.match_lengths(pattern, "A123")
  [1, 3]
  iex> Pattern.match_lengths(pattern, "invalid")
  nil
  ```
  """
  @spec match_lengths(t(), String.t()) :: [non_neg_integer()] | nil
  def match_lengths(pattern, string) when is_list(pattern) and is_binary(string) do
    case do_match(pattern, string, 0, []) do
      {:ok, matches} ->
        matches
        |> Enum.map(fn {_atom, _matched, _pos, length} -> length end)

      {:error, :no_match} ->
        nil
    end
  end

  @doc """
  Format a pattern as a human-readable string.

  ## Display Format

  - Constant strings: in quotes, e.g., `"PMC"`
  - Fixed-width char class: `Name×N`, e.g., `Digit×4`
  - Variable-width char class: `Name+`, e.g., `Lower+`
  - Atoms separated by `◇`

  ## Examples

  ```elixir
  iex> alias FlashProfile.{Pattern, Atom}
  iex> alias FlashProfile.Atoms.CharClass
  iex> digit = CharClass.digit()
  iex> upper = CharClass.upper()
  iex> dash = Atom.constant("-")
  iex> pattern = [upper, dash, digit]
  iex> Pattern.to_string(pattern)
  "Upper+ ◇ \\"-\\" ◇ Digit+"
  ```
  """
  @spec to_string(t()) :: String.t()
  def to_string(pattern) when is_list(pattern) do
    pattern
    |> Enum.map(&format_atom/1)
    |> Enum.join(" ◇ ")
  end

  @doc """
  Concatenate two patterns.

  ## Examples

      iex> alias FlashProfile.{Pattern, Atom}
      iex> alias FlashProfile.Atoms.CharClass
      iex> digit = CharClass.digit()
      iex> upper = CharClass.upper()
      iex> p1 = [upper]
      iex> p2 = [digit]
      iex> result = Pattern.concat(p1, p2)
      iex> length(result)
      2
  """
  @spec concat(t(), t()) :: t()
  def concat(pattern1, pattern2) when is_list(pattern1) and is_list(pattern2) do
    pattern1 ++ pattern2
  end

  @doc """
  Append an atom to a pattern.

  ## Examples

      iex> alias FlashProfile.{Pattern, Atom}
      iex> alias FlashProfile.Atoms.CharClass
      iex> digit = CharClass.digit()
      iex> upper = CharClass.upper()
      iex> pattern = [upper]
      iex> result = Pattern.append(pattern, digit)
      iex> length(result)
      2
  """
  @spec append(t(), Atom.t()) :: t()
  def append(pattern, atom) when is_list(pattern) do
    pattern ++ [atom]
  end

  @doc """
  Get the number of atoms in a pattern.

  ## Examples

      iex> alias FlashProfile.{Pattern, Atom}
      iex> alias FlashProfile.Atoms.CharClass
      iex> digit = CharClass.digit()
      iex> upper = CharClass.upper()
      iex> pattern = [upper, digit]
      iex> Pattern.length(pattern)
      2
      iex> Pattern.length([])
      0
  """
  @spec length(t()) :: non_neg_integer()
  def length(pattern) when is_list(pattern) do
    Kernel.length(pattern)
  end

  @doc """
  Check if pattern is empty.

  ## Examples

      iex> FlashProfile.Pattern.empty?([])
      true
      iex> alias FlashProfile.Atoms.CharClass
      iex> FlashProfile.Pattern.empty?([CharClass.digit()])
      false
  """
  @spec empty?(t()) :: boolean()
  def empty?(pattern) when is_list(pattern), do: pattern == []

  @doc """
  Get the first atom of a pattern.

  Returns nil if pattern is empty.

  ## Examples

      iex> alias FlashProfile.{Pattern, Atom}
      iex> alias FlashProfile.Atoms.CharClass
      iex> digit = CharClass.digit()
      iex> upper = CharClass.upper()
      iex> pattern = [upper, digit]
      iex> first = Pattern.first(pattern)
      iex> first.name
      "Upper"
      iex> Pattern.first([])
      nil
  """
  @spec first(t()) :: Atom.t() | nil
  def first([atom | _]), do: atom
  def first([]), do: nil

  @doc """
  Get the last atom of a pattern.

  Returns nil if pattern is empty.

  ## Examples

      iex> alias FlashProfile.{Pattern, Atom}
      iex> alias FlashProfile.Atoms.CharClass
      iex> digit = CharClass.digit()
      iex> upper = CharClass.upper()
      iex> pattern = [upper, digit]
      iex> last = Pattern.last(pattern)
      iex> last.name
      "Digit"
      iex> Pattern.last([])
      nil
  """
  @spec last(t()) :: Atom.t() | nil
  def last(pattern) when is_list(pattern) do
    List.last(pattern)
  end

  ## Private Functions

  # Match pattern against string, accumulating match details
  # Returns {:ok, matches} or {:error, :no_match}
  defp do_match([], "", _pos, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp do_match([], _remaining, _pos, _acc) do
    {:error, :no_match}
  end

  defp do_match([atom | rest], string, pos, acc) do
    case Atom.match(atom, string) do
      0 ->
        {:error, :no_match}

      len ->
        matched = String.slice(string, 0, len)
        remaining = String.slice(string, len..-1//1)
        do_match(rest, remaining, pos + len, [{atom, matched, pos, len} | acc])
    end
  end

  # Format an atom for display in a pattern string
  defp format_atom(%Atom{type: :constant, params: %{string: str}}) do
    # Constant strings shown in quotes
    inspect(str)
  end

  defp format_atom(%Atom{type: :char_class, name: name, params: %{width: width}})
       when width > 0 do
    # Fixed-width: Name×N
    "#{name}×#{width}"
  end

  defp format_atom(%Atom{type: :char_class, name: name, params: %{width: 0}}) do
    # Variable-width: Name+
    "#{name}+"
  end

  defp format_atom(%Atom{name: name}) do
    # Fallback: just use the name
    name
  end
end
