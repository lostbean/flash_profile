const std = @import("std");

/// Represents cost values used in pattern selection.
/// Can be finite (f64) or infinity for invalid patterns.
pub const Cost = union(enum) {
    finite: f64,
    infinity,

    /// Add two costs together, propagating infinity.
    pub fn add(self: Cost, other: Cost) Cost {
        return switch (self) {
            .infinity => .infinity,
            .finite => |a| switch (other) {
                .infinity => .infinity,
                .finite => |b| .{ .finite = a + b },
            },
        };
    }

    /// Compare costs. Infinity is greater than any finite value.
    pub fn lessThan(self: Cost, other: Cost) bool {
        return switch (self) {
            .infinity => false,
            .finite => |a| switch (other) {
                .infinity => true,
                .finite => |b| a < b,
            },
        };
    }

    /// Check if two costs are equal.
    pub fn eql(self: Cost, other: Cost) bool {
        return switch (self) {
            .infinity => switch (other) {
                .infinity => true,
                .finite => false,
            },
            .finite => |a| switch (other) {
                .infinity => false,
                .finite => |b| a == b,
            },
        };
    }

    /// Create a finite cost.
    pub fn fromFinite(value: f64) Cost {
        return .{ .finite = value };
    }

    /// Get the infinity cost.
    pub fn asInfinity() Cost {
        return .infinity;
    }
};

/// String slice type for consistency.
pub const StringSlice = []const u8;

/// Entry in the profiling table mapping patterns to example data.
/// Used during training and pattern selection.
pub const ProfileEntry = struct {
    /// Indices of atoms that form the pattern.
    pattern_indices: []const u16,

    /// Cost of this pattern.
    cost: f64,

    /// Indices into the training data that match this pattern.
    data_indices: []const u32,
};
