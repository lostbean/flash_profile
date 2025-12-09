defmodule FlashProfile.Token do
  @moduledoc """
  Token types and structures for string analysis.

  Tokens represent atomic units of a string's structure:
  - Literal characters or sequences
  - Character classes (digits, letters, etc.)
  - Whitespace
  - Punctuation/delimiters
  """

  @type token_type ::
          :digits
          | :upper
          | :lower
          | :alpha
          | :alnum
          | :whitespace
          | :delimiter
          | :literal

  @type t :: %__MODULE__{
          type: token_type(),
          value: String.t(),
          length: pos_integer(),
          position: non_neg_integer()
        }

  defstruct [:type, :value, :length, :position]

  @doc """
  Creates a new token.
  """
  def new(type, value, position \\ 0) do
    %__MODULE__{
      type: type,
      value: value,
      length: String.length(value),
      position: position
    }
  end

  @doc """
  Returns a signature character for the token type.
  Used for structural comparison.
  """
  def signature_char(%__MODULE__{type: :digits}), do: "D"
  def signature_char(%__MODULE__{type: :upper}), do: "U"
  def signature_char(%__MODULE__{type: :lower}), do: "L"
  def signature_char(%__MODULE__{type: :alpha}), do: "A"
  def signature_char(%__MODULE__{type: :alnum}), do: "X"
  def signature_char(%__MODULE__{type: :whitespace}), do: "_"
  def signature_char(%__MODULE__{type: :delimiter, value: v}), do: v
  def signature_char(%__MODULE__{type: :literal, value: v}), do: v

  @doc """
  Returns a length-aware signature for the token.
  E.g., 3 uppercase letters → "UUU" or "U{3}"
  """
  def signature(%__MODULE__{type: type, length: len} = token) when len > 1 do
    char = signature_char(token)

    if type in [:delimiter, :literal] do
      token.value
    else
      String.duplicate(char, len)
    end
  end

  def signature(%__MODULE__{} = token), do: signature_char(token)

  @doc """
  Checks if two tokens are structurally compatible.
  """
  def compatible?(%__MODULE__{type: t1}, %__MODULE__{type: t2}) do
    compatible_types?(t1, t2)
  end

  defp compatible_types?(same, same), do: true
  defp compatible_types?(:upper, :lower), do: true
  defp compatible_types?(:lower, :upper), do: true
  defp compatible_types?(:alpha, :upper), do: true
  defp compatible_types?(:alpha, :lower), do: true
  defp compatible_types?(:upper, :alpha), do: true
  defp compatible_types?(:lower, :alpha), do: true
  defp compatible_types?(_, _), do: false
end
