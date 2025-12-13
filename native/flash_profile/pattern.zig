const std = @import("std");
const atom_mod = @import("atom.zig");
const Atom = atom_mod.Atom;
const types = @import("types.zig");

/// A pattern is a sequence of atoms.
///
/// From the FlashProfile paper (Definition 4.3):
/// "A pattern is simply a sequence of atoms. The pattern Empty denotes an empty
/// sequence, which only matches the empty string ε."
///
/// Pattern P describes string s iff:
/// - s ≠ ε (non-empty) OR s = ε and P is empty
/// - ∀i ∈ {1,...,k}: αi(si) > 0 (each atom matches a non-empty prefix)
/// - sk+1 = ε (entire string consumed)
///
/// Matching is greedy left-to-right:
/// 1. Start at position 0
/// 2. For each atom, match against remaining string
/// 3. If match fails (returns null), pattern doesn't match
/// 4. After all atoms, entire string must be consumed
pub const Pattern = struct {
    /// Sequence of atoms
    atoms: []const Atom,

    /// Create an empty pattern (matches only empty string).
    pub fn empty() Pattern {
        return .{ .atoms = &[_]Atom{} };
    }

    /// Create a pattern from a slice of atoms.
    pub fn init(atoms: []const Atom) Pattern {
        return .{ .atoms = atoms };
    }

    /// Check if this pattern matches a string entirely.
    ///
    /// Returns true if:
    /// - Empty pattern and empty string, OR
    /// - Each atom matches a non-empty prefix and entire string is consumed
    ///
    /// Examples:
    /// - Pattern [] matches ""
    /// - Pattern [Digit] matches "123" but not "123abc"
    pub fn matches(self: Pattern, string: []const u8) bool {
        return self.matchInternal(string) != null;
    }

    /// Match pattern and return the lengths matched by each atom.
    /// Returns null if pattern doesn't match.
    ///
    /// This is used for cost calculation - we need to know how much
    /// each atom matched to compute dynamic costs.
    pub fn matchLengths(self: Pattern, allocator: std.mem.Allocator, string: []const u8) !?[]usize {
        // Empty pattern only matches empty string
        if (self.atoms.len == 0) {
            return if (string.len == 0) try allocator.alloc(usize, 0) else null;
        }

        // Allocate array to hold lengths
        const lengths = try allocator.alloc(usize, self.atoms.len);
        errdefer allocator.free(lengths);

        var pos: usize = 0;

        for (self.atoms, 0..) |atom, i| {
            const remaining = string[pos..];
            const len = atom.match(remaining) orelse {
                allocator.free(lengths);
                return null;
            };

            lengths[i] = len;
            pos += len;
        }

        // Entire string must be consumed
        if (pos != string.len) {
            allocator.free(lengths);
            return null;
        }

        return lengths;
    }

    /// Internal matching that checks if pattern matches (for matches() function).
    /// Uses stack-allocated buffer, only returns bool-compatible result.
    fn matchInternal(self: Pattern, string: []const u8) ?[]const usize {
        // Empty pattern only matches empty string
        if (self.atoms.len == 0) {
            return if (string.len == 0) &[_]usize{} else null;
        }

        // Buffer to store match lengths (max 64 atoms per pattern)
        // Note: This is only used for the matches() function which just checks
        // if the return is non-null. The actual values are not used after return.
        var lengths_buffer: [64]usize = undefined;
        if (self.atoms.len > lengths_buffer.len) {
            // Pattern too long
            return null;
        }

        var pos: usize = 0;

        for (self.atoms, 0..) |atom, i| {
            const remaining = string[pos..];
            const len = atom.match(remaining) orelse return null;

            lengths_buffer[i] = len;
            pos += len;
        }

        // Entire string must be consumed
        if (pos != string.len) {
            return null;
        }

        // Return non-null to indicate match (values not used)
        return lengths_buffer[0..self.atoms.len];
    }
};

/// Helper function to check if pattern matches, with atom array.
/// Convenience wrapper for creating a Pattern on the fly.
pub fn matches(atoms: []const Atom, string: []const u8) bool {
    const pattern = Pattern.init(atoms);
    return pattern.matches(string);
}

/// Helper function to get match lengths for a pattern.
pub fn matchLengths(allocator: std.mem.Allocator, atoms: []const Atom, string: []const u8) !?[]usize {
    const pattern = Pattern.init(atoms);
    return pattern.matchLengths(allocator, string);
}

// ============================================================================
// Tests
// ============================================================================

test "Empty pattern" {
    const empty_pattern = Pattern.empty();

    try std.testing.expect(empty_pattern.matches(""));
    try std.testing.expect(!empty_pattern.matches("abc"));
}

test "Single atom pattern" {
    const d = atom_mod.digit();
    const pattern = Pattern.init(&[_]Atom{d});

    try std.testing.expect(pattern.matches("123"));
    try std.testing.expect(!pattern.matches("123abc"));
    try std.testing.expect(!pattern.matches("abc"));
}

test "Multi-atom pattern" {
    const u = atom_mod.upper();
    const dash = atom_mod.constant("Dash", "-");
    const d = atom_mod.digit();

    const pattern = Pattern.init(&[_]Atom{ u, dash, d });

    // Match: Upper+ "-" Digit+
    try std.testing.expect(pattern.matches("A-123"));
    try std.testing.expect(pattern.matches("ABC-456"));
    try std.testing.expect(!pattern.matches("A-"));
    try std.testing.expect(!pattern.matches("a-123"));
    try std.testing.expect(!pattern.matches("A123"));
}

test "Match lengths" {
    const u = atom_mod.upper();
    const d = atom_mod.digit();

    const pattern = Pattern.init(&[_]Atom{ u, d });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // "A123" -> Upper matches 1, Digit matches 3
    const lengths = try pattern.matchLengths(allocator, "A123");
    try std.testing.expect(lengths != null);
    try std.testing.expectEqual(@as(usize, 2), lengths.?.len);
    try std.testing.expectEqual(@as(usize, 1), lengths.?[0]);
    try std.testing.expectEqual(@as(usize, 3), lengths.?[1]);

    // "ABC123" -> Upper matches 3, Digit matches 3
    const lengths2 = try pattern.matchLengths(allocator, "ABC123");
    try std.testing.expect(lengths2 != null);
    try std.testing.expectEqual(@as(usize, 2), lengths2.?.len);
    try std.testing.expectEqual(@as(usize, 3), lengths2.?[0]);
    try std.testing.expectEqual(@as(usize, 3), lengths2.?[1]);

    // "invalid" -> no match
    const no_match = try pattern.matchLengths(allocator, "invalid");
    try std.testing.expect(no_match == null);
}

test "Fixed-width atoms in pattern" {
    const u = atom_mod.upper();
    const d2 = atom_mod.withFixedWidth(atom_mod.digit(), 2);

    const pattern = Pattern.init(&[_]Atom{ u, d2 });

    // Upper+ Digit×2
    try std.testing.expect(pattern.matches("A12"));
    try std.testing.expect(pattern.matches("ABC12"));
    try std.testing.expect(!pattern.matches("A1"));
    try std.testing.expect(!pattern.matches("A123"));
}

test "Helper functions" {
    const d = atom_mod.digit();
    const atoms = [_]Atom{d};

    try std.testing.expect(matches(&atoms, "123"));
    try std.testing.expect(!matches(&atoms, "abc"));

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const lengths = try matchLengths(allocator, &atoms, "456");
    try std.testing.expect(lengths != null);
    try std.testing.expectEqual(@as(usize, 1), lengths.?.len);
    try std.testing.expectEqual(@as(usize, 3), lengths.?[0]);
}
