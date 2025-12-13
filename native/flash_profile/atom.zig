const std = @import("std");
const types = @import("types.zig");

/// Efficient ASCII character set using bitmap for O(1) membership testing.
/// Uses two u64s to cover all 128 ASCII values (0-127).
pub const CharSet = struct {
    /// Lower 64 bits (ASCII 0-63)
    low: u64,
    /// Upper 64 bits (ASCII 64-127)
    high: u64,

    /// Create an empty character set.
    pub fn empty() CharSet {
        return .{ .low = 0, .high = 0 };
    }

    /// Create a character set from a slice of characters.
    pub fn fromChars(chars: []const u8) CharSet {
        var set = empty();
        for (chars) |c| {
            set.add(c);
        }
        return set;
    }

    /// Add a character to the set.
    pub fn add(self: *CharSet, c: u8) void {
        if (c < 64) {
            self.low |= @as(u64, 1) << @intCast(c);
        } else if (c < 128) {
            self.high |= @as(u64, 1) << @intCast(c - 64);
        }
        // Non-ASCII characters are ignored
    }

    /// Check if a character is in the set. O(1) lookup.
    pub fn contains(self: CharSet, c: u8) bool {
        if (c < 64) {
            return (self.low & (@as(u64, 1) << @intCast(c))) != 0;
        } else if (c < 128) {
            return (self.high & (@as(u64, 1) << @intCast(c - 64))) != 0;
        }
        return false;
    }
};

/// Type of atom for pattern matching.
pub const AtomType = enum {
    /// Constant string match
    constant,
    /// Character class (fixed or variable width)
    char_class,
    /// Regular expression match
    regex,
    /// Custom function match
    function,
};

/// Character class data for both fixed and variable width matching.
pub const CharClassData = struct {
    /// Set of allowed characters
    char_set: CharSet,
    /// Width: 0 = variable (greedy), >0 = fixed width
    width: u32,
};

/// Constant string data.
pub const ConstantData = struct {
    /// The exact string to match
    string: []const u8,
};

/// Atom data - type-specific matching information.
pub const AtomData = union(AtomType) {
    constant: ConstantData,
    char_class: CharClassData,
    regex: void, // Not implemented in Phase 2
    function: void, // Not implemented in Phase 2
};

/// An atom represents an atomic pattern that matches a prefix of a string.
///
/// From the FlashProfile paper (Definition 4.1):
/// "An atom α: String → Int is a function, which given a string s, returns
/// the length of the longest prefix of s that satisfies its constraints.
/// Atoms only match non-empty prefixes. α(s) = 0 indicates match failure."
pub const Atom = struct {
    /// Display name of the atom
    name: []const u8,

    /// Static cost for this atom (used in pattern selection)
    static_cost: f64,

    /// Type-specific matching data
    data: AtomData,

    /// Match this atom against a string.
    /// Returns the length of the matched prefix, or null if no match.
    ///
    /// Matching semantics:
    /// - Constant: Returns string length if prefix matches exactly, else null
    /// - CharClass (variable): Returns length of longest prefix with all chars in set
    /// - CharClass (fixed): Returns width if exactly width chars match, else null
    pub fn match(self: Atom, string: []const u8) ?usize {
        return switch (self.data) {
            .constant => |data| self.matchConstant(string, data),
            .char_class => |data| self.matchCharClass(string, data),
            .regex => null, // Not implemented
            .function => null, // Not implemented
        };
    }

    /// Match a constant string.
    fn matchConstant(self: Atom, string: []const u8, data: ConstantData) ?usize {
        _ = self;
        if (string.len < data.string.len) return null;

        // Check if string starts with the constant
        if (std.mem.eql(u8, string[0..data.string.len], data.string)) {
            return data.string.len;
        }
        return null;
    }

    /// Match a character class (variable or fixed width).
    fn matchCharClass(self: Atom, string: []const u8, data: CharClassData) ?usize {
        _ = self;
        if (data.width == 0) {
            // Variable width: match as many characters as possible
            return matchCharClassVariable(string, data.char_set);
        } else {
            // Fixed width: match exactly 'width' characters
            return matchCharClassFixed(string, data.char_set, data.width);
        }
    }
};

/// Match variable-width character class.
/// Returns the length of the longest prefix where all characters are in the set.
/// Returns null if first character doesn't match (atoms only match non-empty prefixes).
fn matchCharClassVariable(string: []const u8, char_set: CharSet) ?usize {
    var count: usize = 0;
    for (string) |c| {
        if (char_set.contains(c)) {
            count += 1;
        } else {
            break;
        }
    }
    // Atoms only match non-empty prefixes
    return if (count > 0) count else null;
}

/// Match fixed-width character class.
/// Returns width if exactly 'width' characters match, null otherwise.
fn matchCharClassFixed(string: []const u8, char_set: CharSet, width: u32) ?usize {
    if (string.len < width) return null;

    // Check if first 'width' characters are all in the set
    for (string[0..width]) |c| {
        if (!char_set.contains(c)) return null;
    }

    return width;
}

// ============================================================================
// Default Atoms from the FlashProfile Paper (Figure 6)
// ============================================================================

/// Create lowercase letter atom [a-z]
pub fn lower() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyz";
    return .{
        .name = "Lower",
        .static_cost = 9.1,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create uppercase letter atom [A-Z]
pub fn upper() Atom {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return .{
        .name = "Upper",
        .static_cost = 8.2,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create digit atom [0-9]
pub fn digit() Atom {
    const chars = "0123456789";
    return .{
        .name = "Digit",
        .static_cost = 8.2,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create alphabetic atom [a-zA-Z]
pub fn alpha() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return .{
        .name = "Alpha",
        .static_cost = 15.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create alphanumeric atom [a-zA-Z0-9]
pub fn alphaDigit() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    return .{
        .name = "AlphaDigit",
        .static_cost = 20.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create whitespace atom (space, tab, newline, carriage return, form feed)
pub fn space() Atom {
    const chars = " \t\n\r\x0C";
    return .{
        .name = "Space",
        .static_cost = 5.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create binary digits atom [01]
pub fn bin() Atom {
    const chars = "01";
    return .{
        .name = "Bin",
        .static_cost = 5.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create hexadecimal digits atom [0-9a-fA-F]
pub fn hex() Atom {
    const chars = "0123456789abcdefABCDEF";
    return .{
        .name = "Hex",
        .static_cost = 26.3,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create alphanumeric and whitespace atom [a-zA-Z0-9\s]
pub fn alphaDigitSpace() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \t\n\r\x0C";
    return .{
        .name = "AlphaDigitSpace",
        .static_cost = 25.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create dot and dash atom [.-]
pub fn dotDash() Atom {
    const chars = ".-";
    return .{
        .name = "DotDash",
        .static_cost = 3.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create common punctuation atom [.,:?/-]
pub fn punct() Atom {
    const chars = ".,:?/-";
    return .{
        .name = "Punct",
        .static_cost = 10.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create alphabetic and dash atom [a-zA-Z-]
pub fn alphaDash() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-";
    return .{
        .name = "AlphaDash",
        .static_cost = 18.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create symbol characters atom [-.,://@#$%&*()!~`+=<>?]
pub fn symb() Atom {
    const chars = "-.,://@#$%&*()!~`+=<>?";
    return .{
        .name = "Symb",
        .static_cost = 30.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create alphabetic and whitespace atom [a-zA-Z\s]
pub fn alphaSpace() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ \t\n\r\x0C";
    return .{
        .name = "AlphaSpace",
        .static_cost = 18.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create Base64 characters atom [a-zA-Z0-9+=]
pub fn base64() Atom {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+=";
    return .{
        .name = "Base64",
        .static_cost = 25.0,
        .data = .{ .char_class = .{
            .char_set = CharSet.fromChars(chars),
            .width = 0,
        } },
    };
}

/// Create any printable ASCII atom (ASCII 32-126)
pub fn any() Atom {
    @setEvalBranchQuota(2000);
    var char_set = CharSet.empty();
    var i: u8 = 32;
    while (i <= 126) : (i += 1) {
        char_set.add(i);
    }
    return .{
        .name = "Any",
        .static_cost = 100.0,
        .data = .{ .char_class = .{
            .char_set = char_set,
            .width = 0,
        } },
    };
}

/// Create a constant string atom.
/// Cost is proportional to 1/length to prefer longer matches.
pub fn constant(name: []const u8, string: []const u8) Atom {
    const len = string.len;
    const cost = 100.0 / @as(f64, @floatFromInt(len));

    return .{
        .name = name,
        .static_cost = cost,
        .data = .{ .constant = .{ .string = string } },
    };
}

/// Create a fixed-width variant of a character class atom.
pub fn withFixedWidth(base_atom: Atom, width: u32) Atom {
    var result = base_atom;
    if (result.data == .char_class) {
        result.data.char_class.width = width;
        // Fixed-width cost is base_cost / width
        result.static_cost = base_atom.static_cost / @as(f64, @floatFromInt(width));
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "CharSet basic operations" {
    var set = CharSet.empty();
    try std.testing.expect(!set.contains('a'));

    set.add('a');
    try std.testing.expect(set.contains('a'));
    try std.testing.expect(!set.contains('b'));

    set.add('z');
    try std.testing.expect(set.contains('z'));
    try std.testing.expect(set.contains('a'));
}

test "CharSet fromChars" {
    const set = CharSet.fromChars("abc123");
    try std.testing.expect(set.contains('a'));
    try std.testing.expect(set.contains('b'));
    try std.testing.expect(set.contains('c'));
    try std.testing.expect(set.contains('1'));
    try std.testing.expect(set.contains('2'));
    try std.testing.expect(set.contains('3'));
    try std.testing.expect(!set.contains('d'));
    try std.testing.expect(!set.contains('0'));
}

test "Constant atom matching" {
    const pmc = constant("PMC", "PMC");

    try std.testing.expectEqual(@as(?usize, 3), pmc.match("PMC12345"));
    try std.testing.expectEqual(@as(?usize, null), pmc.match("XYZ"));
    try std.testing.expectEqual(@as(?usize, null), pmc.match("PM"));
}

test "Variable-width char class matching" {
    const d = digit();

    try std.testing.expectEqual(@as(?usize, 3), d.match("123abc"));
    try std.testing.expectEqual(@as(?usize, null), d.match("abc123"));
    try std.testing.expectEqual(@as(?usize, 1), d.match("5"));
}

test "Fixed-width char class matching" {
    const digit2 = withFixedWidth(digit(), 2);

    try std.testing.expectEqual(@as(?usize, 2), digit2.match("12345"));
    try std.testing.expectEqual(@as(?usize, null), digit2.match("1abc"));
    try std.testing.expectEqual(@as(?usize, 2), digit2.match("123"));
}

test "Default atoms" {
    const l = lower();
    try std.testing.expectEqual(@as(?usize, 3), l.match("abc123"));
    try std.testing.expectEqual(@as(?usize, null), l.match("ABC"));

    const u = upper();
    try std.testing.expectEqual(@as(?usize, 3), u.match("ABC123"));
    try std.testing.expectEqual(@as(?usize, null), u.match("abc"));

    const a = alpha();
    try std.testing.expectEqual(@as(?usize, 6), a.match("abcDEF123"));

    const s = space();
    try std.testing.expectEqual(@as(?usize, 3), s.match("   abc"));
    try std.testing.expectEqual(@as(?usize, 1), s.match("\ttest"));
}

test "Enhanced atoms - DotDash" {
    const dd = dotDash();
    // DotDash only matches '.' and '-', not digits
    try std.testing.expectEqual(@as(?usize, null), dd.match("2023-01-15"));
    try std.testing.expectEqual(@as(?usize, 2), dd.match("--comment"));
    try std.testing.expectEqual(@as(?usize, 3), dd.match("...more"));
    try std.testing.expectEqual(@as(?usize, null), dd.match("abc"));
    try std.testing.expectEqual(@as(?usize, 1), dd.match("-dash"));
}

test "Enhanced atoms - Symb" {
    const s = symb();
    try std.testing.expectEqual(@as(?usize, 1), s.match("@user"));
    try std.testing.expectEqual(@as(?usize, 1), s.match("#tag"));
    // "://" matches 3 symbol chars (: / /)
    try std.testing.expectEqual(@as(?usize, 3), s.match("://rest"));
    try std.testing.expectEqual(@as(?usize, null), s.match("abc"));
}

test "Enhanced atoms - AlphaSpace" {
    const as = alphaSpace();
    try std.testing.expectEqual(@as(?usize, 11), as.match("Hello World123"));
    // "Hello World  \tMore" has space+space+tab+letters, all match AlphaSpace
    try std.testing.expectEqual(@as(?usize, 18), as.match("Hello World  \tMore"));
    try std.testing.expectEqual(@as(?usize, null), as.match("123"));
}

test "Enhanced atoms - Bin, Hex, Base64" {
    const b = bin();
    try std.testing.expectEqual(@as(?usize, 4), b.match("1010abc"));
    try std.testing.expectEqual(@as(?usize, null), b.match("2"));

    const h = hex();
    // "face123" - all 7 chars are hex digits
    try std.testing.expectEqual(@as(?usize, 7), h.match("face123"));
    try std.testing.expectEqual(@as(?usize, 3), h.match("ABC"));

    const b64 = base64();
    try std.testing.expectEqual(@as(?usize, 5), b64.match("aB3+="));
    try std.testing.expectEqual(@as(?usize, null), b64.match("@"));
}

test "Enhanced atoms - AlphaDigitSpace, AlphaDash, Punct" {
    const ads = alphaDigitSpace();
    try std.testing.expectEqual(@as(?usize, 13), ads.match("Hello World 1"));

    const ad = alphaDash();
    try std.testing.expectEqual(@as(?usize, 10), ad.match("test-case-123"));

    const p = punct();
    try std.testing.expectEqual(@as(?usize, 1), p.match(".txt"));
    // "://" has 3 punct chars (: / /)
    try std.testing.expectEqual(@as(?usize, 3), p.match("://"));
}
