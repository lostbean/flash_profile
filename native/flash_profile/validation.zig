// Input validation for FlashProfile NIF entry points
//
// All errors return {:error, reason} tuples to Elixir.
// Limits are permissive by design (user preference).

const std = @import("std");
const beam = @import("beam");

// ============================================================================
// Validation Limits (Permissive)
// ============================================================================

pub const Limits = struct {
    /// Maximum number of strings in a dataset
    pub const MAX_STRINGS_COUNT: usize = 100_000;

    /// Maximum length of a single string (100KB)
    pub const MAX_STRING_LENGTH: usize = 100_000;

    /// Maximum total bytes across all strings (1GB)
    pub const MAX_TOTAL_BYTES: usize = 1_000_000_000;

    /// Maximum number of pattern name parts
    pub const MAX_PATTERN_NAMES: usize = 100;

    /// Maximum value for max_patterns parameter
    pub const MAX_PATTERNS_UPPER: usize = 1000;

    /// Maximum value for theta parameter
    pub const THETA_MAX: f64 = 100.0;

    /// Maximum value for mu parameter
    pub const MU_MAX: f64 = 100.0;
};

// ============================================================================
// Validation Error Types
// ============================================================================

pub const ValidationError = enum {
    /// Too many strings in the input
    too_many_strings,

    /// A string exceeds maximum allowed length
    string_too_long,

    /// Total size of all strings exceeds limit
    total_size_exceeded,

    /// Invalid min_patterns value (must be >= 1)
    invalid_min_patterns,

    /// Invalid max_patterns value (must be >= min_patterns and <= 1000)
    invalid_max_patterns,

    /// Invalid theta value (must be > 0 and <= 100)
    invalid_theta,

    /// Invalid mu value (must be > 0 and <= 100)
    invalid_mu,

    /// Pattern names array too long
    pattern_too_long,

    /// NaN or infinity in numeric parameter
    invalid_number,
};

// ============================================================================
// Validation Functions
// ============================================================================

/// Validate a strings array for size and length limits
/// Returns error atom or null if valid
pub fn validateStrings(strings: []const []const u8) ?ValidationError {
    // Check count
    if (strings.len > Limits.MAX_STRINGS_COUNT) {
        return .too_many_strings;
    }

    // Check individual strings and total size
    var total_bytes: usize = 0;
    for (strings) |s| {
        if (s.len > Limits.MAX_STRING_LENGTH) {
            return .string_too_long;
        }
        total_bytes += s.len;
        if (total_bytes > Limits.MAX_TOTAL_BYTES) {
            return .total_size_exceeded;
        }
    }

    return null;
}

/// Validate pattern names array
pub fn validatePatternNames(pattern_names: []const []const u8) ?ValidationError {
    if (pattern_names.len > Limits.MAX_PATTERN_NAMES) {
        return .pattern_too_long;
    }
    return null;
}

/// Validate min_patterns parameter
pub fn validateMinPatterns(min_patterns: usize) ?ValidationError {
    if (min_patterns == 0) {
        return .invalid_min_patterns;
    }
    return null;
}

/// Validate max_patterns parameter (requires min_patterns for comparison)
pub fn validateMaxPatterns(max_patterns: usize, min_patterns: usize) ?ValidationError {
    if (max_patterns < min_patterns) {
        return .invalid_max_patterns;
    }
    if (max_patterns > Limits.MAX_PATTERNS_UPPER) {
        return .invalid_max_patterns;
    }
    return null;
}

/// Validate theta parameter
pub fn validateTheta(theta: f64) ?ValidationError {
    if (std.math.isNan(theta) or std.math.isInf(theta)) {
        return .invalid_number;
    }
    if (theta <= 0 or theta > Limits.THETA_MAX) {
        return .invalid_theta;
    }
    return null;
}

/// Validate mu parameter
pub fn validateMu(mu: f64) ?ValidationError {
    if (std.math.isNan(mu) or std.math.isInf(mu)) {
        return .invalid_number;
    }
    if (mu <= 0 or mu > Limits.MU_MAX) {
        return .invalid_mu;
    }
    return null;
}

/// Validate a single string length
pub fn validateStringLength(s: []const u8) ?ValidationError {
    if (s.len > Limits.MAX_STRING_LENGTH) {
        return .string_too_long;
    }
    return null;
}

// ============================================================================
// BEAM Error Term Generation
// ============================================================================

/// Convert validation error to BEAM error tuple
pub fn makeErrorTerm(err: ValidationError) beam.term {
    return beam.make(.{ .@"error", err }, .{});
}

// ============================================================================
// Tests
// ============================================================================

test "validateStrings: empty array is valid" {
    const strings = [_][]const u8{};
    try std.testing.expect(validateStrings(&strings) == null);
}

test "validateStrings: normal array is valid" {
    const strings = [_][]const u8{ "hello", "world", "test" };
    try std.testing.expect(validateStrings(&strings) == null);
}

test "validateStrings: string too long" {
    var long_string: [Limits.MAX_STRING_LENGTH + 1]u8 = undefined;
    @memset(&long_string, 'a');
    const strings = [_][]const u8{&long_string};
    try std.testing.expect(validateStrings(&strings) == .string_too_long);
}

test "validateStrings: at limit is valid" {
    var at_limit_string: [Limits.MAX_STRING_LENGTH]u8 = undefined;
    @memset(&at_limit_string, 'a');
    const strings = [_][]const u8{&at_limit_string};
    try std.testing.expect(validateStrings(&strings) == null);
}

test "validatePatternNames: empty is valid" {
    const names = [_][]const u8{};
    try std.testing.expect(validatePatternNames(&names) == null);
}

test "validatePatternNames: normal is valid" {
    const names = [_][]const u8{ "digit", "alpha", "space" };
    try std.testing.expect(validatePatternNames(&names) == null);
}

test "validateMinPatterns: zero is invalid" {
    try std.testing.expect(validateMinPatterns(0) == .invalid_min_patterns);
}

test "validateMinPatterns: one is valid" {
    try std.testing.expect(validateMinPatterns(1) == null);
}

test "validateMaxPatterns: less than min is invalid" {
    try std.testing.expect(validateMaxPatterns(5, 10) == .invalid_max_patterns);
}

test "validateMaxPatterns: greater than limit is invalid" {
    try std.testing.expect(validateMaxPatterns(Limits.MAX_PATTERNS_UPPER + 1, 1) == .invalid_max_patterns);
}

test "validateMaxPatterns: valid range" {
    try std.testing.expect(validateMaxPatterns(10, 5) == null);
    try std.testing.expect(validateMaxPatterns(Limits.MAX_PATTERNS_UPPER, 1) == null);
}

test "validateTheta: zero is invalid" {
    try std.testing.expect(validateTheta(0.0) == .invalid_theta);
}

test "validateTheta: negative is invalid" {
    try std.testing.expect(validateTheta(-1.0) == .invalid_theta);
}

test "validateTheta: NaN is invalid" {
    try std.testing.expect(validateTheta(std.math.nan(f64)) == .invalid_number);
}

test "validateTheta: infinity is invalid" {
    try std.testing.expect(validateTheta(std.math.inf(f64)) == .invalid_number);
}

test "validateTheta: valid value" {
    try std.testing.expect(validateTheta(0.5) == null);
    try std.testing.expect(validateTheta(Limits.THETA_MAX) == null);
}

test "validateTheta: over limit is invalid" {
    try std.testing.expect(validateTheta(Limits.THETA_MAX + 0.1) == .invalid_theta);
}

test "validateMu: zero is invalid" {
    try std.testing.expect(validateMu(0.0) == .invalid_mu);
}

test "validateMu: valid value" {
    try std.testing.expect(validateMu(0.1) == null);
    try std.testing.expect(validateMu(Limits.MU_MAX) == null);
}

test "validateStringLength: normal string is valid" {
    try std.testing.expect(validateStringLength("hello world") == null);
}

test "validateStringLength: empty string is valid" {
    try std.testing.expect(validateStringLength("") == null);
}
