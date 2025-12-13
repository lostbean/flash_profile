// NIF entry point for FlashProfile Zig implementation
// This file defines the public NIF functions exposed to Elixir via Zigler

const std = @import("std");
const beam = @import("beam");

// Import core FlashProfile modules
const atom_mod = @import("atom.zig");
const pattern_mod = @import("pattern.zig");
const cost_mod = @import("cost.zig");
const learner_mod = @import("learner.zig");
const profile_mod = @import("profile.zig");
const dissimilarity_mod = @import("dissimilarity.zig");
const types = @import("types.zig");

const Atom = atom_mod.Atom;
const Pattern = pattern_mod.Pattern;
const Cost = types.Cost;
const ProfileEntry = profile_mod.ProfileEntry;
const ProfileResult = profile_mod.ProfileResult;
const ProfileOptions = profile_mod.ProfileOptions;

// ============================================================================
// Default Atoms Registry
// ============================================================================

/// Default atoms from FlashProfile paper (Figure 6)
/// Ordered to match Elixir implementation in lib/flash_profile/atoms/defaults.ex
const default_atoms = [_]Atom{
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

// ============================================================================
// NIF Functions
// ============================================================================

/// Learn the best pattern for a list of strings.
/// Returns: {:ok, {pattern_names, cost}} or {:error, reason}
pub fn learn_pattern_nif(strings: []const []const u8) !beam.term {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Handle empty dataset
    if (strings.len == 0) {
        return beam.make(.{ .ok, .{ &[_][]const u8{}, @as(f64, 0.0) } }, .{});
    }

    // Learn best pattern
    const result = try learner_mod.learnBestPattern(strings, &default_atoms, allocator);

    if (result) |learn_result| {
        // Collect pattern atom names
        var names = try allocator.alloc([]const u8, learn_result.pattern.len);
        for (learn_result.pattern, 0..) |atom_val, i| {
            names[i] = atom_val.name;
        }

        return beam.make(.{ .ok, .{ names, learn_result.cost } }, .{});
    } else {
        return beam.make(.{ .@"error", .no_pattern }, .{});
    }
}

/// Check if a pattern matches a string.
/// Pattern is specified as list of atom names.
/// Returns: true | false
pub fn matches_nif(pattern_names: []const []const u8, string: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Build pattern from atom names
    const atoms_list = allocator.alloc(Atom, pattern_names.len) catch return false;

    for (pattern_names, 0..) |name, i| {
        atoms_list[i] = lookupAtomByName(name) orelse return false;
    }

    // Check if pattern matches
    const pattern = Pattern.init(atoms_list);
    return pattern.matches(string);
}

/// Calculate the cost of a pattern over a dataset.
/// Returns: {:ok, cost} or {:error, :no_match}
pub fn calculate_cost_nif(pattern_names: []const []const u8, strings: []const []const u8) !beam.term {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Build pattern from atom names
    const atoms_list = try allocator.alloc(Atom, pattern_names.len);

    for (pattern_names, 0..) |name, i| {
        atoms_list[i] = lookupAtomByName(name) orelse {
            return beam.make(.{ .@"error", .invalid_atom }, .{});
        };
    }

    // Calculate cost
    const cost_result = try cost_mod.calculateCost(atoms_list, strings, allocator);

    return switch (cost_result) {
        .infinity => beam.make(.{ .@"error", .no_match }, .{}),
        .finite => |cost| beam.make(.{ .ok, cost }, .{}),
    };
}

/// Profile algorithm: extract patterns from a dataset.
/// Returns: {:ok, [%{pattern: [atom_names], cost: float, indices: [int]}]} or {:error, reason}
pub fn profile_nif(
    strings: []const []const u8,
    min_patterns: usize,
    max_patterns: usize,
    theta: f64,
) !beam.term {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Set up options
    const options = ProfileOptions{
        .min_patterns = min_patterns,
        .max_patterns = max_patterns,
        .theta = theta,
    };

    // Run profile algorithm
    var result = try profile_mod.profile(strings, &default_atoms, options, allocator);
    defer result.deinit();

    // Convert to Elixir terms
    return try convertProfileResultToTerm(result, allocator);
}

/// BigProfile algorithm: extract patterns from large datasets.
/// Returns: {:ok, [%{pattern: [atom_names], cost: float, indices: [int]}]} or {:error, reason}
pub fn big_profile_nif(
    strings: []const []const u8,
    min_patterns: usize,
    max_patterns: usize,
    theta: f64,
    mu: f64,
) !beam.term {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Set up options
    const options = ProfileOptions{
        .min_patterns = min_patterns,
        .max_patterns = max_patterns,
        .theta = theta,
        .mu = mu,
    };

    // Run BigProfile algorithm
    var result = try profile_mod.bigProfile(strings, &default_atoms, options, allocator);
    defer result.deinit();

    // Convert to Elixir terms
    return try convertProfileResultToTerm(result, allocator);
}

/// Compute dissimilarity between two strings.
/// Returns: {:ok, cost} or {:error, :no_pattern}
pub fn dissimilarity_nif(string1: []const u8, string2: []const u8) !beam.term {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Compute dissimilarity
    const dissim = try dissimilarity_mod.computeDissimilarity(
        string1,
        string2,
        &default_atoms,
        allocator,
    );

    // Check if result is infinity (no pattern found)
    if (std.math.isInf(dissim)) {
        return beam.make(.{ .@"error", .no_pattern }, .{});
    }

    return beam.make(.{ .ok, dissim }, .{});
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Look up an atom by name from default atoms, or create a constant atom
fn lookupAtomByName(name: []const u8) ?Atom {
    // First check if it's a default atom (character class)
    for (default_atoms) |atom_val| {
        if (std.mem.eql(u8, atom_val.name, name)) {
            return atom_val;
        }
    }

    // If not a default atom, treat it as a constant atom
    // The constant function creates an atom that matches the exact string
    return atom_mod.constant(name, name);
}

/// Convert ProfileResult to Elixir term
/// Returns: {:ok, [%{pattern: [atom_names], cost: float, indices: [int]}]}
fn convertProfileResultToTerm(
    result: ProfileResult,
    allocator: std.mem.Allocator,
) !beam.term {
    // Build list of entry maps
    var entries_list = try allocator.alloc(EntryTerm, result.entries.len);

    for (result.entries, 0..) |entry, i| {
        // Convert pattern atoms to names
        var pattern_names = try allocator.alloc([]const u8, entry.pattern.len);
        for (entry.pattern, 0..) |atom_val, j| {
            pattern_names[j] = atom_val.name;
        }

        // Convert indices to slice
        const indices = entry.data_indices;

        // Create entry struct for beam.make
        entries_list[i] = .{
            .pattern = pattern_names,
            .cost = entry.cost,
            .indices = indices,
        };
    }

    return beam.make(.{ .ok, entries_list }, .{});
}

/// Helper struct for beam.make conversion
const EntryTerm = struct {
    pattern: []const []const u8,
    cost: f64,
    indices: []const usize,
};
