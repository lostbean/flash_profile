const std = @import("std");
const Allocator = std.mem.Allocator;
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const learner_mod = @import("learner.zig");
const profile_mod = @import("profile.zig");
const ProfileEntry = profile_mod.ProfileEntry;
const ProfileResult = profile_mod.ProfileResult;

/// Compress a profile by iteratively merging the most similar patterns
///
/// Implements the CompressProfile algorithm from Figure 13 of the FlashProfile paper:
///
/// ```
/// CompressProfile(P̃, M):
///   while |P̃| > M:
///     (Pi, Pj) ← argmin_{i≠j} η(Pi, Pj)  // Find most similar patterns
///     P_merged ← LearnBestPattern(Data(Pi) ∪ Data(Pj))
///     P̃ ← P̃ \ {Pi, Pj} ∪ {P_merged}
///   return P̃
/// ```
///
/// Parameters:
/// - profile: Array of profile entries to compress
/// - target_count: Target number of patterns (M in the paper)
/// - strings: Original training data
/// - atoms: Atom library for pattern synthesis
/// - allocator: Memory allocator
///
/// Returns compressed profile with at most target_count entries.
/// If profile already has <= target_count entries, returns a copy unchanged.
pub fn compressProfile(
    profile: []const ProfileEntry,
    target_count: usize,
    strings: []const []const u8,
    atoms: []const Atom,
    allocator: Allocator,
) !ProfileResult {
    // If already at or below target, return a copy
    if (profile.len <= target_count) {
        const entries = try allocator.alloc(ProfileEntry, profile.len);
        errdefer allocator.free(entries);

        for (profile, 0..) |entry, i| {
            entries[i] = .{
                .pattern = try allocator.dupe(Atom, entry.pattern),
                .cost = entry.cost,
                .data_indices = try allocator.dupe(usize, entry.data_indices),
                .allocator = allocator,
            };
        }

        return ProfileResult{
            .entries = entries,
            .allocator = allocator,
        };
    }

    // Create working copy of profile
    var working: std.ArrayList(ProfileEntry) = .{};
    defer {
        for (working.items) |*entry| {
            entry.deinit();
        }
        working.deinit(allocator);
    }

    for (profile) |entry| {
        try working.append(allocator, .{
            .pattern = try allocator.dupe(Atom, entry.pattern),
            .cost = entry.cost,
            .data_indices = try allocator.dupe(usize, entry.data_indices),
            .allocator = allocator,
        });
    }

    // Iteratively merge until we reach target size
    while (working.items.len > target_count) {
        // Find most similar pair
        var min_similarity: f64 = std.math.inf(f64);
        var best_i: usize = 0;
        var best_j: usize = 1;

        for (0..working.items.len) |i| {
            for (i + 1..working.items.len) |j| {
                const similarity = try patternSimilarity(
                    working.items[i],
                    working.items[j],
                    strings,
                    atoms,
                    allocator,
                );

                if (similarity < min_similarity) {
                    min_similarity = similarity;
                    best_i = i;
                    best_j = j;
                }
            }
        }

        // Merge the most similar entries
        const merged = try mergeEntries(
            working.items[best_i],
            working.items[best_j],
            strings,
            atoms,
            allocator,
        );

        // Remove the two merged entries (remove higher index first)
        const to_remove = if (best_i > best_j) [_]usize{ best_i, best_j } else [_]usize{ best_j, best_i };

        // Free memory for removed entries
        working.items[to_remove[0]].deinit();
        _ = working.orderedRemove(to_remove[0]);

        working.items[to_remove[1]].deinit();
        _ = working.orderedRemove(to_remove[1]);

        // Add merged entry
        try working.append(allocator, merged);
    }

    // Transfer ownership to result
    const result_entries = try allocator.alloc(ProfileEntry, working.items.len);
    for (working.items, 0..) |entry, i| {
        result_entries[i] = entry;
    }

    // Clear working list without freeing (ownership transferred)
    working.clearRetainingCapacity();

    return ProfileResult{
        .entries = result_entries,
        .allocator = allocator,
    };
}

/// Compute similarity between two profile entries
///
/// Similarity is measured by the cost of learning a pattern for the combined data.
/// Lower cost = more similar patterns.
///
/// η(Pi, Pj) = cost of LearnBestPattern(Data(Pi) ∪ Data(Pj))
///
/// Parameters:
/// - entry1: First profile entry
/// - entry2: Second profile entry
/// - strings: Original training data
/// - atoms: Atom library
/// - allocator: Memory allocator
///
/// Returns the cost of the best pattern for combined data.
/// Returns infinity if no pattern can describe combined data.
pub fn patternSimilarity(
    entry1: ProfileEntry,
    entry2: ProfileEntry,
    strings: []const []const u8,
    atoms: []const Atom,
    allocator: Allocator,
) !f64 {
    // Combine the data indices from both entries
    const combined = try combineDataIndices(entry1, entry2, allocator);
    defer allocator.free(combined);

    // Get the corresponding strings
    const combined_strings = try getStringsForIndices(combined, strings, allocator);
    defer allocator.free(combined_strings);

    // Learn best pattern for combined data
    const result = try learner_mod.learnBestPattern(combined_strings, atoms, null, allocator);
    defer if (result) |*r| {
        var mut_r = r.*;
        mut_r.deinit();
    };

    if (result) |r| {
        return r.cost;
    } else {
        // No pattern found - return infinity (maximally dissimilar)
        return std.math.inf(f64);
    }
}

/// Merge two profile entries by learning a new pattern for their combined data
///
/// Parameters:
/// - entry1: First profile entry
/// - entry2: Second profile entry
/// - strings: Original training data
/// - atoms: Atom library
/// - allocator: Memory allocator
///
/// Returns a new ProfileEntry representing the merged result.
pub fn mergeEntries(
    entry1: ProfileEntry,
    entry2: ProfileEntry,
    strings: []const []const u8,
    atoms: []const Atom,
    allocator: Allocator,
) !ProfileEntry {
    // Combine data indices
    const combined_indices = try combineDataIndices(entry1, entry2, allocator);
    errdefer allocator.free(combined_indices);

    // Get corresponding strings
    const combined_strings = try getStringsForIndices(combined_indices, strings, allocator);
    defer allocator.free(combined_strings);

    // Learn best pattern for combined data
    const learn_result = try learner_mod.learnBestPattern(combined_strings, atoms, null, allocator);

    if (learn_result) |result| {
        defer {
            var mut_result = result;
            mut_result.deinit();
        }

        // Copy the pattern
        const pattern = try allocator.dupe(Atom, result.pattern);

        return ProfileEntry{
            .pattern = pattern,
            .cost = result.cost,
            .data_indices = combined_indices,
            .allocator = allocator,
        };
    } else {
        // No pattern found - create entry with empty pattern and infinity cost
        const empty_pattern = try allocator.alloc(Atom, 0);
        return ProfileEntry{
            .pattern = empty_pattern,
            .cost = std.math.inf(f64),
            .data_indices = combined_indices,
            .allocator = allocator,
        };
    }
}

/// Combine data indices from two entries, removing duplicates and sorting
fn combineDataIndices(
    entry1: ProfileEntry,
    entry2: ProfileEntry,
    allocator: Allocator,
) ![]usize {
    var combined: std.ArrayList(usize) = .{};
    defer combined.deinit(allocator);

    // Add all indices from both entries
    try combined.appendSlice(allocator, entry1.data_indices);
    try combined.appendSlice(allocator, entry2.data_indices);

    // Sort and remove duplicates
    std.mem.sort(usize, combined.items, {}, std.sort.asc(usize));

    var unique: std.ArrayList(usize) = .{};
    defer unique.deinit(allocator);

    if (combined.items.len > 0) {
        try unique.append(allocator, combined.items[0]);

        for (combined.items[1..]) |idx| {
            if (idx != unique.items[unique.items.len - 1]) {
                try unique.append(allocator, idx);
            }
        }
    }

    return unique.toOwnedSlice(allocator);
}

/// Get strings corresponding to data indices
fn getStringsForIndices(
    indices: []const usize,
    strings: []const []const u8,
    allocator: Allocator,
) ![][]const u8 {
    const result = try allocator.alloc([]const u8, indices.len);
    for (indices, 0..) |idx, i| {
        if (idx >= strings.len) {
            // Invalid index - use empty string
            result[i] = "";
        } else {
            result[i] = strings[idx];
        }
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "compress: already at target" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create simple profile with 2 entries
    const pattern1 = try allocator.alloc(Atom, 1);
    pattern1[0] = atom_mod.digit();
    const data1 = try allocator.alloc(usize, 2);
    data1[0] = 0;
    data1[1] = 1;

    const pattern2 = try allocator.alloc(Atom, 1);
    pattern2[0] = atom_mod.digit();
    const data2 = try allocator.alloc(usize, 1);
    data2[0] = 2;

    const entries = [_]ProfileEntry{
        .{ .pattern = pattern1, .cost = 10.0, .data_indices = data1, .allocator = allocator },
        .{ .pattern = pattern2, .cost = 15.0, .data_indices = data2, .allocator = allocator },
    };
    defer {
        allocator.free(pattern1);
        allocator.free(data1);
        allocator.free(pattern2);
        allocator.free(data2);
    }

    const strings = [_][]const u8{ "123", "456", "789" };
    const d = atom_mod.digit();
    const atoms = [_]Atom{d};

    // Target is 2, profile has 2 entries - should return copy unchanged
    var result = try compressProfile(&entries, 2, &strings, &atoms, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 2), result.entries.len);
}

test "compress: merge similar patterns" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create profile with 3 entries representing digit patterns
    const pattern1 = try allocator.alloc(Atom, 1);
    pattern1[0] = atom_mod.digit();
    const data1 = try allocator.alloc(usize, 2);
    data1[0] = 0; // "123"
    data1[1] = 1; // "456"

    const pattern2 = try allocator.alloc(Atom, 1);
    pattern2[0] = atom_mod.digit();
    const data2 = try allocator.alloc(usize, 1);
    data2[0] = 2; // "789"

    const pattern3 = try allocator.alloc(Atom, 1);
    pattern3[0] = atom_mod.upper();
    const data3 = try allocator.alloc(usize, 1);
    data3[0] = 3; // "ABC"

    const entries = [_]ProfileEntry{
        .{ .pattern = pattern1, .cost = 10.0, .data_indices = data1, .allocator = allocator },
        .{ .pattern = pattern2, .cost = 10.0, .data_indices = data2, .allocator = allocator },
        .{ .pattern = pattern3, .cost = 12.0, .data_indices = data3, .allocator = allocator },
    };
    defer {
        allocator.free(pattern1);
        allocator.free(data1);
        allocator.free(pattern2);
        allocator.free(data2);
        allocator.free(pattern3);
        allocator.free(data3);
    }

    const strings = [_][]const u8{ "123", "456", "789", "ABC" };
    const d = atom_mod.digit();
    const u = atom_mod.upper();
    const atoms = [_]Atom{ d, u };

    // Compress from 3 to 2 entries
    var result = try compressProfile(&entries, 2, &strings, &atoms, allocator);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 2), result.entries.len);
}

test "compress: combine data indices" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const pattern1 = try allocator.alloc(Atom, 1);
    pattern1[0] = atom_mod.digit();
    const data1 = try allocator.alloc(usize, 3);
    data1[0] = 0;
    data1[1] = 2;
    data1[2] = 4;

    const pattern2 = try allocator.alloc(Atom, 1);
    pattern2[0] = atom_mod.digit();
    const data2 = try allocator.alloc(usize, 3);
    data2[0] = 1;
    data2[1] = 2; // duplicate
    data2[2] = 3;

    const entry1 = ProfileEntry{
        .pattern = pattern1,
        .cost = 10.0,
        .data_indices = data1,
        .allocator = allocator,
    };

    const entry2 = ProfileEntry{
        .pattern = pattern2,
        .cost = 10.0,
        .data_indices = data2,
        .allocator = allocator,
    };

    defer {
        allocator.free(pattern1);
        allocator.free(data1);
        allocator.free(pattern2);
        allocator.free(data2);
    }

    const combined = try combineDataIndices(entry1, entry2, allocator);
    defer allocator.free(combined);

    // Should have 5 unique indices: 0, 1, 2, 3, 4
    try testing.expectEqual(@as(usize, 5), combined.len);
    try testing.expectEqual(@as(usize, 0), combined[0]);
    try testing.expectEqual(@as(usize, 1), combined[1]);
    try testing.expectEqual(@as(usize, 2), combined[2]);
    try testing.expectEqual(@as(usize, 3), combined[3]);
    try testing.expectEqual(@as(usize, 4), combined[4]);
}

test "compress: pattern similarity" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const u = atom_mod.upper();
    const atoms = [_]Atom{ d, u };

    // Create two entries with digit patterns
    const pattern1 = try allocator.alloc(Atom, 1);
    pattern1[0] = atom_mod.digit();
    const data1 = try allocator.alloc(usize, 1);
    data1[0] = 0;

    const pattern2 = try allocator.alloc(Atom, 1);
    pattern2[0] = atom_mod.digit();
    const data2 = try allocator.alloc(usize, 1);
    data2[0] = 1;

    const entry1 = ProfileEntry{
        .pattern = pattern1,
        .cost = 10.0,
        .data_indices = data1,
        .allocator = allocator,
    };

    const entry2 = ProfileEntry{
        .pattern = pattern2,
        .cost = 10.0,
        .data_indices = data2,
        .allocator = allocator,
    };

    defer {
        allocator.free(pattern1);
        allocator.free(data1);
        allocator.free(pattern2);
        allocator.free(data2);
    }

    const strings = [_][]const u8{ "123", "456" };

    const similarity = try patternSimilarity(entry1, entry2, &strings, &atoms, allocator);

    // Similarity should be finite (both match digit pattern)
    try testing.expect(!std.math.isInf(similarity));
    try testing.expect(similarity > 0.0);
}

test "compress: merge entries" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const d = atom_mod.digit();
    const atoms = [_]Atom{d};

    const pattern1 = try allocator.alloc(Atom, 1);
    pattern1[0] = atom_mod.digit();
    const data1 = try allocator.alloc(usize, 1);
    data1[0] = 0;

    const pattern2 = try allocator.alloc(Atom, 1);
    pattern2[0] = atom_mod.digit();
    const data2 = try allocator.alloc(usize, 1);
    data2[0] = 1;

    const entry1 = ProfileEntry{
        .pattern = pattern1,
        .cost = 10.0,
        .data_indices = data1,
        .allocator = allocator,
    };

    const entry2 = ProfileEntry{
        .pattern = pattern2,
        .cost = 10.0,
        .data_indices = data2,
        .allocator = allocator,
    };

    defer {
        allocator.free(pattern1);
        allocator.free(data1);
        allocator.free(pattern2);
        allocator.free(data2);
    }

    const strings = [_][]const u8{ "123", "456" };

    var merged = try mergeEntries(entry1, entry2, &strings, &atoms, allocator);
    defer merged.deinit();

    // Merged entry should cover both data points
    try testing.expectEqual(@as(usize, 2), merged.data_indices.len);
    try testing.expect(merged.cost > 0.0);
}
