// FlashProfile Zig Implementation
// Main module that re-exports all submodules for Zigler NIF binding

pub const types = @import("types.zig");
pub const atom = @import("atom.zig");
pub const pattern = @import("pattern.zig");
pub const cost = @import("cost.zig");
pub const learner = @import("learner.zig");
pub const dissimilarity = @import("dissimilarity.zig");
pub const hierarchy = @import("hierarchy.zig");
pub const profile = @import("profile.zig");
pub const compress = @import("compress.zig");

// Re-export main types for convenience
pub const Cost = types.Cost;
pub const ProfileEntry = types.ProfileEntry;
pub const Atom = atom.Atom;
pub const AtomType = atom.AtomType;
pub const CharSet = atom.CharSet;
pub const Pattern = pattern.Pattern;
pub const LearnResult = learner.LearnResult;

// Default atoms
pub const lower = atom.lower;
pub const upper = atom.upper;
pub const digit = atom.digit;
pub const alpha = atom.alpha;
pub const alphaDigit = atom.alphaDigit;
pub const space = atom.space;
pub const any = atom.any;
pub const constant = atom.constant;
pub const withFixedWidth = atom.withFixedWidth;

// Tests
test {
    _ = types;
    _ = atom;
    _ = pattern;
    _ = cost;
    _ = learner;
    _ = dissimilarity;
    _ = hierarchy;
    _ = profile;
    _ = compress;
}
