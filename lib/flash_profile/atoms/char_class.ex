defmodule FlashProfile.Atoms.CharClass do
  @moduledoc """
  Factory functions for character class atoms.

  Provides predefined character class atoms based on the FlashProfile paper (Figure 6).
  Each function creates an atom representing a specific character class with an
  associated static cost that influences pattern selection.

  ## Static Costs

  Lower costs indicate more preferred/specific patterns:
  - Very specific (Bin, DotDash): 3.0-5.0
  - Single char classes (Lower, Upper, Digit): 8.2-9.1
  - Medium specificity (Alpha, AlphaDash): 15.0-18.0
  - Broad classes (AlphaDigit, Base64): 20.0-25.0
  - Hex: 26.3 (penalized to prefer "Lower" for words like "face")
  - High generality (Symb): 30.0
  - Catch-all (Any): 100.0

  ## Examples

      iex> lower = FlashProfile.Atoms.CharClass.lower()
      iex> upper = FlashProfile.Atoms.CharClass.upper()
      iex> digit_fixed = FlashProfile.Atoms.CharClass.with_width(&FlashProfile.Atoms.CharClass.digit/0, 3)
  """

  alias FlashProfile.Atom

  @doc """
  Lowercase letters: [a-z]

  Static cost: 9.1
  """
  def lower(), do: Atom.char_class("Lower", ~c"abcdefghijklmnopqrstuvwxyz", 9.1)

  @doc """
  Uppercase letters: [A-Z]

  Static cost: 8.2
  """
  def upper(), do: Atom.char_class("Upper", ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ", 8.2)

  @doc """
  Decimal digits: [0-9]

  Static cost: 8.2
  """
  def digit(), do: Atom.char_class("Digit", ~c"0123456789", 8.2)

  @doc """
  Binary digits: [01]

  Static cost: 5.0
  """
  def bin(), do: Atom.char_class("Bin", ~c"01", 5.0)

  @doc """
  Hexadecimal digits: [0-9a-fA-F]

  Static cost: 26.3 (higher to avoid matching words like "face" as hex)
  """
  def hex(), do: Atom.char_class("Hex", ~c"0123456789abcdefABCDEF", 26.3)

  @doc """
  Alphabetic characters: [a-zA-Z]

  Static cost: 15.0
  """
  def alpha(), do: Atom.char_class("Alpha", all_alpha_chars(), 15.0)

  @doc """
  Alphanumeric characters: [a-zA-Z0-9]

  Static cost: 20.0
  """
  def alpha_digit(), do: Atom.char_class("AlphaDigit", all_alpha_digit_chars(), 20.0)

  @doc """
  Whitespace characters: space, tab, newline, carriage return, form feed

  Static cost: 5.0
  """
  def space(), do: Atom.char_class("Space", ~c" \t\n\r\f", 5.0)

  @doc """
  Alphanumeric and whitespace: [a-zA-Z0-9\\s]

  Static cost: 25.0
  """
  def alpha_digit_space() do
    Atom.char_class("AlphaDigitSpace", all_alpha_digit_space_chars(), 25.0)
  end

  @doc """
  Dot and dash: [.-]

  Static cost: 3.0
  """
  def dot_dash(), do: Atom.char_class("DotDash", ~c".-", 3.0)

  @doc """
  Common punctuation: [.,:?/-]

  Static cost: 10.0
  """
  def punct(), do: Atom.char_class("Punct", ~c".,:?/-", 10.0)

  @doc """
  Alphabetic and dash: [a-zA-Z-]

  Static cost: 18.0
  """
  def alpha_dash(), do: Atom.char_class("AlphaDash", all_alpha_dash_chars(), 18.0)

  @doc """
  Symbol characters: [-.,://@#$%&*()!~`+=<>?]

  Static cost: 30.0
  """
  def symb(), do: Atom.char_class("Symb", symbol_chars(), 30.0)

  @doc """
  Alphabetic and whitespace: [a-zA-Z\\s]

  Static cost: 18.0
  """
  def alpha_space(), do: Atom.char_class("AlphaSpace", all_alpha_space_chars(), 18.0)

  @doc """
  Base64 characters: [a-zA-Z0-9+=]

  Static cost: 25.0
  """
  def base64(), do: Atom.char_class("Base64", base64_chars(), 25.0)

  @doc """
  Any printable character (ASCII 32-126)

  Static cost: 100.0 (high cost as catch-all)
  """
  def any(), do: Atom.char_class("Any", all_printable_chars(), 100.0)

  @doc """
  Create a fixed-width variant of a character class atom.

  Takes a zero-arity function that returns an atom and a positive integer width,
  and returns a new atom with the specified fixed width.

  ## Parameters

    - `atom_fn` - A zero-arity function that returns an atom
    - `width` - The fixed width (positive integer)

  ## Examples

      iex> digit_3 = FlashProfile.Atoms.CharClass.with_width(&FlashProfile.Atoms.CharClass.digit/0, 3)
      # Creates a Digit atom that matches exactly 3 digits
  """
  def with_width(atom_fn, width)
      when is_function(atom_fn, 0) and is_integer(width) and width > 0 do
    base_atom = atom_fn.()
    # Extract the name, chars, and static_cost from the base atom
    # and create a fixed-width variant
    %{name: name, chars: chars, static_cost: cost} = base_atom
    Atom.char_class(name <> "#{width}", chars, width, cost)
  end

  # Private helper functions

  defp all_alpha_chars() do
    ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  end

  defp all_alpha_digit_chars() do
    ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  end

  defp all_alpha_digit_space_chars() do
    ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \t\n\r\f"
  end

  defp all_alpha_dash_chars() do
    ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-"
  end

  defp all_alpha_space_chars() do
    ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ \t\n\r\f"
  end

  defp base64_chars() do
    ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+="
  end

  defp symbol_chars() do
    ~c"-.,://@#$%&*()!~`+=<>?"
  end

  defp all_printable_chars() do
    # ASCII printable characters (32-126)
    Enum.to_list(32..126)
  end
end
