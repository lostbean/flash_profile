const std = @import("std");
const Allocator = std.mem.Allocator;
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const pattern_mod = @import("pattern.zig");
const Pattern = pattern_mod.Pattern;
const types = @import("types.zig");
const Cost = types.Cost;

/// Calculate the FlashProfile cost function for a pattern over a dataset
///
/// From the paper (Section 4.3):
/// C_FP(P, S) = Σ Q(αi) · W(i, S | P)
///
/// Where:
/// - Q(αi) is the static cost of atom i
/// - W(i, S | P) is the dynamic weight (average fraction of string consumed by atom i)
/// - len_i(s) is the length matched by atom i on string s
///
/// Returns:
/// - Cost.infinity if pattern doesn't match all strings
/// - Cost.finite(0.0) for empty pattern on empty dataset
/// - Cost.finite(0.0) for any pattern on empty dataset (vacuous truth)
/// - Cost.infinity for empty pattern on non-empty dataset
///
/// ## Edge Cases
///
/// - **Empty pattern on empty dataset**: Returns 0.0 (vacuous truth)
/// - **Empty strings in dataset**: Empty strings contribute 0.0 to the dynamic weight
///   calculation (avoiding division by zero). This means empty strings effectively
///   don't affect the cost.
/// - **Pattern on empty dataset**: Returns 0.0 (any pattern vacuously matches empty set)
pub fn calculateCost(
    pattern: []const Atom,
    strings: []const []const u8,
    allocator: Allocator,
) !Cost {
    // Edge case: empty pattern on empty dataset
    if (pattern.len == 0 and strings.len == 0) {
        return Cost.fromFinite(0.0);
    }

    // Edge case: empty pattern on non-empty dataset = infinity
    if (pattern.len == 0 and strings.len > 0) {
        return Cost.asInfinity();
    }

    // Edge case: pattern on empty dataset = 0.0 (vacuous truth)
    if (strings.len == 0) {
        return Cost.fromFinite(0.0);
    }

    // Get match lengths for all strings
    var all_lengths = try getAllMatchLengths(pattern, strings, allocator);
    defer {
        for (all_lengths.items) |lengths| {
            allocator.free(lengths);
        }
        all_lengths.deinit(allocator);
    }

    // Check if all strings matched (all_lengths entries are non-null)
    var all_matched = true;
    for (all_lengths.items) |lengths| {
        if (lengths.len == 0) {
            all_matched = false;
            break;
        }
    }

    if (!all_matched) {
        return Cost.asInfinity();
    }

    // Calculate cost as sum over atoms
    var total_cost: f64 = 0.0;

    for (pattern, 0..) |atom_val, idx| {
        const static_cost = atom_val.static_cost;
        const dynamic_weight = calculateDynamicWeight(all_lengths.items, strings, idx);
        total_cost += static_cost * dynamic_weight;
    }

    return Cost.fromFinite(total_cost);
}

/// Calculate the dynamic weight for atom at position `atom_index`
///
/// W(i, S | P) = (1/|S|) · Σ_{s∈S} (αi(si) / |s|)
///
/// This is the average fraction of the original string length that
/// this atom matches across all strings.
///
/// Where:
/// - s1 = s (the original string)
/// - si+1 = si[αi(si):] (remaining suffix after matching atom αi)
/// - αi(si) is the length matched by atom i on string si
/// - |s| is the total length of the original string
pub fn dynamicWeight(
    position: usize,
    pattern: []const Atom,
    strings: []const []const u8,
    allocator: Allocator,
) !f64 {
    if (strings.len == 0) {
        return 0.0;
    }

    // Get match lengths for all strings
    var all_lengths = try getAllMatchLengths(pattern, strings, allocator);
    defer {
        for (all_lengths.items) |lengths| {
            allocator.free(lengths);
        }
        all_lengths.deinit(allocator);
    }

    return calculateDynamicWeight(all_lengths.items, strings, position);
}

/// Calculate dynamic weight from pre-computed match lengths
fn calculateDynamicWeight(
    all_lengths: []const []const usize,
    strings: []const []const u8,
    atom_index: usize,
) f64 {
    const num_strings = strings.len;
    if (num_strings == 0) {
        return 0.0;
    }

    var total: f64 = 0.0;

    for (all_lengths, 0..) |lengths, i| {
        // Get the length matched by this atom
        const atom_length = if (atom_index < lengths.len)
            lengths[atom_index]
        else
            0;

        const string_length = strings[i].len;

        if (string_length > 0) {
            const fraction = @as(f64, @floatFromInt(atom_length)) / @as(f64, @floatFromInt(string_length));
            total += fraction;
        }
        // Empty strings contribute 0.0
    }

    return total / @as(f64, @floatFromInt(num_strings));
}

/// Get match lengths for a pattern across all strings
///
/// Returns ArrayList of length arrays. Each inner array contains the lengths
/// matched by each atom for one string. If a string doesn't match, returns
/// an empty array for that string.
fn getAllMatchLengths(
    pattern: []const Atom,
    strings: []const []const u8,
    allocator: Allocator,
) !std.ArrayList([]const usize) {
    var results: std.ArrayList([]const usize) = .{};
    errdefer {
        for (results.items) |lengths| {
            allocator.free(lengths);
        }
        results.deinit(allocator);
    }

    const pat = Pattern.init(pattern);

    for (strings) |string| {
        const lengths = try pat.matchLengths(allocator, string);
        if (lengths) |l| {
            try results.append(allocator, l);
        } else {
            // Pattern doesn't match - append empty array
            const empty = try allocator.alloc(usize, 0);
            try results.append(allocator, empty);
        }
    }

    return results;
}

/// Cost breakdown for a single atom
pub const CostBreakdown = struct {
    atom_index: usize,
    static_cost: f64,
    dynamic_weight: f64,
    contribution: f64,
};

/// Result of detailed cost calculation
pub const DetailedCostResult = struct {
    total_cost: f64,
    breakdown: []CostBreakdown,
    allocator: Allocator,

    pub fn deinit(self: *DetailedCostResult) void {
        self.allocator.free(self.breakdown);
    }
};

/// Calculate cost with detailed breakdown for each atom
///
/// Returns null if pattern doesn't match all strings in the dataset.
///
/// ## Parameters
///
/// - `pattern` - List of atoms forming the pattern
/// - `strings` - List of strings to evaluate the pattern against
/// - `allocator` - Memory allocator
///
/// ## Returns
///
/// - `DetailedCostResult` - Success with detailed breakdown
/// - `null` - Pattern doesn't match all strings
pub fn calculateCostDetailed(
    pattern: []const Atom,
    strings: []const []const u8,
    allocator: Allocator,
) !?DetailedCostResult {
    // Edge cases
    if (pattern.len == 0 and strings.len == 0) {
        const breakdown = try allocator.alloc(CostBreakdown, 0);
        return DetailedCostResult{
            .total_cost = 0.0,
            .breakdown = breakdown,
            .allocator = allocator,
        };
    }

    if (pattern.len == 0 and strings.len > 0) {
        return null; // Error: empty pattern on non-empty strings
    }

    if (strings.len == 0) {
        const breakdown = try allocator.alloc(CostBreakdown, 0);
        return DetailedCostResult{
            .total_cost = 0.0,
            .breakdown = breakdown,
            .allocator = allocator,
        };
    }

    // Get match lengths
    var all_lengths = try getAllMatchLengths(pattern, strings, allocator);
    defer {
        for (all_lengths.items) |lengths| {
            allocator.free(lengths);
        }
        all_lengths.deinit(allocator);
    }

    // Check if all strings matched
    for (all_lengths.items) |lengths| {
        if (lengths.len == 0) {
            return null; // Pattern doesn't match all strings
        }
    }

    // Build breakdown
    const breakdown = try allocator.alloc(CostBreakdown, pattern.len);
    errdefer allocator.free(breakdown);

    var total_cost: f64 = 0.0;

    for (pattern, 0..) |atom_val, i| {
        const static_cost = atom_val.static_cost;
        const dynamic_weight = calculateDynamicWeight(all_lengths.items, strings, i);
        const contribution = static_cost * dynamic_weight;

        breakdown[i] = .{
            .atom_index = i,
            .static_cost = static_cost,
            .dynamic_weight = dynamic_weight,
            .contribution = contribution,
        };

        total_cost += contribution;
    }

    return DetailedCostResult{
        .total_cost = total_cost,
        .breakdown = breakdown,
        .allocator = allocator,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "cost: empty pattern on empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const pattern = [_]Atom{};
    const strings = [_][]const u8{};

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expectEqual(@as(f64, 0.0), cost.finite);
}

test "cost: empty pattern on non-empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const pattern = [_]Atom{};
    const strings = [_][]const u8{"test"};

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .infinity);
}

test "cost: pattern on empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const pattern = [_]Atom{d};
    const strings = [_][]const u8{};

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expectEqual(@as(f64, 0.0), cost.finite);
}

test "cost: simple pattern matching" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const u = atom_mod.upper();
    const d = atom_mod.digit();
    const pattern = [_]Atom{ u, d };
    const strings = [_][]const u8{ "A123", "B456" };

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expect(cost.finite > 0.0);
}

test "cost: pattern doesn't match" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const pattern = [_]Atom{d};
    const strings = [_][]const u8{"abc"};

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .infinity);
}

test "cost: dynamic weight calculation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const u = atom_mod.upper();
    const d = atom_mod.digit();
    const pattern = [_]Atom{ u, d };

    // "A123" -> Upper matches 1 char (1/4 = 0.25), Digit matches 3 chars (3/4 = 0.75)
    const strings = [_][]const u8{"A123"};

    const weight0 = try dynamicWeight(0, &pattern, &strings, allocator);
    const weight1 = try dynamicWeight(1, &pattern, &strings, allocator);

    try testing.expectApproxEqAbs(@as(f64, 0.25), weight0, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.75), weight1, 0.001);
}

test "cost: detailed breakdown" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const pattern = [_]Atom{d};
    const strings = [_][]const u8{"123"};

    var result = try calculateCostDetailed(&pattern, &strings, allocator);
    defer if (result) |*r| r.deinit();

    try testing.expect(result != null);
    try testing.expectEqual(@as(usize, 1), result.?.breakdown.len);
    try testing.expectEqual(@as(f64, 1.0), result.?.breakdown[0].dynamic_weight);
}

test "cost: complex multi-atom pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test cost calculation for pattern with 4+ atoms
    // Pattern: Upper + Digit + DotDash + Lower + Digit
    const u = atom_mod.upper();
    const d = atom_mod.digit();
    const dd = atom_mod.dotDash();
    const l = atom_mod.lower();
    const pattern = [_]Atom{ u, d, dd, l, d };

    // Test strings matching the pattern: "A1-b2", "Z9.x5"
    const strings = [_][]const u8{ "A1-b2", "Z9.x5" };

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expect(cost.finite > 0.0);

    // Verify detailed breakdown works correctly
    var result = try calculateCostDetailed(&pattern, &strings, allocator);
    defer if (result) |*r| r.deinit();

    try testing.expect(result != null);
    try testing.expectEqual(@as(usize, 5), result.?.breakdown.len);

    // Each atom should contribute to the total cost
    var sum: f64 = 0.0;
    for (result.?.breakdown) |item| {
        try testing.expect(item.contribution >= 0.0);
        sum += item.contribution;
    }
    try testing.expectApproxEqAbs(result.?.total_cost, sum, 0.001);
}

test "cost: very long strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test cost calculation with strings of 100+ characters
    // Verify no overflow or precision issues
    const d = atom_mod.digit();
    const l = atom_mod.lower();
    const pattern = [_]Atom{ d, l };

    // Create long strings (100+ chars)
    // Format: "1" + 100 'a's + "2" + 100 'b's
    var string1: std.ArrayList(u8) = .{};
    defer string1.deinit(allocator);
    try string1.append(allocator, '1');
    {
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            try string1.append(allocator, 'a');
        }
    }

    var string2: std.ArrayList(u8) = .{};
    defer string2.deinit(allocator);
    try string2.append(allocator, '2');
    {
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            try string2.append(allocator, 'b');
        }
    }

    const strings = [_][]const u8{ string1.items, string2.items };

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expect(cost.finite > 0.0);

    // Verify dynamic weights are reasonable (each string is 101 chars)
    const weight0 = try dynamicWeight(0, &pattern, &strings, allocator);
    const weight1 = try dynamicWeight(1, &pattern, &strings, allocator);

    // First atom (digit) matches 1 char out of 101 = ~0.0099
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 101.0), weight0, 0.001);
    // Second atom (lower) matches 100 chars out of 101 = ~0.9901
    try testing.expectApproxEqAbs(@as(f64, 100.0 / 101.0), weight1, 0.001);
}

test "cost: pattern with repeated atom type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test pattern like [Digit, Digit, Digit]
    // Verify cost accumulation is correct
    // Use fixed-width atoms to match exactly 1 char each
    const d = atom_mod.withFixedWidth(atom_mod.digit(), 1);
    const pattern = [_]Atom{ d, d, d };

    const strings = [_][]const u8{ "123", "456", "789" };

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expect(cost.finite > 0.0);

    // Check detailed breakdown
    var result = try calculateCostDetailed(&pattern, &strings, allocator);
    defer if (result) |*r| r.deinit();

    try testing.expect(result != null);
    try testing.expectEqual(@as(usize, 3), result.?.breakdown.len);

    // Each digit atom should have the same static cost
    const static_cost = result.?.breakdown[0].static_cost;
    try testing.expectEqual(static_cost, result.?.breakdown[1].static_cost);
    try testing.expectEqual(static_cost, result.?.breakdown[2].static_cost);

    // Each digit matches exactly 1 char out of 3 = 1/3 dynamic weight
    for (result.?.breakdown) |item| {
        try testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), item.dynamic_weight, 0.001);
    }
}

test "cost: dynamic weight with uniform matches" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test when all strings have same match lengths
    // Dynamic weight should be predictable
    const u = atom_mod.upper();
    const d = atom_mod.digit();
    const l = atom_mod.lower();
    const pattern = [_]Atom{ u, d, l };

    // All strings: 1 upper + 2 digits + 3 lowers = 6 chars total
    const strings = [_][]const u8{ "A12abc", "B34def", "C56ghi", "D78jkl" };

    const cost = try calculateCost(&pattern, &strings, allocator);
    try testing.expect(cost == .finite);
    try testing.expect(cost.finite > 0.0);

    // Check dynamic weights
    const weight0 = try dynamicWeight(0, &pattern, &strings, allocator);
    const weight1 = try dynamicWeight(1, &pattern, &strings, allocator);
    const weight2 = try dynamicWeight(2, &pattern, &strings, allocator);

    // Upper matches 1/6, Digit matches 2/6, Lower matches 3/6
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 6.0), weight0, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.0 / 6.0), weight1, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 3.0 / 6.0), weight2, 0.001);

    // Sum of dynamic weights should equal 1.0
    const sum = weight0 + weight1 + weight2;
    try testing.expectApproxEqAbs(@as(f64, 1.0), sum, 0.001);
}
