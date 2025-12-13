//! Dissimilarity computation for FlashProfile hierarchical clustering.
//!
//! This module implements dissimilarity computation between strings based on
//! pattern cost, as described in the FlashProfile paper (Section 5).
//!
//! ## Key Algorithm
//!
//! From the paper:
//! - η(x, y) = C(P*, {x, y}) where P* is the best pattern for {x, y}
//! - Dissimilarity is the cost of the minimum-cost pattern that describes both strings
//! - Used for hierarchical clustering in the PROFILE algorithm
//!
//! ## Main Functions
//!
//! - `computeDissimilarity`: Compute η(x, y) for two strings
//! - `sampleDissimilarities`: Sample representative strings (Figure 8)
//! - `buildApproxMatrix`: Build approximate dissimilarity matrix (Figure 9)
//!
//! ## Matrix Storage
//!
//! Dissimilarity matrices use upper-triangle storage for efficiency:
//! - Only stores i < j pairs (symmetric matrix)
//! - Row-major indexing
//! - O(1) access time

const std = @import("std");
const Allocator = std.mem.Allocator;
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const learner_mod = @import("learner.zig");
const pattern_mod = @import("pattern.zig");
const cost_mod = @import("cost.zig");
const types = @import("types.zig");
const Cost = types.Cost;

/// Dissimilarity matrix stored in upper-triangle format.
///
/// From the FlashProfile paper (Figure 8-9):
/// Dissimilarity η(x, y) = C(P*, {x, y}) where P* is the best pattern for {x, y}.
///
/// Storage format:
/// - Only stores upper triangle (i < j)
/// - Row-major order
/// - Index calculation: index(i, j) = i*n + j - (i+1)*(i+2)/2
pub const DissimilarityMatrix = struct {
    /// Number of strings
    n: usize,
    /// Upper triangle storage (row-major)
    values: []f64,
    allocator: Allocator,

    /// Create a new dissimilarity matrix for n strings.
    pub fn init(n: usize, allocator: Allocator) !DissimilarityMatrix {
        // Size of upper triangle: n*(n-1)/2
        const size = (n * (n - 1)) / 2;
        const values = try allocator.alloc(f64, size);

        // Initialize with zeros
        @memset(values, 0.0);

        return DissimilarityMatrix{
            .n = n,
            .values = values,
            .allocator = allocator,
        };
    }

    /// Get dissimilarity value at position (i, j).
    /// Requires i < j (upper triangle).
    pub fn get(self: DissimilarityMatrix, i: usize, j: usize) f64 {
        std.debug.assert(i < j);
        std.debug.assert(j < self.n);

        const idx = self.getIndex(i, j);
        return self.values[idx];
    }

    /// Set dissimilarity value at position (i, j).
    /// Requires i < j (upper triangle).
    pub fn set(self: *DissimilarityMatrix, i: usize, j: usize, value: f64) void {
        std.debug.assert(i < j);
        std.debug.assert(j < self.n);

        const idx = self.getIndex(i, j);
        self.values[idx] = value;
    }

    /// Calculate index into upper triangle storage.
    /// For i < j: index = i*n + j - (i+1)*(i+2)/2
    fn getIndex(self: DissimilarityMatrix, i: usize, j: usize) usize {
        // Number of elements before row i: i*n - (0+1+...+i) = i*n - i*(i+1)/2
        // Plus column offset: j - (i+1)
        const row_offset = i * self.n - (i * (i + 1)) / 2;
        const col_offset = j - (i + 1);
        return row_offset + col_offset;
    }

    /// Free the matrix.
    pub fn deinit(self: *DissimilarityMatrix) void {
        self.allocator.free(self.values);
    }
};

/// Cached pattern from dissimilarity computation
pub const CachedPattern = struct {
    atoms: []const Atom,
    cost: f64,
};

/// Result of sample dissimilarities computation.
pub const SampleResult = struct {
    /// Indices of sampled strings
    indices: []usize,
    /// Pairwise dissimilarities for samples
    matrix: DissimilarityMatrix,
    /// Cached patterns learned during sampling (for reuse in buildApproxMatrix)
    patterns: std.ArrayList(CachedPattern),
    allocator: Allocator,

    /// Free the sample result.
    pub fn deinit(self: *SampleResult) void {
        self.allocator.free(self.indices);
        self.matrix.deinit();
        // Free pattern atoms
        for (self.patterns.items) |pattern| {
            self.allocator.free(pattern.atoms);
        }
        self.patterns.deinit(self.allocator);
    }
};

/// Compute dissimilarity between two strings.
///
/// From the paper (Section 5):
/// η(x, y) = C(P*, {x, y}) where P* is the best pattern for {x, y}
///
/// Returns:
/// - 0.0 if strings are identical (per Definition 3.1)
/// - The cost of the minimum-cost pattern that describes both strings
/// - Infinity if no pattern can describe both strings
pub fn computeDissimilarity(
    s1: []const u8,
    s2: []const u8,
    atoms: []const Atom,
    allocator: Allocator,
) !f64 {
    const result = try computeDissimilarityWithPattern(s1, s2, atoms, allocator);
    if (result.pattern) |p| {
        allocator.free(p);
    }
    return result.cost;
}

/// Result of dissimilarity computation including the learned pattern
pub const DissimilarityResult = struct {
    cost: f64,
    pattern: ?[]const Atom, // null if no pattern (infinity cost)
};

/// Compute dissimilarity and return the learned pattern.
///
/// This is used when we want to cache patterns for reuse.
pub fn computeDissimilarityWithPattern(
    s1: []const u8,
    s2: []const u8,
    atoms: []const Atom,
    allocator: Allocator,
) !DissimilarityResult {
    // Optimization: identical strings have zero dissimilarity
    if (std.mem.eql(u8, s1, s2)) {
        return DissimilarityResult{ .cost = 0.0, .pattern = null };
    }

    const strings = [_][]const u8{ s1, s2 };

    const result = try learner_mod.learnBestPattern(&strings, atoms, allocator);

    if (result) |r| {
        // Return the pattern without deinit - caller takes ownership
        return DissimilarityResult{ .cost = r.cost, .pattern = r.pattern };
    } else {
        // No pattern found - return infinity
        return DissimilarityResult{ .cost = std.math.inf(f64), .pattern = null };
    }
}

/// Try to compute dissimilarity using cached patterns first.
///
/// OPTIMIZATION: Check if any cached pattern matches both strings before
/// doing full pattern learning. Pattern matching + cost calculation is
/// much faster than learning a new pattern.
fn computeDissimilarityWithCache(
    s1: []const u8,
    s2: []const u8,
    cached_patterns: []const CachedPattern,
    atoms: []const Atom,
    allocator: Allocator,
) !DissimilarityResult {
    // Fast path: identical strings
    if (std.mem.eql(u8, s1, s2)) {
        return DissimilarityResult{ .cost = 0.0, .pattern = null };
    }

    // Try cached patterns first - this is O(patterns) matching instead of O(pattern_learning)
    var best_cost: f64 = std.math.inf(f64);
    var best_pattern: ?[]const Atom = null;

    for (cached_patterns) |cached| {
        const pattern = pattern_mod.Pattern.init(cached.atoms);

        // Check if pattern matches both strings
        if (pattern.matches(s1) and pattern.matches(s2)) {
            // Pattern matches! Calculate cost for this specific pair
            const strings = [_][]const u8{ s1, s2 };
            const cost = try cost_mod.calculateCost(cached.atoms, &strings, allocator);

            if (cost == .finite and cost.finite < best_cost) {
                best_cost = cost.finite;
                best_pattern = cached.atoms;
            }
        }
    }

    // If a cached pattern worked, return it (don't duplicate atoms - just reference)
    if (best_cost < std.math.inf(f64)) {
        // Copy the pattern atoms since caller may need to own them
        const pattern_copy = try allocator.dupe(Atom, best_pattern.?);
        return DissimilarityResult{ .cost = best_cost, .pattern = pattern_copy };
    }

    // No cached pattern worked, do full pattern learning
    return computeDissimilarityWithPattern(s1, s2, atoms, allocator);
}

/// Sample dissimilarities from a dataset.
///
/// Implements the SampleDissimilarities algorithm from Figure 8 of the paper:
///
/// ```
/// func SampleDissimilarities(S: String[], M̂: Int)
///   Seeds ← {}
///   for i = 1 to M̂ do
///     x ← argmax_{s∈S\Seeds} min_{t∈Seeds} η(s, t)  // Most dissimilar to chosen set
///     Seeds ← Seeds ∪ {x}
///   return Seeds with pairwise dissimilarities
/// ```
///
/// Adaptive seed selection: picks strings that are most dissimilar from the
/// already chosen set to maximize diversity.
///
/// Parameters:
/// - strings: List of all strings
/// - M_hat: Number of samples to select (must be <= strings.len)
/// - atoms: List of atoms for pattern learning
/// - allocator: Memory allocator
///
/// Returns:
/// - SampleResult with sampled indices and their pairwise dissimilarity matrix
pub fn sampleDissimilarities(
    strings: []const []const u8,
    M_hat: usize,
    atoms: []const Atom,
    allocator: Allocator,
) !SampleResult {
    const n = strings.len;
    const m = if (M_hat > n) n else M_hat;

    var indices = try allocator.alloc(usize, m);
    errdefer allocator.free(indices);

    // Edge case: if m == 0, return empty result
    if (m == 0) {
        const matrix = try DissimilarityMatrix.init(0, allocator);
        return SampleResult{
            .indices = indices[0..0],
            .matrix = matrix,
            .patterns = std.ArrayList(CachedPattern){},
            .allocator = allocator,
        };
    }

    // Edge case: if m == 1, return first string
    if (m == 1) {
        indices[0] = 0;
        const matrix = try DissimilarityMatrix.init(1, allocator);
        return SampleResult{
            .indices = indices,
            .matrix = matrix,
            .patterns = std.ArrayList(CachedPattern){},
            .allocator = allocator,
        };
    }

    // Adaptive seed selection with dissimilarity caching
    // Cache stores: (string_idx, seed_idx) -> dissimilarity
    // This avoids recomputing dissimilarities between rounds
    var selected = std.AutoHashMap(usize, void).init(allocator);
    defer selected.deinit();

    // Cache for dissimilarity values: key = (i, j) where i < j
    const CacheKey = struct { a: usize, b: usize };
    var dissim_cache = std.AutoHashMap(CacheKey, f64).init(allocator);
    defer dissim_cache.deinit();

    // Collected patterns for reuse in buildApproxMatrix
    var collected_patterns: std.ArrayList(CachedPattern) = .{};
    errdefer {
        for (collected_patterns.items) |p| {
            allocator.free(p.atoms);
        }
        collected_patterns.deinit(allocator);
    }

    // Helper function to get or compute dissimilarity and collect patterns
    const getCachedDissimilarityWithPatterns = struct {
        fn call(
            i: usize,
            j: usize,
            strings_ref: []const []const u8,
            atoms_ref: []const Atom,
            cache: *std.AutoHashMap(CacheKey, f64),
            patterns: *std.ArrayList(CachedPattern),
            alloc: Allocator,
        ) !f64 {
            // Normalize key so i < j
            const key = if (i < j) CacheKey{ .a = i, .b = j } else CacheKey{ .a = j, .b = i };

            // Check cache first
            if (cache.get(key)) |cached| {
                return cached;
            }

            // Compute with pattern collection
            const result = try computeDissimilarityWithPattern(
                strings_ref[i],
                strings_ref[j],
                atoms_ref,
                alloc,
            );

            // Store pattern if valid
            if (result.pattern) |p| {
                try patterns.append(alloc, CachedPattern{ .atoms = p, .cost = result.cost });
            }

            try cache.put(key, result.cost);
            return result.cost;
        }
    }.call;

    // Start with first string as initial seed
    indices[0] = 0;
    try selected.put(0, {});

    // Select remaining seeds
    for (1..m) |seed_idx| {
        var max_min_dist: f64 = -1.0;
        var best_candidate: usize = 0;

        // For each non-selected string
        for (0..n) |i| {
            if (selected.contains(i)) continue;

            // Compute minimum distance to any selected seed
            var min_dist: f64 = std.math.inf(f64);

            for (0..seed_idx) |j| {
                const selected_idx = indices[j];
                const dist = try getCachedDissimilarityWithPatterns(
                    i,
                    selected_idx,
                    strings,
                    atoms,
                    &dissim_cache,
                    &collected_patterns,
                    allocator,
                );

                if (dist < min_dist) {
                    min_dist = dist;
                }
            }

            // Pick string with maximum minimum distance (most dissimilar)
            if (min_dist > max_min_dist) {
                max_min_dist = min_dist;
                best_candidate = i;
            }
        }

        indices[seed_idx] = best_candidate;
        try selected.put(best_candidate, {});
    }

    // Compute pairwise dissimilarities for selected samples
    // Reuse cache from seed selection - some pairs may already be computed
    var matrix = try DissimilarityMatrix.init(m, allocator);
    errdefer matrix.deinit();

    for (0..m) |i| {
        for (i + 1..m) |j| {
            const dissim = try getCachedDissimilarityWithPatterns(
                indices[i],
                indices[j],
                strings,
                atoms,
                &dissim_cache,
                &collected_patterns,
                allocator,
            );
            matrix.set(i, j, dissim);
        }
    }

    return SampleResult{
        .indices = indices,
        .matrix = matrix,
        .patterns = collected_patterns,
        .allocator = allocator,
    };
}

/// Build approximate dissimilarity matrix using cached samples.
///
/// Implements the ApproxDMatrix algorithm from Figure 10 of the paper:
///
/// ```
/// func ApproxDMatrix(S: String[], Seeds: String[], η_seeds: Matrix)
///   A ← |S| × |S| matrix
///   for each s1, s2 ∈ S do
///     if s1, s2 ∈ Seeds then
///       A[s1, s2] ← η_seeds[s1, s2]  // Use cached value
///     else
///       A[s1, s2] ← η(s1, s2)        // Compute fresh (using cached patterns)
///   return A
/// ```
///
/// OPTIMIZATION: When computing new dissimilarities, we first try cached
/// patterns from the sampling phase. Pattern matching + cost calculation
/// is much faster than full pattern learning.
///
/// Parameters:
/// - strings: All strings (n strings)
/// - sample: Pre-computed sample result with m sampled strings and cached patterns
/// - atoms: List of atoms for pattern learning
/// - allocator: Memory allocator
///
/// Returns:
/// - DissimilarityMatrix for all n strings
pub fn buildApproxMatrix(
    strings: []const []const u8,
    sample: SampleResult,
    atoms: []const Atom,
    allocator: Allocator,
) !DissimilarityMatrix {
    const n = strings.len;
    var matrix = try DissimilarityMatrix.init(n, allocator);
    errdefer matrix.deinit();

    // Build reverse index: string index -> sample index
    var sample_map = std.AutoHashMap(usize, usize).init(allocator);
    defer sample_map.deinit();

    for (sample.indices, 0..) |str_idx, sample_idx| {
        try sample_map.put(str_idx, sample_idx);
    }

    // Fill matrix
    for (0..n) |i| {
        for (i + 1..n) |j| {
            const dissim = blk: {
                // Check if both are in sample
                const i_sample = sample_map.get(i);
                const j_sample = sample_map.get(j);

                if (i_sample != null and j_sample != null) {
                    // Both in sample - use cached value
                    const si = i_sample.?;
                    const sj = j_sample.?;

                    if (si < sj) {
                        break :blk sample.matrix.get(si, sj);
                    } else {
                        break :blk sample.matrix.get(sj, si);
                    }
                }

                // Compute using cached patterns first (key optimization!)
                const result = try computeDissimilarityWithCache(
                    strings[i],
                    strings[j],
                    sample.patterns.items,
                    atoms,
                    allocator,
                );
                // Free pattern if allocated (we don't collect more patterns here)
                if (result.pattern) |p| {
                    allocator.free(p);
                }
                break :blk result.cost;
            };

            matrix.set(i, j, dissim);
        }
    }

    return matrix;
}

// ============================================================================
// Tests
// ============================================================================

test "dissimilarity: identical strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};

    const dissim = try computeDissimilarity("123", "123", &atoms, allocator);

    // Identical strings should have zero dissimilarity (Definition 3.1)
    try testing.expectEqual(@as(f64, 0.0), dissim);
}

test "dissimilarity: different strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const u = atom_mod.upper();
    const atoms = [_]Atom{ d, u };

    const dissim = try computeDissimilarity("123", "456", &atoms, allocator);

    // Different strings should still have finite dissimilarity if pattern exists
    try testing.expect(dissim < std.math.inf(f64));
    try testing.expect(dissim >= 0.0);
}

test "dissimilarity: incompatible strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};

    const dissim = try computeDissimilarity("123", "abc", &atoms, allocator);

    // Incompatible strings (no common pattern) should have infinite dissimilarity
    try testing.expect(dissim == std.math.inf(f64));
}

test "dissimilarity matrix: storage and retrieval" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var matrix = try DissimilarityMatrix.init(4, allocator);
    defer matrix.deinit();

    // Set some values
    matrix.set(0, 1, 1.5);
    matrix.set(0, 2, 2.5);
    matrix.set(1, 2, 3.5);
    matrix.set(2, 3, 4.5);

    // Retrieve and verify
    try testing.expectEqual(@as(f64, 1.5), matrix.get(0, 1));
    try testing.expectEqual(@as(f64, 2.5), matrix.get(0, 2));
    try testing.expectEqual(@as(f64, 3.5), matrix.get(1, 2));
    try testing.expectEqual(@as(f64, 4.5), matrix.get(2, 3));
}

test "dissimilarity matrix: index calculation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const matrix = try DissimilarityMatrix.init(5, allocator);
    defer {
        var mut_matrix = matrix;
        mut_matrix.deinit();
    }

    // Verify index calculation for n=5
    // Upper triangle has 10 elements: (0,1), (0,2), (0,3), (0,4), (1,2), (1,3), (1,4), (2,3), (2,4), (3,4)
    try testing.expectEqual(@as(usize, 10), matrix.values.len);

    // Check specific indices
    try testing.expectEqual(@as(usize, 0), matrix.getIndex(0, 1)); // First element
    try testing.expectEqual(@as(usize, 1), matrix.getIndex(0, 2));
    try testing.expectEqual(@as(usize, 4), matrix.getIndex(1, 2)); // First of row 1
    try testing.expectEqual(@as(usize, 9), matrix.getIndex(3, 4)); // Last element
}

test "sample dissimilarities: empty dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};
    const strings = [_][]const u8{};

    var result = try sampleDissimilarities(&strings, 0, &atoms, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 0), result.indices.len);
    try testing.expectEqual(@as(usize, 0), result.matrix.n);
}

test "sample dissimilarities: single string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};
    const strings = [_][]const u8{"123"};

    var result = try sampleDissimilarities(&strings, 1, &atoms, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.indices.len);
    try testing.expectEqual(@as(usize, 0), result.indices[0]);
}

test "sample dissimilarities: multiple strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const u = atom_mod.upper();
    const atoms = [_]Atom{ d, u };

    const strings = [_][]const u8{ "123", "456", "789", "ABC" };

    var result = try sampleDissimilarities(&strings, 3, &atoms, allocator);
    defer result.deinit();

    // Should select 3 samples
    try testing.expectEqual(@as(usize, 3), result.indices.len);
    try testing.expectEqual(@as(usize, 3), result.matrix.n);

    // Matrix should have 3 entries in upper triangle
    try testing.expectEqual(@as(usize, 3), result.matrix.values.len);

    // First sample should be index 0
    try testing.expectEqual(@as(usize, 0), result.indices[0]);
}

test "sample dissimilarities: M_hat larger than dataset" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};
    const strings = [_][]const u8{ "123", "456" };

    // Request 10 samples from 2 strings - should cap at 2
    var result = try sampleDissimilarities(&strings, 10, &atoms, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 2), result.indices.len);
    try testing.expectEqual(@as(usize, 2), result.matrix.n);
}

test "build approx matrix: uses cached samples" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};
    const strings = [_][]const u8{ "111", "222", "333", "444" };

    // Sample 2 strings
    var sample = try sampleDissimilarities(&strings, 2, &atoms, allocator);
    defer sample.deinit();

    // Build full matrix using samples
    var matrix = try buildApproxMatrix(&strings, sample, &atoms, allocator);
    defer matrix.deinit();

    // Matrix should have n=4
    try testing.expectEqual(@as(usize, 4), matrix.n);

    // Should have 6 entries in upper triangle
    try testing.expectEqual(@as(usize, 6), matrix.values.len);

    // All dissimilarities should be finite (all are digit patterns)
    for (0..4) |i| {
        for (i + 1..4) |j| {
            const dissim = matrix.get(i, j);
            try testing.expect(dissim < std.math.inf(f64));
        }
    }
}

test "build approx matrix: empty sample" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};
    const strings = [_][]const u8{ "111", "222" };

    // Empty sample
    var sample = try sampleDissimilarities(&strings, 0, &atoms, allocator);
    defer sample.deinit();

    // Build full matrix - should compute all fresh
    var matrix = try buildApproxMatrix(&strings, sample, &atoms, allocator);
    defer matrix.deinit();

    try testing.expectEqual(@as(usize, 2), matrix.n);
    try testing.expect(matrix.get(0, 1) < std.math.inf(f64));
}
