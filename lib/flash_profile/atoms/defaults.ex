defmodule FlashProfile.Atoms.Defaults do
  @moduledoc """
  Default set of atoms for FlashProfile.

  Based on Figure 6 from the FlashProfile paper, this module provides the
  standard collection of atoms used in pattern learning. The atoms are organized
  by type and can be accessed individually or as categorized groups.

  ## Paper Atoms (Figure 6)

  The following atoms are defined in the paper:
  - Lower, Upper, Digit, Bin, Hex, Alpha, AlphaDigit, Space, DotDash,
  - Punct, AlphaDash, Symb, Base64, Any

  ## Extensions (not in paper)

  This implementation includes additional atoms beyond Figure 6:
  - **AlphaDigitSpace**: [a-zA-Z0-9\\s] - alphanumeric with whitespace
  - **AlphaSpace**: [a-zA-Z\\s] - alphabetic with whitespace
  - **TitleCaseWord**: [A-Z][a-z]+ - title case words (regex-based)

  ## Default Atoms

  The following atoms are included:

  ### Character Classes
  - Lower: lowercase letters [a-z]
  - Upper: uppercase letters [A-Z]
  - Digit: decimal digits [0-9]
  - Bin: binary digits [01]
  - Hex: hexadecimal digits [0-9a-fA-F]
  - Alpha: alphabetic characters [a-zA-Z]
  - AlphaDigit: alphanumeric [a-zA-Z0-9]
  - Space: whitespace characters
  - AlphaDigitSpace: alphanumeric and whitespace (extension)
  - DotDash: dot and dash [.-]
  - Punct: common punctuation [.,:?/-]
  - AlphaDash: alphabetic and dash [a-zA-Z-]
  - Symb: symbol characters
  - AlphaSpace: alphabetic and whitespace (extension)
  - Base64: Base64 characters [a-zA-Z0-9+=]
  - Any: any printable character

  ### Regex Patterns
  - TitleCaseWord: uppercase letter followed by lowercase letters (extension)

  ## Examples

      iex> all_atoms = FlashProfile.Atoms.Defaults.all()
      iex> length(all_atoms)
      17

      iex> letters = FlashProfile.Atoms.Defaults.letters()
      iex> digits = FlashProfile.Atoms.Defaults.digits()

      iex> lower = FlashProfile.Atoms.Defaults.get("Lower")
  """

  alias FlashProfile.Atoms.{CharClass, Regex}

  @doc """
  Get all default atoms as a list.

  Returns the complete set of 17 default atoms defined in the FlashProfile paper.

  ## Returns

  A list containing all default atoms.

  ## Examples

      iex> atoms = FlashProfile.Atoms.Defaults.all()
      iex> Enum.map(atoms, & &1.name)
      ["Lower", "Upper", "Digit", "Bin", "Hex", "Alpha", "AlphaDigit",
       "Space", "AlphaDigitSpace", "DotDash", "Punct", "AlphaDash",
       "Symb", "AlphaSpace", "Base64", "Any", "TitleCaseWord"]
  """
  def all() do
    [
      CharClass.lower(),
      CharClass.upper(),
      CharClass.digit(),
      CharClass.bin(),
      CharClass.hex(),
      CharClass.alpha(),
      CharClass.alpha_digit(),
      CharClass.space(),
      CharClass.alpha_digit_space(),
      CharClass.dot_dash(),
      CharClass.punct(),
      CharClass.alpha_dash(),
      CharClass.symb(),
      CharClass.alpha_space(),
      CharClass.base64(),
      CharClass.any(),
      Regex.title_case_word()
    ]
  end

  @doc """
  Get letter-related atoms.

  Returns atoms that match letters: Lower, Upper, and Alpha.

  ## Returns

  A list of letter-matching atoms.

  ## Examples

      iex> letters = FlashProfile.Atoms.Defaults.letters()
      iex> Enum.map(letters, & &1.name)
      ["Lower", "Upper", "Alpha"]
  """
  def letters() do
    [
      CharClass.lower(),
      CharClass.upper(),
      CharClass.alpha()
    ]
  end

  @doc """
  Get digit-related atoms.

  Returns atoms that match numeric digits: Digit, Bin, and Hex.

  ## Returns

  A list of digit-matching atoms.

  ## Examples

      iex> digits = FlashProfile.Atoms.Defaults.digits()
      iex> Enum.map(digits, & &1.name)
      ["Digit", "Bin", "Hex"]
  """
  def digits() do
    [
      CharClass.digit(),
      CharClass.bin(),
      CharClass.hex()
    ]
  end

  @doc """
  Get whitespace-related atoms.

  Returns atoms that match whitespace characters.

  ## Returns

  A list containing the Space atom.

  ## Examples

      iex> ws = FlashProfile.Atoms.Defaults.whitespace()
      iex> Enum.map(ws, & &1.name)
      ["Space"]
  """
  def whitespace() do
    [CharClass.space()]
  end

  @doc """
  Get punctuation-related atoms.

  Returns atoms that match punctuation and symbols: DotDash, Punct, and Symb.

  ## Returns

  A list of punctuation-matching atoms.

  ## Examples

      iex> punct = FlashProfile.Atoms.Defaults.punctuation()
      iex> Enum.map(punct, & &1.name)
      ["DotDash", "Punct", "Symb"]
  """
  def punctuation() do
    [
      CharClass.dot_dash(),
      CharClass.punct(),
      CharClass.symb()
    ]
  end

  @doc """
  Get mixed character class atoms.

  Returns atoms that match combinations of character types:
  AlphaDigit, AlphaDigitSpace, and Base64.

  ## Returns

  A list of mixed character class atoms.

  ## Examples

      iex> mixed = FlashProfile.Atoms.Defaults.mixed()
      iex> Enum.map(mixed, & &1.name)
      ["AlphaDigit", "AlphaDigitSpace", "Base64"]
  """
  def mixed() do
    [
      CharClass.alpha_digit(),
      CharClass.alpha_digit_space(),
      CharClass.base64()
    ]
  end

  @doc """
  Get an atom by name.

  Looks up an atom from the default set by its name (case-sensitive).

  ## Parameters

    - `name` - The name of the atom to retrieve (e.g., "Lower", "Digit")

  ## Returns

  The matching atom, or `nil` if no atom with that name exists.

  ## Examples

      iex> FlashProfile.Atoms.Defaults.get("Lower")
      %FlashProfile.Atom{name: "Lower", ...}

      iex> FlashProfile.Atoms.Defaults.get("Digit")
      %FlashProfile.Atom{name: "Digit", ...}

      iex> FlashProfile.Atoms.Defaults.get("NonExistent")
      nil
  """
  def get(name) when is_binary(name) do
    Enum.find(all(), fn atom -> atom.name == name end)
  end

  @doc """
  Get all atom names.

  Returns a list of all default atom names for reference.

  ## Returns

  A list of atom names as strings.

  ## Examples

      iex> FlashProfile.Atoms.Defaults.atom_names()
      ["Lower", "Upper", "Digit", "Bin", "Hex", "Alpha", "AlphaDigit",
       "Space", "AlphaDigitSpace", "DotDash", "Punct", "AlphaDash",
       "Symb", "AlphaSpace", "Base64", "Any", "TitleCaseWord"]
  """
  def atom_names() do
    [
      "Lower",
      "Upper",
      "Digit",
      "Bin",
      "Hex",
      "Alpha",
      "AlphaDigit",
      "Space",
      "AlphaDigitSpace",
      "DotDash",
      "Punct",
      "AlphaDash",
      "Symb",
      "AlphaSpace",
      "Base64",
      "Any",
      "TitleCaseWord"
    ]
  end
end
