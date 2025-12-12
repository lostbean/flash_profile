defmodule FlashProfile.Atoms.Constant do
  @moduledoc """
  Factory for constant string atoms.

  Constant atoms represent literal string patterns that match exactly the
  specified string with no variation. They are useful for common separators,
  delimiters, and fixed prefixes/suffixes in data.

  ## Examples

      iex> comma = FlashProfile.Atoms.Constant.new(",")
      iex> prefixes = FlashProfile.Atoms.Constant.all_prefixes("Hello")
      # Returns [const("H"), const("He"), const("Hel"), const("Hell"), const("Hello")]

      iex> strings = ["test123", "test456", "test789"]
      iex> lcp_atom = FlashProfile.Atoms.Constant.from_common_prefix(strings)
      # Returns constant atoms for all prefixes of "test"
  """

  alias FlashProfile.Atom

  @doc """
  Create a constant atom from a string.

  ## Parameters

    - `string` - A non-empty binary string

  ## Returns

  An atom that matches exactly the provided string.

  ## Examples

      iex> FlashProfile.Atoms.Constant.new(":")
      %FlashProfile.Atom{type: :constant, value: ":", ...}

      iex> FlashProfile.Atoms.Constant.new("/")
      %FlashProfile.Atom{type: :constant, value: "/", ...}
  """
  def new(string) when is_binary(string) and byte_size(string) > 0 do
    Atom.constant(string)
  end

  @doc """
  Create constant atoms for all prefixes of a string.

  Given a string, creates a list of constant atoms for each prefix of the string,
  from length 1 to the full string length. This is useful for pattern learning
  where we want to explore different levels of specificity.

  ## Parameters

    - `string` - A non-empty binary string

  ## Returns

  A list of constant atoms, one for each prefix of the string, ordered from
  shortest to longest.

  ## Examples

      iex> FlashProfile.Atoms.Constant.all_prefixes("ABC")
      [
        %FlashProfile.Atom{value: "A", ...},
        %FlashProfile.Atom{value: "AB", ...},
        %FlashProfile.Atom{value: "ABC", ...}
      ]

      iex> FlashProfile.Atoms.Constant.all_prefixes(":")
      [%FlashProfile.Atom{value: ":", ...}]
  """
  def all_prefixes(string) when is_binary(string) and byte_size(string) > 0 do
    string
    |> String.graphemes()
    |> Enum.scan(&(&2 <> &1))
    |> Enum.map(&new/1)
  end

  @doc """
  Create constant atoms for all prefixes of the longest common prefix (LCP) of strings.

  Finds the longest common prefix shared by all input strings, then creates
  constant atoms for all prefixes of that LCP. This is useful for identifying
  common patterns across a set of examples.

  ## Parameters

    - `strings` - A non-empty list of binary strings

  ## Returns

  A list of constant atoms for all prefixes of the longest common prefix.
  Returns an empty list if there is no common prefix or if the input is empty.

  ## Examples

      iex> FlashProfile.Atoms.Constant.from_common_prefix(["test123", "test456", "test789"])
      [
        %FlashProfile.Atom{value: "t", ...},
        %FlashProfile.Atom{value: "te", ...},
        %FlashProfile.Atom{value: "tes", ...},
        %FlashProfile.Atom{value: "test", ...}
      ]

      iex> FlashProfile.Atoms.Constant.from_common_prefix(["abc", "def"])
      []

      iex> FlashProfile.Atoms.Constant.from_common_prefix(["same", "same", "same"])
      [
        %FlashProfile.Atom{value: "s", ...},
        %FlashProfile.Atom{value: "sa", ...},
        %FlashProfile.Atom{value: "sam", ...},
        %FlashProfile.Atom{value: "same", ...}
      ]
  """
  def from_common_prefix([]), do: []
  def from_common_prefix([string]), do: all_prefixes(string)

  def from_common_prefix(strings) when is_list(strings) do
    case find_longest_common_prefix(strings) do
      "" -> []
      lcp -> all_prefixes(lcp)
    end
  end

  # Private helper functions

  defp find_longest_common_prefix([first | rest]) do
    first
    |> String.graphemes()
    |> Enum.reduce_while("", fn char, acc ->
      candidate = acc <> char

      if Enum.all?(rest, &String.starts_with?(&1, candidate)) do
        {:cont, candidate}
      else
        {:halt, acc}
      end
    end)
  end

  defp find_longest_common_prefix([]), do: ""
end
