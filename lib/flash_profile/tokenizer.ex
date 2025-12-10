defmodule FlashProfile.Tokenizer do
  @moduledoc """
  Tokenizes strings into structural components.

  The tokenizer breaks strings into runs of similar characters:
  - Consecutive digits → :digits token
  - Consecutive uppercase → :upper token
  - Consecutive lowercase → :lower token
  - Whitespace → :whitespace token
  - Punctuation/delimiters → :delimiter token (single char)
  """

  alias FlashProfile.Token

  @delimiters ~c"-_./\\@#$%^&*()+=[]{}|;:'\",<>?!`~"
  @whitespace ~c" \t\n\r"

  @type tokenize_opts :: [
          merge_alpha: boolean(),
          preserve_case: boolean()
        ]

  @doc """
  Tokenizes a string into a list of tokens.

  ## Options
  - `:merge_alpha` - Merge upper/lower into :alpha (default: false)
  - `:preserve_case` - Keep original case info even when merging (default: true)

  ## Examples

      iex> tokens = FlashProfile.Tokenizer.tokenize("ABC-123")
      iex> Enum.map(tokens, fn t -> {t.type, t.value} end)
      [{:upper, "ABC"}, {:delimiter, "-"}, {:digits, "123"}]
  """
  @spec tokenize(String.t(), tokenize_opts()) :: [Token.t()]
  def tokenize(string, opts \\ []) when is_binary(string) do
    string
    |> String.to_charlist()
    |> do_tokenize(0, [])
    |> Enum.reverse()
    |> maybe_merge_alpha(opts)
  end

  defp do_tokenize([], _pos, acc), do: acc

  defp do_tokenize([char | rest], pos, acc) do
    type = classify_char(char)

    case type do
      :delimiter ->
        token = Token.new(:delimiter, <<char::utf8>>, pos)
        do_tokenize(rest, pos + 1, [token | acc])

      :whitespace ->
        {ws_chars, remaining} = collect_while(rest, &whitespace?/1)
        value = <<char::utf8>> <> to_string(ws_chars)
        token = Token.new(:whitespace, value, pos)
        do_tokenize(remaining, pos + String.length(value), [token | acc])

      char_type ->
        {same_chars, remaining} = collect_while(rest, &(classify_char(&1) == char_type))
        value = <<char::utf8>> <> to_string(same_chars)
        token = Token.new(char_type, value, pos)
        do_tokenize(remaining, pos + String.length(value), [token | acc])
    end
  end

  defp classify_char(char) when char in @delimiters, do: :delimiter
  defp classify_char(char) when char in @whitespace, do: :whitespace
  defp classify_char(char) when char in ?0..?9, do: :digits
  defp classify_char(char) when char in ?A..?Z, do: :upper
  defp classify_char(char) when char in ?a..?z, do: :lower
  defp classify_char(_char), do: :literal

  defp whitespace?(char), do: char in @whitespace

  defp collect_while(chars, pred, acc \\ [])
  defp collect_while([], _pred, acc), do: {Enum.reverse(acc), []}

  defp collect_while([char | rest] = chars, pred, acc) do
    if pred.(char) do
      collect_while(rest, pred, [char | acc])
    else
      {Enum.reverse(acc), chars}
    end
  end

  defp maybe_merge_alpha(tokens, opts) do
    if Keyword.get(opts, :merge_alpha, false) do
      merge_adjacent_alpha(tokens)
    else
      tokens
    end
  end

  defp merge_adjacent_alpha(tokens) do
    tokens
    |> Enum.reduce([], fn token, acc ->
      case {token.type, acc} do
        {type, [%Token{type: prev_type} = prev | rest]}
        when type in [:upper, :lower, :alpha] and prev_type in [:upper, :lower, :alpha] ->
          merged =
            Token.new(
              :alpha,
              prev.value <> token.value,
              prev.position
            )

          [merged | rest]

        _ ->
          [token | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Generates a structural signature from tokens.

  ## Examples

      iex> FlashProfile.Tokenizer.signature("ACC-00123")
      "UUU-DDDDD"

      iex> FlashProfile.Tokenizer.signature("hello@world.com")
      "LLLLL@LLLLL.LLL"
  """
  @spec signature(String.t() | [Token.t()]) :: String.t()
  def signature(string) when is_binary(string) do
    string |> tokenize() |> signature()
  end

  def signature(tokens) when is_list(tokens) do
    tokens
    |> Enum.map(&Token.signature/1)
    |> Enum.join()
  end

  @doc """
  Generates a compact signature (length-agnostic for char classes).

  ## Examples

      iex> FlashProfile.Tokenizer.compact_signature("ACC-00123")
      "U-D"

      iex> FlashProfile.Tokenizer.compact_signature("ACCT-00123")
      "U-D"
  """
  @spec compact_signature(String.t() | [Token.t()]) :: String.t()
  def compact_signature(string) when is_binary(string) do
    string |> tokenize() |> compact_signature()
  end

  def compact_signature(tokens) when is_list(tokens) do
    tokens
    |> Enum.map(&Token.signature_char/1)
    |> Enum.join()
  end

  @doc """
  Returns tokens with their positions annotated.
  """
  @spec tokenize_with_positions(String.t()) :: [
          {Token.t(), {non_neg_integer(), non_neg_integer()}}
        ]
  def tokenize_with_positions(string) do
    tokens = tokenize(string)

    Enum.map(tokens, fn token ->
      {token, {token.position, token.position + token.length}}
    end)
  end
end
