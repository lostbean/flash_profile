defmodule FlashProfile.Atoms.Regex do
  @moduledoc """
  Factory for regex-based atoms.

  **Regex atoms** represent patterns that are more complex than simple character
  classes or constants. They are used when the pattern requires more sophisticated
  matching logic, such as specific sequences or structural constraints.

  ## Examples

  ```elixir
  iex> title = FlashProfile.Atoms.Regex.title_case_word()
  # Matches words like "Hello", "World", "Title"

  iex> custom = FlashProfile.Atoms.Regex.new("IPv4Octet", "([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])", 15.0)
  # Matches valid IPv4 octets (0-255)
  ```
  """

  alias FlashProfile.Atom

  @doc """
  Create a regex atom.

  Creates an atom that matches strings according to the provided regex pattern.
  The pattern is automatically anchored at the start (`^`) to ensure it matches
  from the beginning of the string.

  ## Parameters

  - `name` - A descriptive name for the atom (e.g., `"TitleCaseWord"`)
  - `pattern` - A regex pattern string (without the leading `^`)
  - `static_cost` - The static cost for this atom (influences pattern selection)

  ## Returns

  An atom that matches strings according to the regex pattern.

  ## Examples

  ```elixir
  iex> FlashProfile.Atoms.Regex.new("Digit3", "[0-9]{3}", 8.0)
  %FlashProfile.Atom{type: :regex, name: "Digit3", ...}

  iex> FlashProfile.Atoms.Regex.new("Word", "\\w+", 10.0)
  %FlashProfile.Atom{type: :regex, name: "Word", ...}
  ```

  ## Errors

  Raises a `Regex.CompileError` if the pattern is invalid.
  """
  def new(name, pattern, static_cost)
      when is_binary(name) and is_binary(pattern) and is_number(static_cost) do
    # Compile regex with ^ anchor to match from start
    compiled_regex = Regex.compile!("^" <> pattern)
    Atom.regex(name, compiled_regex, static_cost)
  end

  @doc """
  Title case word: starts with uppercase letter followed by one or more lowercase letters.

  Matches words in title case format, such as `"Hello"`, `"World"`, `"Title"`, `"Example"`.
  Does not match all-uppercase words (e.g., `"HELLO"`) or all-lowercase words (e.g., `"hello"`).

  Pattern: `[A-Z][a-z]+`

  Static cost: `12.0`

  ## Examples

  ```elixir
  iex> atom = FlashProfile.Atoms.Regex.title_case_word()
  # Matches: "Hello", "World", "Title"
  # Does not match: "HELLO", "hello", "HeLLo"
  ```
  """
  def title_case_word() do
    new("TitleCaseWord", "[A-Z][a-z]+", 12.0)
  end
end
