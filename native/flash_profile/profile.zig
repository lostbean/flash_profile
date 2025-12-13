const std = @import("std");
const Allocator = std.mem.Allocator;
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const learner_mod = @import("learner.zig");
const cost_mod = @import("cost.zig");
const pattern_mod = @import("pattern.zig");
const hierarchy_mod = @import("hierarchy.zig");
const dissimilarity_mod = @import("dissimilarity.zig");
const compress_mod = @import("compress.zig");
const types = @import("types.zig");
const Cost = types.Cost;

/// Entry in the profile result mapping patterns to example data.
pub const ProfileEntry = struct {
    /// The pattern atoms that describe this cluster
    pattern: []const Atom,

    /// Cost of this pattern
    cost: f64,

    /// Indices into the original string array that match this pattern
    data_indices: []usize,

    allocator: Allocator,

    pub fn deinit(self: *ProfileEntry) void {
        self.allocator.free(self.pattern);
        self.allocator.free(self.data_indices);
    }
};

/// Result of profiling operation containing all pattern clusters
pub const ProfileResult = struct {
    entries: []ProfileEntry,
    allocator: Allocator,

    pub fn deinit(self: *ProfileResult) void {
        for (self.entries) |*entry| {
            entry.deinit();
        }
        self.allocator.free(self.entries);
    }
};

/// Options for profiling algorithms
pub const ProfileOptions = struct {
    /// Minimum number of patterns to extract (m)
    min_patterns: usize = 1,

    /// Maximum number of patterns to extract (M)
    max_patterns: usize = 10,

    /// Threshold multiplier for hierarchy building (θ)
    /// When |S| > θ·M, use approximate dissimilarity matrix
    theta: f64 = 1.25,

    /// Sampling multiplier for BigProfile (µ)
    /// Sample size = µ * M
    mu: f64 = 4.0,

    /// Sample size for dissimilarity matrix approximation (M̂)
    m_hat: usize = 100,

    /// Maximum iterations for BigProfile
    max_iterations: usize = 100,
};

/// Profile algorithm from the FlashProfile paper (Figure 7)
///
/// Profile(S, m, M, θ):
///   H ← BuildHierarchy(S, M, θ)
///   C ← Partition(H, m)
///   P ← {LearnBestPattern(c) : c ∈ C}
///   if |P| > M:
///     CompressProfile(P, M)
///   return P
///
/// Parameters:
/// - strings: Input strings to profile
/// - atoms: Atoms to use for pattern synthesis
/// - options: Profiling options
/// - allocator: Memory allocator
///
/// Returns ProfileResult with patterns and their associated data indices
pub fn profile(
    strings: []const []const u8,
    atoms: []const Atom,
    options: ProfileOptions,
    allocator: Allocator,
) !ProfileResult {
    // Edge case: empty dataset
    if (strings.len == 0) {
        const entries = try allocator.alloc(ProfileEntry, 0);
        return ProfileResult{
            .entries = entries,
            .allocator = allocator,
        };
    }

    // Build hierarchy using dissimilarity matrix
    var hierarchy = try buildHierarchy(strings, atoms, options, allocator);
    defer hierarchy.deinit();

    // Partition hierarchy into clusters
    // Use max_patterns as the initial cluster count to discover natural clusters
    // The algorithm will then learn patterns and compress if needed
    const k = @min(options.max_patterns, strings.len);
    var partition_result = try hierarchy_mod.partition(&hierarchy, k, allocator);
    defer partition_result.deinit();

    // Learn best pattern for each cluster
    var entries: std.ArrayList(ProfileEntry) = .{};
    defer entries.deinit(allocator);

    for (partition_result.clusters) |cluster| {
        // Get strings for this cluster
        const cluster_strings = try allocator.alloc([]const u8, cluster.len);
        defer allocator.free(cluster_strings);

        for (cluster, 0..) |idx, i| {
            cluster_strings[i] = strings[idx];
        }

        // Learn best pattern (no cache for cluster-level learning)
        const learn_result = try learner_mod.learnBestPattern(cluster_strings, atoms, null, allocator);

        if (learn_result) |result| {
            defer {
                var mut_result = result;
                mut_result.deinit();
            }

            // Copy pattern
            const pattern = try allocator.dupe(Atom, result.pattern);

            // Copy indices
            const indices = try allocator.dupe(usize, cluster);

            try entries.append(allocator, .{
                .pattern = pattern,
                .cost = result.cost,
                .data_indices = indices,
                .allocator = allocator,
            });
        } else {
            // Pattern learning failed - create entry with empty pattern and infinity cost
            const pattern = try allocator.alloc(Atom, 0);
            const indices = try allocator.dupe(usize, cluster);

            try entries.append(allocator, .{
                .pattern = pattern,
                .cost = std.math.inf(f64),
                .data_indices = indices,
                .allocator = allocator,
            });
        }
    }

    const learned_entries = try entries.toOwnedSlice(allocator);

    // If we have too many patterns, compress to max_patterns (per paper's Figure 7)
    if (learned_entries.len > options.max_patterns) {
        const compressed_result = try compress_mod.compressProfile(
            learned_entries,
            options.max_patterns,
            strings,
            atoms,
            allocator,
        );

        // Free the uncompressed entries
        for (learned_entries) |*entry| {
            entry.deinit();
        }
        allocator.free(learned_entries);

        return compressed_result;
    }

    return ProfileResult{
        .entries = learned_entries,
        .allocator = allocator,
    };
}

/// BigProfile algorithm for large datasets (Figure 11)
///
/// BigProfile(S, m, M, M̂, θ, µ):
///   S̃ ← S
///   P̃ ← ∅
///   while |S̃| > 0 and |P̃| < M:
///     Ŝ ← Sample(S̃, µ)
///     P ← Profile(Ŝ, m, M, θ)
///     P̃ ← P̃ ∪ P
///     S̃ ← Filter(S̃, P)
///   return P̃
///
/// Parameters:
/// - strings: Input strings to profile
/// - atoms: Atoms to use for pattern synthesis
/// - options: Profiling options
/// - allocator: Memory allocator
///
/// Returns ProfileResult with patterns learned across multiple sampling iterations
pub fn bigProfile(
    strings: []const []const u8,
    atoms: []const Atom,
    options: ProfileOptions,
    allocator: Allocator,
) !ProfileResult {
    // Edge case: empty dataset
    if (strings.len == 0) {
        const entries = try allocator.alloc(ProfileEntry, 0);
        return ProfileResult{
            .entries = entries,
            .allocator = allocator,
        };
    }

    // Calculate sample size: ⌈µ·M⌉ (ceiling as per paper)
    const sample_size = @as(usize, @intFromFloat(@ceil(options.mu * @as(f64, @floatFromInt(options.max_patterns)))));

    // If dataset is small enough, use regular Profile
    if (strings.len <= sample_size) {
        return try profile(strings, atoms, options, allocator);
    }

    // Initialize working set (copy of strings)
    var remaining_strings: std.ArrayList([]const u8) = .{};
    defer remaining_strings.deinit(allocator);
    try remaining_strings.appendSlice(allocator, strings);

    // Accumulated profile entries
    var all_entries: std.ArrayList(ProfileEntry) = .{};
    defer all_entries.deinit(allocator);

    var iteration: usize = 0;

    while (remaining_strings.items.len > 0 and
        all_entries.items.len < options.max_patterns and
        iteration < options.max_iterations) : (iteration += 1)
    {

        // Sample strings
        const sample = try sampleStrings(remaining_strings.items, sample_size, allocator);
        defer allocator.free(sample);

        // Profile the sample
        var sample_profile = try profile(sample, atoms, options, allocator);
        defer sample_profile.deinit();

        // Map sample indices back to original string set
        for (sample_profile.entries) |*entry| {
            // Find original indices
            const original_indices = try allocator.alloc(usize, entry.data_indices.len);

            for (entry.data_indices, 0..) |sample_idx, i| {
                const sample_string = sample[sample_idx];
                // Find this string in remaining_strings
                for (remaining_strings.items) |remaining_str| {
                    if (std.mem.eql(u8, sample_string, remaining_str)) {
                        // Find this string's index in original strings array
                        for (strings, 0..) |orig_str, k| {
                            if (std.mem.eql(u8, remaining_str, orig_str)) {
                                original_indices[i] = k;
                                break;
                            }
                        }
                        break;
                    }
                }
            }

            // Add to accumulated entries with copied pattern and remapped indices
            const pattern_copy = try allocator.dupe(Atom, entry.pattern);

            try all_entries.append(allocator, .{
                .pattern = pattern_copy,
                .cost = entry.cost,
                .data_indices = original_indices,
                .allocator = allocator,
            });
        }

        // Filter out strings covered by this profile
        const patterns = try allocator.alloc([]const Atom, sample_profile.entries.len);
        defer allocator.free(patterns);

        for (sample_profile.entries, 0..) |entry, i| {
            patterns[i] = entry.pattern;
        }

        const filtered = try filterStrings(remaining_strings.items, patterns, allocator);
        defer allocator.free(filtered);

        // Update remaining strings
        remaining_strings.clearRetainingCapacity();
        try remaining_strings.appendSlice(allocator, filtered);

        // Break if no progress made
        if (filtered.len == remaining_strings.items.len) {
            break;
        }
    }

    // Compress if we have too many patterns
    if (all_entries.items.len > options.max_patterns) {
        const compressed = try compressProfile(all_entries.items, strings, options.max_patterns, allocator);

        // Free the excess entries
        for (all_entries.items) |*entry| {
            entry.deinit();
        }

        // Replace with compressed
        return ProfileResult{
            .entries = compressed,
            .allocator = allocator,
        };
    }

    return ProfileResult{
        .entries = try all_entries.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Build hierarchy using agglomerative hierarchical clustering (Figure 12)
///
/// BuildHierarchy(S, M, θ):
///   if |S| ≤ θ·M:
///     return AHC(S, η)
///   else:
///     Samples ← SampleDissimilarities(S, M̂)
///     Matrix ← ApproxDMatrix(S, Samples)
///     return AHC(S, Matrix)
fn buildHierarchy(
    strings: []const []const u8,
    atoms: []const Atom,
    options: ProfileOptions,
    allocator: Allocator,
) !hierarchy_mod.Hierarchy {
    // OPTIMIZATION: Check for homogeneous data FIRST before any dissimilarity computation
    // This optimization applies to both small and large datasets
    // For homogeneous data (all strings match the same pattern), we can skip O(n²)
    // dissimilarity computations and just use a uniform value
    if (strings.len >= 3) {
        const homogeneity_result = try checkHomogeneity(strings, atoms, allocator);
        if (homogeneity_result.is_homogeneous) {
            // All strings match the same pattern!
            // Build matrix with uniform dissimilarity (fast path - O(n²) memory ops only)
            // No expensive pattern learning required for each pair

            var matrix = try hierarchy_mod.DissimilarityMatrix.init(strings, allocator);
            defer matrix.deinit();

            for (0..strings.len) |i| {
                for (i + 1..strings.len) |j| {
                    const diss_value = hierarchy_mod.Dissimilarity{ .finite = homogeneity_result.uniform_dissim };
                    try matrix.set(i, j, diss_value);
                }
            }
            return try hierarchy_mod.ahc(&matrix, allocator);
        }
    }

    // Compute threshold: ⌈θ·M⌉ (ceiling as per paper)
    const threshold = @as(usize, @intFromFloat(@ceil(options.theta * @as(f64, @floatFromInt(options.max_patterns)))));

    // Build dissimilarity matrix for hierarchy module
    var matrix = try hierarchy_mod.DissimilarityMatrix.init(strings, allocator);
    defer matrix.deinit();

    // OPTIMIZATION: Create persistent pattern cache for this hierarchy build
    var pattern_cache = learner_mod.PatternCache.init(allocator);
    defer pattern_cache.deinit();

    if (strings.len <= threshold) {

        // Full AHC - compute all pairwise dissimilarities
        for (0..strings.len) |i| {
            for (i + 1..strings.len) |j| {
                const diss = try dissimilarity_mod.computeDissimilarity(
                    strings[i],
                    strings[j],
                    atoms,
                    &pattern_cache,
                    allocator,
                );

                const diss_value = if (std.math.isInf(diss))
                    hierarchy_mod.Dissimilarity.infinity
                else
                    hierarchy_mod.Dissimilarity{ .finite = diss };

                try matrix.set(i, j, diss_value);
            }
        }
    } else {
        // Use sampling and approximation for large datasets
        // M̂ = ⌈θ·M⌉
        const m_hat = threshold;
        const sample_result = try dissimilarity_mod.sampleDissimilarities(strings, m_hat, atoms, &pattern_cache, allocator);
        defer {
            var mut_sample = sample_result;
            mut_sample.deinit();
        }

        var approx_matrix = try dissimilarity_mod.buildApproxMatrix(strings, sample_result, atoms, &pattern_cache, allocator);
        defer approx_matrix.deinit();

        // Copy approximated dissimilarities into hierarchy matrix
        for (0..strings.len) |i| {
            for (i + 1..strings.len) |j| {
                const diss = approx_matrix.get(i, j);

                const diss_value = if (std.math.isInf(diss))
                    hierarchy_mod.Dissimilarity.infinity
                else
                    hierarchy_mod.Dissimilarity{ .finite = diss };

                try matrix.set(i, j, diss_value);
            }
        }
    }

    // Use agglomerative hierarchical clustering
    return try hierarchy_mod.ahc(&matrix, allocator);
}

/// Filter strings not covered by any pattern
///
/// Returns strings that don't match any of the given patterns
pub fn filterStrings(
    strings: []const []const u8,
    patterns: []const []const Atom,
    allocator: Allocator,
) ![][]const u8 {
    var filtered: std.ArrayList([]const u8) = .{};
    defer filtered.deinit(allocator);

    for (strings) |string| {
        var matched = false;

        for (patterns) |pattern| {
            const pat = pattern_mod.Pattern.init(pattern);
            if (pat.matches(string)) {
                matched = true;
                break;
            }
        }

        if (!matched) {
            try filtered.append(allocator, string);
        }
    }

    return filtered.toOwnedSlice(allocator);
}

/// Sample strings randomly
///
/// Sample size = min(count, strings.len)
/// Uses Fisher-Yates shuffle for unbiased sampling
pub fn sampleStrings(
    strings: []const []const u8,
    count: usize,
    allocator: Allocator,
) ![][]const u8 {
    if (strings.len == 0) {
        return try allocator.alloc([]const u8, 0);
    }

    const sample_size = @min(count, strings.len);

    // Create indices array
    const indices = try allocator.alloc(usize, strings.len);
    defer allocator.free(indices);

    for (indices, 0..) |*idx, i| {
        idx.* = i;
    }

    // Fisher-Yates shuffle for first sample_size elements
    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
    const random = rng.random();

    for (0..sample_size) |i| {
        const j = random.intRangeLessThan(usize, i, strings.len);
        const tmp = indices[i];
        indices[i] = indices[j];
        indices[j] = tmp;
    }

    // Build result array
    const result = try allocator.alloc([]const u8, sample_size);
    for (0..sample_size) |i| {
        result[i] = strings[indices[i]];
    }

    return result;
}

/// Compress profile to max_patterns by merging similar entries
///
/// Uses greedy merging: repeatedly merge the two entries with lowest combined cost
fn compressProfile(
    entries: []ProfileEntry,
    strings: []const []const u8,
    max_patterns: usize,
    allocator: Allocator,
) ![]ProfileEntry {
    _ = strings;

    if (entries.len <= max_patterns) {
        // No compression needed - return copy
        const result = try allocator.alloc(ProfileEntry, entries.len);
        for (entries, 0..) |entry, i| {
            const pattern = try allocator.dupe(Atom, entry.pattern);
            const indices = try allocator.dupe(usize, entry.data_indices);
            result[i] = .{
                .pattern = pattern,
                .cost = entry.cost,
                .data_indices = indices,
                .allocator = allocator,
            };
        }
        return result;
    }

    // Simple compression: keep entries with lowest cost
    // Create working copy with indices
    const EntryWithIdx = struct {
        entry: *const ProfileEntry,
        original_idx: usize,
    };

    var sorted = try allocator.alloc(EntryWithIdx, entries.len);
    defer allocator.free(sorted);

    for (entries, 0..) |*entry, i| {
        sorted[i] = .{ .entry = entry, .original_idx = i };
    }

    // Sort by cost (ascending)
    std.sort.heap(EntryWithIdx, sorted, {}, struct {
        fn lessThan(_: void, a: EntryWithIdx, b: EntryWithIdx) bool {
            return a.entry.cost < b.entry.cost;
        }
    }.lessThan);

    // Take top max_patterns entries
    const result = try allocator.alloc(ProfileEntry, max_patterns);
    for (0..max_patterns) |i| {
        const entry = sorted[i].entry;
        const pattern = try allocator.dupe(Atom, entry.pattern);
        const indices = try allocator.dupe(usize, entry.data_indices);

        result[i] = .{
            .pattern = pattern,
            .cost = entry.cost,
            .data_indices = indices,
            .allocator = allocator,
        };
    }

    return result;
}

/// Result of homogeneity check
const HomogeneityResult = struct {
    is_homogeneous: bool,
    uniform_dissim: f64,
};

/// Check if dataset is homogeneous (all strings match the same pattern)
///
/// OPTIMIZATION: For homogeneous data, we can skip most dissimilarity computations
/// since all pairs will have the same dissimilarity value.
///
/// Algorithm:
/// 1. Sample a few pairs and learn their patterns
/// 2. Check if all costs are similar (within 1% tolerance)
/// 3. Verify the pattern matches ALL strings in the dataset
/// 4. If yes, return the uniform dissimilarity value
fn checkHomogeneity(
    strings: []const []const u8,
    atoms: []const Atom,
    allocator: Allocator,
) !HomogeneityResult {
    // Sample a few pairs (up to 5)
    const sample_count = @min(5, strings.len);
    var costs: [10]f64 = undefined; // Max 10 pairs from 5 strings
    var patterns: [10]?[]const Atom = .{null} ** 10;
    defer {
        for (patterns) |p| {
            if (p) |atoms_slice| {
                allocator.free(atoms_slice);
            }
        }
    }

    var pair_idx: usize = 0;

    // Learn patterns for first few pairs
    for (0..sample_count) |i| {
        for (i + 1..sample_count) |j| {
            if (pair_idx >= 10) break;

            const result = try dissimilarity_mod.computeDissimilarityWithPattern(
                strings[i],
                strings[j],
                atoms,
                null, // No cache needed for sampling
                allocator,
            );

            costs[pair_idx] = result.cost;
            patterns[pair_idx] = result.pattern;
            pair_idx += 1;
        }
    }

    // Need at least 2 pairs to check homogeneity
    if (pair_idx < 2) {
        return HomogeneityResult{ .is_homogeneous = false, .uniform_dissim = 0 };
    }

    // Check if all costs are similar (within 1% tolerance)
    const first_cost = costs[0];

    // Skip if cost is infinite
    if (std.math.isInf(first_cost)) {
        return HomogeneityResult{ .is_homogeneous = false, .uniform_dissim = 0 };
    }

    var all_similar = true;
    for (costs[1..pair_idx]) |c| {
        // Use absolute difference for small costs, relative for large
        const tolerance = if (first_cost < 1.0) 0.01 else first_cost * 0.01;
        if (@abs(c - first_cost) > tolerance) {
            all_similar = false;
            break;
        }
    }

    if (!all_similar or patterns[0] == null) {
        return HomogeneityResult{ .is_homogeneous = false, .uniform_dissim = 0 };
    }

    // Verify the pattern matches ALL strings
    // Since we learned the pattern from a pair of strings, it should match both.
    // But we need to check if it generalizes to ALL strings in the dataset.
    const pattern = pattern_mod.Pattern.init(patterns[0].?);
    for (strings) |s| {
        if (!pattern.matches(s)) {
            // Pattern doesn't generalize to all strings
            return HomogeneityResult{ .is_homogeneous = false, .uniform_dissim = 0 };
        }
    }

    // All strings match the same pattern!
    // This means the dataset is homogeneous and all pairs will have similar dissimilarity
    return HomogeneityResult{ .is_homogeneous = true, .uniform_dissim = first_cost };
}

// ============================================================================
// Tests
// ============================================================================

test "profile: empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{};
    const atoms = [_]Atom{};
    const options = ProfileOptions{};

    var result = try profile(&strings, &atoms, options, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 0), result.entries.len);
}

test "profile: small dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "PMC123", "PMC456", "PMC789" };
    const pmc = atom_mod.constant("PMC", "PMC");
    const digit = atom_mod.digit();
    const atoms = [_]Atom{ pmc, digit };

    const options = ProfileOptions{ .max_patterns = 5 };

    var result = try profile(&strings, &atoms, options, allocator);
    defer result.deinit();

    try testing.expect(result.entries.len >= 1);
    try testing.expect(result.entries.len <= options.max_patterns);

    // Check that all strings are covered
    var total_covered: usize = 0;
    for (result.entries) |entry| {
        total_covered += entry.data_indices.len;
    }
    try testing.expectEqual(strings.len, total_covered);
}

test "profile: pattern coverage verification" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "ABC", "DEF", "GHI" };
    const upper = atom_mod.upper();
    const atoms = [_]Atom{upper};

    const options = ProfileOptions{ .max_patterns = 3 };

    var result = try profile(&strings, &atoms, options, allocator);
    defer result.deinit();

    // Each pattern should match its associated data
    for (result.entries) |entry| {
        const pat = pattern_mod.Pattern.init(entry.pattern);

        for (entry.data_indices) |idx| {
            const string = strings[idx];
            try testing.expect(pat.matches(string));
        }
    }
}

test "filterStrings: basic filtering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "123", "456", "abc", "def" };
    const digit = atom_mod.digit();
    const pattern1 = [_]Atom{digit};
    const patterns = [_][]const Atom{&pattern1};

    const filtered = try filterStrings(&strings, &patterns, allocator);
    defer allocator.free(filtered);

    // Should only keep non-digit strings
    try testing.expectEqual(@as(usize, 2), filtered.len);
    try testing.expect(std.mem.eql(u8, "abc", filtered[0]) or std.mem.eql(u8, "def", filtered[0]));
}

test "filterStrings: all strings match" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "123", "456", "789" };
    const digit = atom_mod.digit();
    const pattern1 = [_]Atom{digit};
    const patterns = [_][]const Atom{&pattern1};

    const filtered = try filterStrings(&strings, &patterns, allocator);
    defer allocator.free(filtered);

    try testing.expectEqual(@as(usize, 0), filtered.len);
}

test "filterStrings: no patterns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def" };
    const patterns = [_][]const Atom{};

    const filtered = try filterStrings(&strings, &patterns, allocator);
    defer allocator.free(filtered);

    try testing.expectEqual(strings.len, filtered.len);
}

test "sampleStrings: sample smaller than dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "a", "b", "c", "d", "e" };
    const sample = try sampleStrings(&strings, 3, allocator);
    defer allocator.free(sample);

    try testing.expectEqual(@as(usize, 3), sample.len);

    // All sampled strings should be from original
    for (sample) |s| {
        var found = false;
        for (strings) |orig| {
            if (std.mem.eql(u8, s, orig)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "sampleStrings: sample larger than dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "a", "b", "c" };
    const sample = try sampleStrings(&strings, 10, allocator);
    defer allocator.free(sample);

    // Should return all strings
    try testing.expectEqual(strings.len, sample.len);
}

test "sampleStrings: empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{};
    const sample = try sampleStrings(&strings, 5, allocator);
    defer allocator.free(sample);

    try testing.expectEqual(@as(usize, 0), sample.len);
}

test "bigProfile: small dataset (uses Profile)" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "PMC1", "PMC2", "PMC3" };
    const pmc = atom_mod.constant("PMC", "PMC");
    const digit = atom_mod.digit();
    const atoms = [_]Atom{ pmc, digit };

    const options = ProfileOptions{
        .max_patterns = 5,
        .mu = 4.0,
    };

    var result = try bigProfile(&strings, &atoms, options, allocator);
    defer result.deinit();

    try testing.expect(result.entries.len >= 1);
    try testing.expect(result.entries.len <= options.max_patterns);
}

test "bigProfile: respects max_patterns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create diverse dataset
    var strings_list: std.ArrayList([]const u8) = .{};
    defer strings_list.deinit(allocator);

    try strings_list.append(allocator, "PMC1");
    try strings_list.append(allocator, "PMC2");
    try strings_list.append(allocator, "ABC");
    try strings_list.append(allocator, "DEF");
    try strings_list.append(allocator, "123");
    try strings_list.append(allocator, "456");

    const digit = atom_mod.digit();
    const upper = atom_mod.upper();
    const pmc = atom_mod.constant("PMC", "PMC");
    const atoms = [_]Atom{ pmc, digit, upper };

    const max_patterns = 2;
    const options = ProfileOptions{
        .max_patterns = max_patterns,
        .mu = 2.0,
    };

    var result = try bigProfile(strings_list.items, &atoms, options, allocator);
    defer result.deinit();

    try testing.expect(result.entries.len <= max_patterns);
}

test "bigProfile: empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{};
    const atoms = [_]Atom{};
    const options = ProfileOptions{};

    var result = try bigProfile(&strings, &atoms, options, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 0), result.entries.len);
}

test "compressProfile: no compression needed" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "a", "b" };

    // Create entries
    const idx0 = try allocator.dupe(usize, &[_]usize{0});
    defer allocator.free(idx0);
    const idx1 = try allocator.dupe(usize, &[_]usize{1});
    defer allocator.free(idx1);

    var entries = [_]ProfileEntry{
        .{
            .pattern = &[_]Atom{},
            .cost = 1.0,
            .data_indices = idx0,
            .allocator = allocator,
        },
        .{
            .pattern = &[_]Atom{},
            .cost = 2.0,
            .data_indices = idx1,
            .allocator = allocator,
        },
    };

    const compressed = try compressProfile(&entries, &strings, 5, allocator);
    defer {
        for (compressed) |*entry| {
            entry.deinit();
        }
        allocator.free(compressed);
    }

    try testing.expectEqual(@as(usize, 2), compressed.len);
}

test "compressProfile: compression needed" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "a", "b", "c", "d" };

    // Create entries with different costs
    const idx0 = try allocator.dupe(usize, &[_]usize{0});
    defer allocator.free(idx0);
    const idx1 = try allocator.dupe(usize, &[_]usize{1});
    defer allocator.free(idx1);
    const idx2 = try allocator.dupe(usize, &[_]usize{2});
    defer allocator.free(idx2);
    const idx3 = try allocator.dupe(usize, &[_]usize{3});
    defer allocator.free(idx3);

    var entries = [_]ProfileEntry{
        .{
            .pattern = &[_]Atom{},
            .cost = 1.0,
            .data_indices = idx0,
            .allocator = allocator,
        },
        .{
            .pattern = &[_]Atom{},
            .cost = 5.0,
            .data_indices = idx1,
            .allocator = allocator,
        },
        .{
            .pattern = &[_]Atom{},
            .cost = 2.0,
            .data_indices = idx2,
            .allocator = allocator,
        },
        .{
            .pattern = &[_]Atom{},
            .cost = 4.0,
            .data_indices = idx3,
            .allocator = allocator,
        },
    };

    const compressed = try compressProfile(&entries, &strings, 2, allocator);
    defer {
        for (compressed) |*entry| {
            entry.deinit();
        }
        allocator.free(compressed);
    }

    // Should keep 2 entries with lowest cost
    try testing.expectEqual(@as(usize, 2), compressed.len);
    try testing.expectEqual(@as(f64, 1.0), compressed[0].cost);
    try testing.expectEqual(@as(f64, 2.0), compressed[1].cost);
}

test "checkHomogeneity: homogeneous phone numbers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // All phone numbers have the same format
    const strings = [_][]const u8{
        "555-001-1234",
        "555-002-1234",
        "555-003-1234",
        "555-004-1234",
        "555-005-1234",
    };

    // Use full default atom set
    const atoms = [_]Atom{
        atom_mod.lower(),
        atom_mod.upper(),
        atom_mod.digit(),
        atom_mod.bin(),
        atom_mod.hex(),
        atom_mod.alpha(),
        atom_mod.alphaDigit(),
        atom_mod.space(),
        atom_mod.alphaDigitSpace(),
        atom_mod.dotDash(),
        atom_mod.punct(),
        atom_mod.alphaDash(),
        atom_mod.symb(),
        atom_mod.alphaSpace(),
        atom_mod.base64(),
        atom_mod.any(),
    };

    const result = try checkHomogeneity(&strings, &atoms, allocator);

    // Should detect homogeneity
    try testing.expect(result.is_homogeneous);
    try testing.expect(result.uniform_dissim >= 0.0);
    try testing.expect(!std.math.isInf(result.uniform_dissim));
}

test "checkHomogeneity: heterogeneous data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Mixed data with different patterns
    const strings = [_][]const u8{
        "555-001-1234",
        "user@example.com",
        "2023-01-15",
        "PMC1234567",
    };

    const digit = atom_mod.digit();
    const upper = atom_mod.upper();
    const atoms = [_]Atom{ digit, upper };

    const result = try checkHomogeneity(&strings, &atoms, allocator);

    // Should NOT detect homogeneity
    try testing.expect(!result.is_homogeneous);
}

test "checkHomogeneity: too few strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{"123"};
    const digit = atom_mod.digit();
    const atoms = [_]Atom{digit};

    const result = try checkHomogeneity(&strings, &atoms, allocator);

    // Should not detect homogeneity with too few strings
    try testing.expect(!result.is_homogeneous);
}
