defmodule FlashProfile.Native do
  @moduledoc """
  Zigler NIF bindings to high-performance Zig implementation of FlashProfile.

  This module provides low-level NIF functions for pattern matching and cost calculation.
  The Zig implementation provides significant performance improvements for:
  - Pattern matching (greedy left-to-right)
  - Cost calculation
  - Character class operations
  - Profile and BigProfile algorithms
  - Dissimilarity computation

  ## Usage

  The functions in this module are called by the main FlashProfile API.
  Direct usage is possible but the higher-level API is recommended.
  """

  use Zig,
    otp_app: :flash_profile,
    nifs: [
      # Inline NIFs (character matching)
      match_char_class: [],
      match_constant: [],
      get_static_cost: [],
      calculate_dynamic_weight: [],
      string_matches_class: [],
      # External NIFs (main algorithms)
      profile_nif: [:dirty_cpu],
      big_profile_nif: [:dirty_cpu],
      dissimilarity_nif: [:dirty_cpu],
      learn_pattern_nif: [:dirty_cpu],
      matches_nif: [],
      calculate_cost_nif: []
    ],
    extra_modules: [
      # Base modules with no dependencies
      types: {"./native/flash_profile/types.zig", []},
      # Atom module depends on nothing
      atom: {"./native/flash_profile/atom.zig", []},
      # Pattern depends on atom
      pattern: {"./native/flash_profile/pattern.zig", [:atom]},
      # Cost depends on atom, pattern, types
      cost: {"./native/flash_profile/cost.zig", [:atom, :pattern, :types]},
      # Learner depends on atom, pattern, cost, types
      learner: {"./native/flash_profile/learner.zig", [:atom, :pattern, :cost, :types]},
      # Hierarchy depends on types
      hierarchy: {"./native/flash_profile/hierarchy.zig", [:types]},
      # Dissimilarity depends on atom, pattern, cost, learner, types
      dissimilarity:
        {"./native/flash_profile/dissimilarity.zig", [:atom, :pattern, :cost, :learner, :types]},
      # Profile depends on atom, pattern, cost, learner, dissimilarity, hierarchy, types
      profile:
        {"./native/flash_profile/profile.zig",
         [:atom, :pattern, :cost, :learner, :dissimilarity, :hierarchy, :types]},
      # Flash profile NIF bindings depend on all the above plus beam
      flash_profile_nif:
        {"./native/flash_profile/nif.zig",
         [:beam, :atom, :pattern, :cost, :learner, :profile, :dissimilarity, :types]}
    ]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  // ============================================================================
  // CharSet - Efficient ASCII character set using 128-bit bitmap
  // ============================================================================

  const CharSet = struct {
      low: u64,
      high: u64,

      fn empty() CharSet {
          return .{ .low = 0, .high = 0 };
      }

      fn fromChars(chars: []const u8) CharSet {
          var set = empty();
          for (chars) |c| {
              set.add(c);
          }
          return set;
      }

      fn add(self: *CharSet, c: u8) void {
          if (c < 64) {
              self.low |= @as(u64, 1) << @intCast(c);
          } else if (c < 128) {
              self.high |= @as(u64, 1) << @intCast(c - 64);
          }
      }

      fn contains(self: CharSet, c: u8) bool {
          if (c < 64) {
              return (self.low & (@as(u64, 1) << @intCast(c))) != 0;
          } else if (c < 128) {
              return (self.high & (@as(u64, 1) << @intCast(c - 64))) != 0;
          }
          return false;
      }
  };

  // ============================================================================
  // Default Character Sets (from FlashProfile paper Figure 6)
  // ============================================================================

  const lower_chars = "abcdefghijklmnopqrstuvwxyz";
  const upper_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const digit_chars = "0123456789";
  const alpha_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const alphadigit_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  const space_chars = " \t\n\r";

  // Static costs from paper
  const LOWER_COST: f64 = 9.1;
  const UPPER_COST: f64 = 8.2;
  const DIGIT_COST: f64 = 8.2;
  const ALPHA_COST: f64 = 15.0;
  const ALPHADIGIT_COST: f64 = 20.0;
  const SPACE_COST: f64 = 5.0;
  const ANY_COST: f64 = 100.0;

  // ============================================================================
  // Pattern Matching
  // ============================================================================

  /// Match a variable-width character class against a string.
  /// Returns length of longest prefix with all chars in set, or 0 if no match.
  fn matchCharClass(string: []const u8, char_set: CharSet) usize {
      var count: usize = 0;
      for (string) |c| {
          if (char_set.contains(c)) {
              count += 1;
          } else {
              break;
          }
      }
      return count;
  }

  /// Match any printable ASCII character
  fn matchAny(string: []const u8) usize {
      var count: usize = 0;
      for (string) |c| {
          if (c >= 32 and c <= 126) {
              count += 1;
          } else {
              break;
          }
      }
      return count;
  }

  /// Match a constant string prefix
  fn matchConstant(string: []const u8, constant: []const u8) usize {
      if (string.len < constant.len) return 0;
      if (std.mem.eql(u8, string[0..constant.len], constant)) {
          return constant.len;
      }
      return 0;
  }

  // ============================================================================
  // NIF Functions
  // ============================================================================

  /// Match a character class against a string.
  /// atom_name: "Lower", "Upper", "Digit", "Alpha", "AlphaDigit", "Space", "Any"
  /// Returns: length of match (0 = no match)
  pub fn match_char_class(atom_name: []const u8, string: []const u8) usize {
      if (std.mem.eql(u8, atom_name, "Lower")) {
          return matchCharClass(string, CharSet.fromChars(lower_chars));
      } else if (std.mem.eql(u8, atom_name, "Upper")) {
          return matchCharClass(string, CharSet.fromChars(upper_chars));
      } else if (std.mem.eql(u8, atom_name, "Digit")) {
          return matchCharClass(string, CharSet.fromChars(digit_chars));
      } else if (std.mem.eql(u8, atom_name, "Alpha")) {
          return matchCharClass(string, CharSet.fromChars(alpha_chars));
      } else if (std.mem.eql(u8, atom_name, "AlphaDigit")) {
          return matchCharClass(string, CharSet.fromChars(alphadigit_chars));
      } else if (std.mem.eql(u8, atom_name, "Space")) {
          return matchCharClass(string, CharSet.fromChars(space_chars));
      } else if (std.mem.eql(u8, atom_name, "Any")) {
          return matchAny(string);
      }
      return 0;
  }

  /// Match a constant string prefix
  pub fn match_constant(constant: []const u8, string: []const u8) usize {
      return matchConstant(string, constant);
  }

  /// Get the static cost for a character class atom
  pub fn get_static_cost(atom_name: []const u8) f64 {
      if (std.mem.eql(u8, atom_name, "Lower")) {
          return LOWER_COST;
      } else if (std.mem.eql(u8, atom_name, "Upper")) {
          return UPPER_COST;
      } else if (std.mem.eql(u8, atom_name, "Digit")) {
          return DIGIT_COST;
      } else if (std.mem.eql(u8, atom_name, "Alpha")) {
          return ALPHA_COST;
      } else if (std.mem.eql(u8, atom_name, "AlphaDigit")) {
          return ALPHADIGIT_COST;
      } else if (std.mem.eql(u8, atom_name, "Space")) {
          return SPACE_COST;
      } else if (std.mem.eql(u8, atom_name, "Any")) {
          return ANY_COST;
      }
      return 100.0; // Default high cost
  }

  /// Calculate dynamic weight for an atom position in a pattern.
  /// W(i, S | P) = (1/|S|) * sum over s in S of (len_i(s) / |s|)
  pub fn calculate_dynamic_weight(match_lengths: []const u32, string_lengths: []const u32) f64 {
      if (match_lengths.len == 0 or string_lengths.len == 0) {
          return 0.0;
      }

      var total: f64 = 0.0;
      const n = @min(match_lengths.len, string_lengths.len);

      for (0..n) |i| {
          const match_len = match_lengths[i];
          const string_len = string_lengths[i];

          if (string_len > 0) {
              const fraction = @as(f64, @floatFromInt(match_len)) / @as(f64, @floatFromInt(string_len));
              total += fraction;
          }
      }

      return total / @as(f64, @floatFromInt(n));
  }

  /// Check if a string consists entirely of characters from a character class
  pub fn string_matches_class(atom_name: []const u8, string: []const u8) bool {
      const match_len = match_char_class(atom_name, string);
      return match_len == string.len and match_len > 0;
  }
  """

  # Import external Zig NIF functions from native/flash_profile/nif.zig
  ~Z"""
  const flash_nif = @import("flash_profile_nif");

  // Re-export NIF functions
  pub const profile_nif = flash_nif.profile_nif;
  pub const big_profile_nif = flash_nif.big_profile_nif;
  pub const dissimilarity_nif = flash_nif.dissimilarity_nif;
  pub const learn_pattern_nif = flash_nif.learn_pattern_nif;
  pub const matches_nif = flash_nif.matches_nif;
  pub const calculate_cost_nif = flash_nif.calculate_cost_nif;
  """

  # ============================================================================
  # High-level Elixir Wrapper Functions
  # ============================================================================

  @doc """
  Profile algorithm: extract patterns from a dataset.

  ## Parameters

  - `strings` - List of strings to profile
  - `min_patterns` - Minimum number of patterns to extract (default: 1)
  - `max_patterns` - Maximum number of patterns to extract (default: 10)
  - `theta` - Threshold multiplier for hierarchy building (default: 1.25)

  ## Returns

  - `{:ok, [%{pattern: [atom_names], cost: float, indices: [int]}]}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> FlashProfile.Native.profile(["PMC123", "PMC456", "PMC789"], 1, 5, 1.25)
      {:ok, [%{pattern: ["PMC", "Digit"], cost: 12.3, indices: [0, 1, 2]}]}
  """
  @spec profile([String.t()], non_neg_integer(), non_neg_integer(), float()) ::
          {:ok, [profile_entry()]} | {:error, atom()}
  def profile(strings, min_patterns \\ 1, max_patterns \\ 10, theta \\ 1.25)
      when is_list(strings) and is_integer(min_patterns) and is_integer(max_patterns) and
             is_float(theta) do
    profile_nif(strings, min_patterns, max_patterns, theta)
  end

  @doc """
  BigProfile algorithm: extract patterns from large datasets.

  Uses sampling and iterative profiling for scalability on large datasets.

  ## Parameters

  - `strings` - List of strings to profile
  - `min_patterns` - Minimum number of patterns to extract (default: 1)
  - `max_patterns` - Maximum number of patterns to extract (default: 10)
  - `theta` - Threshold multiplier for hierarchy building (default: 1.25)
  - `mu` - Sampling multiplier (sample size = mu * max_patterns, default: 4.0)

  ## Returns

  - `{:ok, [%{pattern: [atom_names], cost: float, indices: [int]}]}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> FlashProfile.Native.big_profile(large_dataset, 1, 10, 1.25, 4.0)
      {:ok, [%{pattern: ["Lower", "Digit"], cost: 15.2, indices: [0, 5, 10]}]}
  """
  @spec big_profile([String.t()], non_neg_integer(), non_neg_integer(), float(), float()) ::
          {:ok, [profile_entry()]} | {:error, atom()}
  def big_profile(strings, min_patterns \\ 1, max_patterns \\ 10, theta \\ 1.25, mu \\ 4.0)
      when is_list(strings) and is_integer(min_patterns) and is_integer(max_patterns) and
             is_float(theta) and is_float(mu) do
    big_profile_nif(strings, min_patterns, max_patterns, theta, mu)
  end

  @doc """
  Compute dissimilarity between two strings.

  The dissimilarity is the cost of the pattern that matches both strings.
  Lower cost indicates more similarity.

  ## Parameters

  - `string1` - First string
  - `string2` - Second string

  ## Returns

  - `{:ok, cost}` on success
  - `{:error, :no_pattern}` if no pattern matches both strings

  ## Examples

      iex> FlashProfile.Native.dissimilarity("PMC123", "PMC456")
      {:ok, 12.3}

      iex> FlashProfile.Native.dissimilarity("abc", "123")
      {:error, :no_pattern}
  """
  @spec dissimilarity(String.t(), String.t()) :: {:ok, float()} | {:error, atom()}
  def dissimilarity(string1, string2)
      when is_binary(string1) and is_binary(string2) do
    dissimilarity_nif(string1, string2)
  end

  @doc """
  Learn the best pattern for a list of strings.

  ## Parameters

  - `strings` - List of strings to learn from

  ## Returns

  - `{:ok, {pattern_names, cost}}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> FlashProfile.Native.learn_pattern(["abc", "def", "ghi"])
      {:ok, {["Lower"], 9.1}}
  """
  @spec learn_pattern([String.t()]) :: {:ok, {[String.t()], float()}} | {:error, atom()}
  def learn_pattern(strings) when is_list(strings) do
    learn_pattern_nif(strings)
  end

  @doc """
  Check if a pattern matches a string.

  ## Parameters

  - `pattern_names` - List of atom names representing the pattern
  - `string` - String to match against

  ## Returns

  - `true` if the pattern matches
  - `false` otherwise

  ## Examples

      iex> FlashProfile.Native.matches?(["Lower", "Digit"], "abc123")
      true

      iex> FlashProfile.Native.matches?(["Digit"], "abc")
      false
  """
  @spec matches?([String.t()], String.t()) :: boolean()
  def matches?(pattern_names, string)
      when is_list(pattern_names) and is_binary(string) do
    matches_nif(pattern_names, string)
  end

  @doc """
  Calculate the cost of a pattern over a dataset.

  ## Parameters

  - `pattern_names` - List of atom names representing the pattern
  - `strings` - List of strings to calculate cost over

  ## Returns

  - `{:ok, cost}` on success
  - `{:error, :no_match}` if the pattern doesn't match all strings
  - `{:error, :invalid_atom}` if an atom name is invalid

  ## Examples

      iex> FlashProfile.Native.calculate_cost(["Lower"], ["abc", "def"])
      {:ok, 9.1}

      iex> FlashProfile.Native.calculate_cost(["Digit"], ["abc"])
      {:error, :no_match}
  """
  @spec calculate_cost([String.t()], [String.t()]) :: {:ok, float()} | {:error, atom()}
  def calculate_cost(pattern_names, strings)
      when is_list(pattern_names) and is_list(strings) do
    calculate_cost_nif(pattern_names, strings)
  end

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc """
  A profile entry representing a pattern cluster.

  - `pattern` - List of atom names (e.g., ["Lower", "Digit"])
  - `cost` - Cost of the pattern
  - `indices` - Indices of strings in the dataset that match this pattern
  """
  @type profile_entry :: %{
          pattern: [String.t()],
          cost: float(),
          indices: [non_neg_integer()]
        }
end
