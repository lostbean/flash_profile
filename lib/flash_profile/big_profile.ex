defmodule FlashProfile.BigProfile do
  @moduledoc """
  Extended profile representation for large-scale pattern learning.

  BigProfile extends the basic Profile with additional capabilities
  for handling large datasets and multiple pattern clusters.

  The BigProfile algorithm (Figure 12 from the paper) handles large datasets
  through an iterative sampling approach:

  1. Sample a subset of strings from the dataset
  2. Generate a profile for the sample
  3. Merge with existing profile and compress
  4. Remove matched strings from dataset
  5. Repeat until all strings are matched or no progress is made

  This approach scales to large datasets by:
  - Only processing small samples at a time
  - Iteratively refining the profile
  - Removing matched strings to reduce dataset size

  ## Algorithm

  ```
  func BigProfile(S, m, M, θ, μ)
    P̃ ← {}
    while |S| > 0 do
      X ← SampleRandom(S, ⌈μ·M⌉)
      P̃' ← Profile(X, m, M, θ)
      P̃ ← CompressProfile(P̃ ∪ P̃', M)
      S ← RemoveMatchingStrings(S, P̃)
    return P̃
  ```

  ## Parameters

  - `m` - Minimum number of patterns (min_patterns)
  - `M` - Maximum number of patterns (max_patterns)
  - `θ` (theta) - Pattern sampling factor (default: 1.25)
  - `μ` (mu) - String sampling factor (default: 4.0)

  ## Examples

      iex> alias FlashProfile.BigProfile
      iex> # Generate large dataset
      iex> strings = for i <- 1..1000, do: "PMC\#{String.pad_leading(Integer.to_string(i), 7, "0")}"
      iex> # Profile with sampling
      iex> profile = BigProfile.big_profile(strings, max_patterns: 5)
      iex> length(profile) <= 5
      true

      iex> # Sample random strings
      iex> alias FlashProfile.BigProfile
      iex> strings = ["a", "b", "c", "d", "e"]
      iex> sample = BigProfile.sample_random(strings, 3)
      iex> length(sample)
      3
  """

  alias FlashProfile.{ProfileEntry, Pattern, Compress}
  alias FlashProfile.Atoms.Defaults

  # Default configuration matching paper's recommendations
  @default_opts [
    min_patterns: 1,
    max_patterns: 10,
    theta: 1.25,
    mu: 4.0,
    atoms: nil,
    max_iterations: 100
  ]

  @doc """
  Profile a large dataset using sampling and iteration.

  This function implements the BigProfile algorithm from Figure 12 of the paper.
  It processes large datasets by:
  1. Sampling random subsets
  2. Profiling each subset
  3. Merging and compressing profiles
  4. Removing matched strings

  ## Parameters

    - `strings` - List of strings to profile
    - `opts` - Keyword list of options:
      - `:min_patterns` - Minimum number of patterns (default: 1)
      - `:max_patterns` - Maximum number of patterns (default: 10)
      - `:theta` - Pattern sampling factor (default: 1.25)
      - `:mu` - String sampling factor (default: 4.0)
      - `:atoms` - List of atoms to use (default: Defaults.all())
      - `:max_iterations` - Maximum iterations to prevent infinite loops (default: 100)

  ## Returns

  List of ProfileEntry structs, each containing:
  - `data` - Strings matched by this entry
  - `pattern` - Learned pattern
  - `cost` - Pattern cost

  ## Examples

      iex> alias FlashProfile.BigProfile
      iex> strings = ["PMC123", "PMC456", "PMC789"]
      iex> profile = BigProfile.big_profile(strings)
      iex> is_list(profile)
      true
      iex> length(profile) >= 1
      true
  """
  @spec big_profile([String.t()], keyword()) :: [ProfileEntry.t()]
  def big_profile(strings, opts \\ [])

  def big_profile([], _opts), do: []

  def big_profile(strings, opts) when is_list(strings) do
    # Merge options with defaults
    config = Keyword.merge(@default_opts, opts)
    max_patterns = config[:max_patterns]
    mu = config[:mu]
    max_iterations = config[:max_iterations]

    # Calculate sample size: ⌈μ·M⌉
    sample_size = ceil(mu * max_patterns)

    # If dataset is small enough, use Profile directly instead of BigProfile
    if length(strings) <= sample_size do
      # For small datasets, use the full Profile algorithm directly
      profile_small_dataset(strings, config)
    else
      # Run BigProfile iteration
      do_big_profile(strings, [], sample_size, config, 0, max_iterations)
    end
  end

  @doc """
  Sample random strings from a list.

  Uses Enum.take_random/2 to select a random subset of strings.
  If count is greater than or equal to the list size, returns all strings.

  ## Parameters

    - `strings` - List of strings to sample from
    - `count` - Number of strings to sample

  ## Returns

  List of randomly sampled strings (may be shorter if list is smaller than count).

  ## Examples

      iex> strings = ["a", "b", "c", "d", "e"]
      iex> sample = FlashProfile.BigProfile.sample_random(strings, 3)
      iex> length(sample)
      3
      iex> Enum.all?(sample, fn s -> s in strings end)
      true

      iex> small_list = ["x", "y"]
      iex> sample = FlashProfile.BigProfile.sample_random(small_list, 5)
      iex> length(sample)
      2
  """
  @spec sample_random([String.t()], pos_integer()) :: [String.t()]
  def sample_random(strings, count) when is_list(strings) and is_integer(count) and count > 0 do
    # If count >= list size, return all strings (possibly shuffled)
    if count >= length(strings) do
      strings
    else
      Enum.take_random(strings, count)
    end
  end

  @doc """
  Remove strings that match any profile entry.

  Filters out strings that match at least one pattern in the profile.
  A string matches a profile if any entry's pattern matches it.

  ## Parameters

    - `strings` - List of strings to filter
    - `profile` - List of ProfileEntry structs with patterns

  ## Returns

  List of strings that don't match any profile entry.

  ## Examples

      iex> alias FlashProfile.{BigProfile, ProfileEntry, Atoms.CharClass}
      iex> digit_pattern = [CharClass.digit()]
      iex> entry = %ProfileEntry{data: ["123"], pattern: digit_pattern, cost: 8.2}
      iex> profile = [entry]
      iex> strings = ["123", "456", "abc", "def"]
      iex> BigProfile.remove_matching_strings(strings, profile)
      ["abc", "def"]

      iex> # Empty profile returns all strings
      iex> FlashProfile.BigProfile.remove_matching_strings(["a", "b"], [])
      ["a", "b"]
  """
  @spec remove_matching_strings([String.t()], [ProfileEntry.t()]) :: [String.t()]
  def remove_matching_strings(strings, profile) when is_list(strings) and is_list(profile) do
    Enum.reject(strings, fn string ->
      matches_profile?(string, profile)
    end)
  end

  @doc """
  Check if a string matches any entry in the profile.

  A string matches the profile if it matches at least one entry's pattern.
  Entries without patterns (pattern is nil) are ignored.

  ## Parameters

    - `string` - String to check
    - `profile` - List of ProfileEntry structs

  ## Returns

  true if the string matches at least one profile entry's pattern, false otherwise.

  ## Examples

      iex> alias FlashProfile.{BigProfile, ProfileEntry, Atoms.CharClass}
      iex> digit_pattern = [CharClass.digit()]
      iex> entry = %ProfileEntry{data: ["123"], pattern: digit_pattern, cost: 8.2}
      iex> BigProfile.matches_profile?("456", [entry])
      true
      iex> BigProfile.matches_profile?("abc", [entry])
      false

      iex> # Entry with nil pattern doesn't match
      iex> entry_no_pattern = %FlashProfile.ProfileEntry{data: ["x"], pattern: nil, cost: :infinity}
      iex> FlashProfile.BigProfile.matches_profile?("x", [entry_no_pattern])
      false
  """
  @spec matches_profile?(String.t(), [ProfileEntry.t()]) :: boolean()
  def matches_profile?(string, profile) when is_binary(string) and is_list(profile) do
    Enum.any?(profile, fn entry ->
      case entry.pattern do
        nil -> false
        pattern -> Pattern.matches?(pattern, string)
      end
    end)
  end

  ## Private Functions

  # Main BigProfile iteration loop
  defp do_big_profile(strings, current_profile, sample_size, config, iteration, max_iterations) do
    # Check termination conditions
    cond do
      # All strings processed
      length(strings) == 0 ->
        current_profile

      # Maximum iterations reached (safety check)
      iteration >= max_iterations ->
        # Return current profile even if incomplete
        current_profile

      # Continue processing
      true ->
        # Sample random strings: X ← SampleRandom(S, ⌈μ·M⌉)
        sample = sample_random(strings, sample_size)

        # Profile the sample: P̃' ← Profile(X, m, M, θ)
        sample_profile = profile_sample(sample, config)

        # Merge and compress profiles: P̃ ← CompressProfile(P̃ ∪ P̃', M)
        merged_profile = merge_and_compress(current_profile, sample_profile, config)

        # Remove matching strings: S ← RemoveMatchingStrings(S, P̃)
        remaining_strings = remove_matching_strings(strings, merged_profile)

        # Check if we made progress
        if length(remaining_strings) == length(strings) do
          # No strings were removed - we're stuck, terminate
          # This can happen if no patterns match or patterns are incomplete
          merged_profile
        else
          # Continue iteration with remaining strings
          do_big_profile(
            remaining_strings,
            merged_profile,
            sample_size,
            config,
            iteration + 1,
            max_iterations
          )
        end
    end
  end

  # Profile a small dataset directly (when dataset size <= sample size)
  # Delegates to profile_sample which uses the full Profile algorithm
  defp profile_small_dataset(strings, config) do
    # For small datasets, we can use the full Profile algorithm directly
    profile_sample(strings, config)
  end

  # Profile a sample of strings using the full Profile algorithm
  # This implements the call to Profile(X, m, M, θ) from Figure 12, Step 4
  defp profile_sample(strings, config) do
    min_patterns = config[:min_patterns] || 1
    max_patterns = config[:max_patterns] || 10
    theta = config[:theta] || 1.25
    atoms = config[:atoms] || Defaults.all()

    # Call the full Profile algorithm with clustering
    FlashProfile.Profile.profile(strings, min_patterns, max_patterns, theta: theta, atoms: atoms)
  end

  # Merge two profiles and compress to max_patterns
  # Implements: P̃ ← CompressProfile(P̃ ∪ P̃', M)
  defp merge_and_compress(profile1, profile2, config) do
    max_patterns = config[:max_patterns]

    # Union of profiles
    combined = profile1 ++ profile2

    # If within limit, no compression needed
    if length(combined) <= max_patterns do
      combined
    else
      # Compress to max_patterns using the Compress module
      atoms = config[:atoms] || Defaults.all()
      Compress.compress(combined, max_patterns, atoms: atoms)
    end
  end
end
