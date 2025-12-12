# Pattern Module Examples
# Run with: mix run examples/pattern_examples.exs

alias FlashProfile.{Pattern, Atom}
alias FlashProfile.Atoms.CharClass

IO.puts("=== FlashProfile Pattern Module Examples ===\n")

# Example 1: PMC IDs (from the paper)
IO.puts("Example 1: PMC (PubMed Central) IDs")
IO.puts("Pattern: \"PMC\" ◇ Digit×7")

pmc = Atom.constant("PMC")
digit7 = Atom.char_class("Digit", ~c"0123456789", 7, 8.2)
pmc_pattern = [pmc, digit7]

pmc_ids = ["PMC1234567", "PMC9876543", "PMC123456", "PMC12345678", "XYZ1234567"]

Enum.each(pmc_ids, fn id ->
  matches = Pattern.matches?(pmc_pattern, id)
  IO.puts("  #{id}: #{if matches, do: "✓", else: "✗"}")
end)

IO.puts("\nPattern string: #{Pattern.to_string(pmc_pattern)}")
IO.puts("")

# Example 2: Date Format (YYYY-MM-DD)
IO.puts("Example 2: ISO Date Format (YYYY-MM-DD)")
IO.puts("Pattern: Digit×4 ◇ \"-\" ◇ Digit×2 ◇ \"-\" ◇ Digit×2")

digit4 = Atom.char_class("Digit", ~c"0123456789", 4, 8.2)
digit2 = Atom.char_class("Digit", ~c"0123456789", 2, 8.2)
dash = Atom.constant("-")
date_pattern = [digit4, dash, digit2, dash, digit2]

dates = ["2024-12-11", "2024-1-11", "24-12-11", "2024/12/11", "2024-12-1"]

Enum.each(dates, fn date ->
  matches = Pattern.matches?(date_pattern, date)
  IO.puts("  #{date}: #{if matches, do: "✓", else: "✗"}")
end)

IO.puts("\nPattern string: #{Pattern.to_string(date_pattern)}")
IO.puts("")

# Example 3: Email Username Pattern
IO.puts("Example 3: Simple Email Username")
IO.puts("Pattern: Lower+ ◇ \".\" ◇ Lower+ ◇ \"@\"")

lower = CharClass.lower()
dot = Atom.constant(".")
at = Atom.constant("@")
email_pattern = [lower, dot, lower, at]

usernames = ["john.doe@", "jane.smith@", "bob@", "alice.b.cooper@", "user@"]

Enum.each(usernames, fn user ->
  matches = Pattern.matches?(email_pattern, user)
  IO.puts("  #{user}: #{if matches, do: "✓", else: "✗"}")
end)

IO.puts("\nPattern string: #{Pattern.to_string(email_pattern)}")
IO.puts("")

# Example 4: Capitalized Word
IO.puts("Example 4: Capitalized Word")
IO.puts("Pattern: Upper ◇ Lower+")

upper = CharClass.upper()
cap_pattern = [upper, lower]

words = ["Hello", "HELLO", "hello", "H", "HeLLo", "World"]

Enum.each(words, fn word ->
  matches = Pattern.matches?(cap_pattern, word)
  IO.puts("  #{word}: #{if matches, do: "✓", else: "✗"}")
end)

IO.puts("\nPattern string: #{Pattern.to_string(cap_pattern)}")
IO.puts("")

# Example 5: Detailed Match Information
IO.puts("Example 5: Detailed Match Information")
test_string = "PMC1234567"

case Pattern.match(pmc_pattern, test_string) do
  {:ok, matches} ->
    IO.puts("String: \"#{test_string}\"")
    IO.puts("Pattern: #{Pattern.to_string(pmc_pattern)}")
    IO.puts("\nMatch Details:")
    Enum.each(matches, fn {atom, matched_str, pos, len} ->
      IO.puts("  Atom: #{atom.name}")
      IO.puts("    Matched: \"#{matched_str}\"")
      IO.puts("    Position: #{pos}")
      IO.puts("    Length: #{len}")
    end)

    lengths = Pattern.match_lengths(pmc_pattern, test_string)
    IO.puts("\nMatch lengths: #{inspect(lengths)}")

  {:error, reason} ->
    IO.puts("No match: #{reason}")
end

IO.puts("")

# Example 6: Pattern Composition
IO.puts("Example 6: Pattern Composition")

# Build a URL pattern: "http://" or "https://" + domain
http = Atom.constant("http://")
https = Atom.constant("https://")
alpha_digit = CharClass.alpha_digit()

# We can only test one variant at a time (http or https)
http_pattern = [http, alpha_digit, dot, alpha_digit]
https_pattern = [https, alpha_digit, dot, alpha_digit]

test_urls = [
  "http://example.com",
  "https://example.com",
  "http://test.org",
  "ftp://test.org"
]

IO.puts("Testing with HTTP pattern:")
Enum.each(test_urls, fn url ->
  matches = Pattern.matches?(http_pattern, url)
  IO.puts("  #{url}: #{if matches, do: "✓", else: "✗"}")
end)

IO.puts("\nTesting with HTTPS pattern:")
Enum.each(test_urls, fn url ->
  matches = Pattern.matches?(https_pattern, url)
  IO.puts("  #{url}: #{if matches, do: "✓", else: "✗"}")
end)

IO.puts("")

# Example 7: Greedy Matching Behavior
IO.puts("Example 7: Understanding Greedy Matching")
IO.puts("Pattern: Lower+ ◇ Lower+")
IO.puts("String: \"hello\"")

greedy_pattern = [lower, lower]
result = Pattern.match(greedy_pattern, "hello")

IO.puts("\nResult: #{inspect(result)}")
IO.puts("Explanation: First Lower+ greedily consumes ALL lowercase letters,")
IO.puts("leaving nothing for the second Lower+. Pattern fails to match.")
IO.puts("")

# Example 8: Pattern Utilities
IO.puts("Example 8: Pattern Utility Functions")

pattern = [upper, digit4, dash, lower]

IO.puts("Pattern: #{Pattern.to_string(pattern)}")
IO.puts("Length: #{Pattern.length(pattern)} atoms")
IO.puts("Empty?: #{Pattern.empty?(pattern)}")
IO.puts("First atom: #{Pattern.first(pattern).name}")
IO.puts("Last atom: #{Pattern.last(pattern).name}")

# Concatenate patterns
p1 = [upper, digit4]
p2 = [dash, lower]
concatenated = Pattern.concat(p1, p2)
IO.puts("\nConcatenated pattern: #{Pattern.to_string(concatenated)}")

# Append an atom
appended = Pattern.append([upper], digit4)
IO.puts("Appended pattern: #{Pattern.to_string(appended)}")

IO.puts("\n=== Examples Complete ===")
