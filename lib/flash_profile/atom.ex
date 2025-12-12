defmodule FlashProfile.Atom do
  @moduledoc """
  Implementation of atomic patterns (atoms) for FlashProfile.

  An atom α: String → Int is a function that matches a prefix of a string
  and returns the length matched (0 = no match). Atoms only match non-empty
  prefixes.

  From the paper (Definition 4.1):
  "An atom α: String → Int is a function, which given a string s, returns
  the length of the longest prefix of s that satisfies its constraints.
  Atoms only match non-empty prefixes. α(s) = 0 indicates match failure."

  ## Four Types of Atoms

  1. **Constant Strings (Const_s)**: Matches only the string s as prefix
  2. **Regular Expressions (RegEx_r)**: Returns length of longest prefix matched by regex r
  3. **Character Classes (Class^z_c)**:
     - Class^0_c: Returns length of longest prefix containing only chars from set c
     - Class^z_c (z > 0): Fixed-width variant - matches exactly z characters from set c
  4. **Arbitrary Functions (Funct_f)**: Custom matching function f
  """

  @type atom_type :: :constant | :char_class | :regex | :function

  @type t :: %__MODULE__{
          name: String.t(),
          type: atom_type(),
          matcher: (String.t() -> non_neg_integer()),
          static_cost: float(),
          params: map()
        }

  defstruct [
    :name,
    :type,
    :matcher,
    :static_cost,
    :params
  ]

  ## Constructor Functions

  @doc """
  Create a constant string atom.

  Matches exactly `string` as a prefix and returns the length of the string
  if matched, 0 otherwise.

  Cost is proportional to 1/length(string) to prefer longer matches.

  ## Examples

      iex> atom = FlashProfile.Atom.constant("PMC")
      iex> FlashProfile.Atom.match(atom, "PMC12345")
      3
      iex> FlashProfile.Atom.match(atom, "XYZ")
      0
  """
  @spec constant(String.t()) :: t()
  def constant(string) when is_binary(string) and byte_size(string) > 0 do
    len = String.length(string)
    # Cost proportional to 1/length - shorter strings have higher cost
    cost = 100.0 / len

    matcher = fn s ->
      if String.starts_with?(s, string) do
        len
      else
        0
      end
    end

    %__MODULE__{
      name: inspect(string),
      type: :constant,
      matcher: matcher,
      static_cost: cost,
      params: %{string: string, length: len}
    }
  end

  @doc """
  Create a variable-width character class atom.

  Matches the longest prefix where all characters are in the allowed set.
  Returns 0 if the first character doesn't match.

  ## Parameters

  - `name`: Display name for the atom (e.g., "Digit", "Upper")
  - `chars`: Charlist of allowed characters (e.g., ~c"0123456789")
  - `static_cost`: Base cost for this atom

  ## Examples

      iex> digit = FlashProfile.Atom.char_class("Digit", ~c"0123456789", 8.2)
      iex> FlashProfile.Atom.match(digit, "123abc")
      3
      iex> FlashProfile.Atom.match(digit, "abc123")
      0
  """
  @spec char_class(String.t(), charlist(), float()) :: t()
  def char_class(name, chars, static_cost) when is_list(chars) and is_float(static_cost) do
    # Convert charlist to MapSet for O(1) lookup
    char_set = MapSet.new(chars)

    matcher = fn s ->
      match_char_class_variable(s, char_set)
    end

    %__MODULE__{
      name: name,
      type: :char_class,
      matcher: matcher,
      static_cost: static_cost,
      params: %{chars: chars, width: 0, char_set: char_set}
    }
  end

  @doc """
  Create a fixed-width character class atom.

  Matches exactly `width` characters from the character set.
  Returns `width` if exactly `width` characters match, 0 otherwise.

  Cost is base_cost / width (fixed-width costs less than variable).

  ## Parameters

  - `name`: Display name for the atom
  - `chars`: Charlist of allowed characters
  - `width`: Exact number of characters to match (must be > 0)
  - `static_cost`: Base cost for this atom (will be divided by width)

  ## Examples

      iex> digit2 = FlashProfile.Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
      iex> FlashProfile.Atom.match(digit2, "12345")
      2
      iex> FlashProfile.Atom.match(digit2, "1abc")
      0
  """
  @spec char_class(String.t(), charlist(), pos_integer(), float()) :: t()
  def char_class(name, chars, width, static_cost)
      when is_list(chars) and is_integer(width) and width > 0 and is_float(static_cost) do
    char_set = MapSet.new(chars)
    # Fixed-width cost is base_cost / width
    adjusted_cost = static_cost / width

    matcher = fn s ->
      match_char_class_fixed(s, char_set, width)
    end

    %__MODULE__{
      name: name,
      type: :char_class,
      matcher: matcher,
      static_cost: adjusted_cost,
      params: %{chars: chars, width: width, char_set: char_set}
    }
  end

  @doc """
  Create a regex atom.

  The pattern must match from the start of the string (should be anchored with ^).
  Returns the length of the matched prefix.

  ## Parameters

  - `name`: Display name for the atom
  - `pattern`: Regex pattern (string or compiled regex)
  - `static_cost`: Base cost for this atom

  ## Examples

      iex> atom = FlashProfile.Atom.regex("Email", ~r/^[a-z]+@/, 15.0)
      iex> FlashProfile.Atom.match(atom, "user@example.com")
      5
  """
  @spec regex(String.t(), String.t() | Regex.t(), float()) :: t()
  def regex(name, pattern, static_cost) when is_float(static_cost) do
    compiled_regex =
      case pattern do
        %Regex{} = r -> r
        string when is_binary(string) -> Regex.compile!(string)
      end

    matcher = fn s ->
      case Regex.run(compiled_regex, s, return: :index) do
        [{0, length}] -> length
        _ -> 0
      end
    end

    %__MODULE__{
      name: name,
      type: :regex,
      matcher: matcher,
      static_cost: static_cost,
      params: %{pattern: compiled_regex}
    }
  end

  @doc """
  Create a function atom with custom matching logic.

  The matcher function should take a string and return the length of the
  matched prefix (0 for no match).

  ## Parameters

  - `name`: Display name for the atom
  - `matcher_fn`: Function (String.t() -> non_neg_integer())
  - `static_cost`: Base cost for this atom

  ## Examples

      iex> matcher = fn s ->
      ...>   cond do
      ...>     String.starts_with?(s, "http://") -> 7
      ...>     String.starts_with?(s, "https://") -> 8
      ...>     true -> 0
      ...>   end
      ...> end
      iex> atom = FlashProfile.Atom.function("Protocol", matcher, 10.0)
      iex> FlashProfile.Atom.match(atom, "https://example.com")
      8
  """
  @spec function(String.t(), (String.t() -> non_neg_integer()), float()) :: t()
  def function(name, matcher_fn, static_cost)
      when is_function(matcher_fn, 1) and is_float(static_cost) do
    %__MODULE__{
      name: name,
      type: :function,
      matcher: matcher_fn,
      static_cost: static_cost,
      params: %{}
    }
  end

  ## Core Functions

  @doc """
  Match atom against string, return length of matched prefix.

  Returns 0 if no match (atoms only match non-empty prefixes).

  ## Examples

      iex> digit = FlashProfile.Atom.char_class("Digit", ~c"0123456789", 8.2)
      iex> FlashProfile.Atom.match(digit, "123abc")
      3
  """
  @spec match(t(), String.t()) :: non_neg_integer()
  def match(%__MODULE__{matcher: matcher}, string) when is_binary(string) do
    matcher.(string)
  end

  @doc """
  Get the static cost of an atom.

  ## Examples

      iex> atom = FlashProfile.Atom.constant("PMC")
      iex> FlashProfile.Atom.static_cost(atom)
      33.333333333333336
  """
  @spec static_cost(t()) :: float()
  def static_cost(%__MODULE__{static_cost: cost}), do: cost

  @doc """
  Format atom for display.

  Returns a string representation suitable for pattern printing.

  ## Examples

      iex> digit = FlashProfile.Atom.char_class("Digit", ~c"0123456789", 8.2)
      iex> FlashProfile.Atom.to_string(digit)
      "Digit"

      iex> const = FlashProfile.Atom.constant("PMC")
      iex> FlashProfile.Atom.to_string(const)
      "\\"PMC\\""
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{name: name, type: type}) do
    case type do
      :constant -> name
      _ -> name
    end
  end

  @doc """
  Check if atom matches entire string.

  Returns true if the atom matches and consumes the entire string.

  ## Examples

      iex> digit = FlashProfile.Atom.char_class("Digit", ~c"0123456789", 8.2)
      iex> FlashProfile.Atom.matches_entirely?(digit, "123")
      true
      iex> FlashProfile.Atom.matches_entirely?(digit, "123abc")
      false
  """
  @spec matches_entirely?(t(), String.t()) :: boolean()
  def matches_entirely?(%__MODULE__{} = atom, string) when is_binary(string) do
    matched_length = match(atom, string)
    matched_length > 0 and matched_length == String.length(string)
  end

  @doc """
  Create a fixed-width variant of a character class atom.

  Given a variable-width char_class atom, creates a new atom that matches
  exactly `width` characters from the same character set.

  ## Examples

      iex> digit = FlashProfile.Atom.char_class("Digit", ~c"0123456789", 8.2)
      iex> digit2 = FlashProfile.Atom.with_fixed_width(digit, 2)
      iex> FlashProfile.Atom.match(digit2, "12345")
      2
      iex> FlashProfile.Atom.match(digit2, "1abc")
      0
  """
  @spec with_fixed_width(t(), pos_integer()) :: t()
  def with_fixed_width(
        %__MODULE__{type: :char_class, name: name, params: params, static_cost: base_cost},
        width
      )
      when is_integer(width) and width > 0 do
    chars = params.chars
    char_class(name, chars, width, base_cost)
  end

  ## Private Helper Functions

  # Match variable-width character class
  # Returns length of longest prefix where all characters are in char_set
  defp match_char_class_variable(string, char_set) do
    string
    |> String.graphemes()
    |> Enum.reduce_while(0, fn grapheme, count ->
      # Convert grapheme to codepoint for comparison
      codepoint = String.to_charlist(grapheme) |> List.first()

      if codepoint && MapSet.member?(char_set, codepoint) do
        {:cont, count + 1}
      else
        {:halt, count}
      end
    end)
  end

  # Match fixed-width character class
  # Returns width if exactly width characters match, 0 otherwise
  defp match_char_class_fixed(string, char_set, width) do
    graphemes = String.graphemes(string)

    if length(graphemes) < width do
      0
    else
      matched =
        graphemes
        |> Enum.take(width)
        |> Enum.all?(fn grapheme ->
          codepoint = String.to_charlist(grapheme) |> List.first()
          codepoint && MapSet.member?(char_set, codepoint)
        end)

      if matched, do: width, else: 0
    end
  end
end
