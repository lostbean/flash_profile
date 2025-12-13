const std = @import("std");
const Allocator = std.mem.Allocator;

/// Dissimilarity value - either finite or infinity
pub const Dissimilarity = union(enum) {
    finite: f64,
    infinity,

    /// Compare two dissimilarity values
    pub fn lessThan(self: Dissimilarity, other: Dissimilarity) bool {
        return switch (self) {
            .infinity => false,
            .finite => |a| switch (other) {
                .infinity => true,
                .finite => |b| a < b,
            },
        };
    }

    /// Get max of two dissimilarity values
    pub fn max(self: Dissimilarity, other: Dissimilarity) Dissimilarity {
        return switch (self) {
            .infinity => .infinity,
            .finite => |a| switch (other) {
                .infinity => .infinity,
                .finite => |b| if (a >= b) .{ .finite = a } else .{ .finite = b },
            },
        };
    }
};

/// Dissimilarity matrix mapping string pairs to dissimilarity values
pub const DissimilarityMatrix = struct {
    /// Map from string pairs to dissimilarity
    /// We store indices instead of strings for efficiency
    data: std.AutoHashMap(StringPair, Dissimilarity),
    strings: []const []const u8,
    allocator: Allocator,

    /// Pair of string indices (normalized: i <= j)
    const StringPair = struct {
        i: usize,
        j: usize,
    };

    pub fn init(strings: []const []const u8, allocator: Allocator) !DissimilarityMatrix {
        return DissimilarityMatrix{
            .data = std.AutoHashMap(StringPair, Dissimilarity).init(allocator),
            .strings = strings,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DissimilarityMatrix) void {
        self.data.deinit();
    }

    /// Set dissimilarity for a pair of strings
    pub fn set(self: *DissimilarityMatrix, i: usize, j: usize, value: Dissimilarity) !void {
        const pair = normalizePair(i, j);
        try self.data.put(pair, value);
    }

    /// Get dissimilarity between two strings by index
    pub fn get(self: *const DissimilarityMatrix, i: usize, j: usize) Dissimilarity {
        // Diagonal is always 0
        if (i == j) {
            return .{ .finite = 0.0 };
        }

        const pair = normalizePair(i, j);
        return self.data.get(pair) orelse .infinity;
    }

    /// Normalize pair so i <= j
    fn normalizePair(i: usize, j: usize) StringPair {
        if (i <= j) {
            return .{ .i = i, .j = j };
        } else {
            return .{ .i = j, .j = i };
        }
    }
};

/// Node in the hierarchical clustering tree (dendrogram)
pub const HierarchyNode = union(enum) {
    /// Leaf node: contains index into original string array
    leaf: usize,

    /// Internal node: two children merged at some height
    internal: struct {
        left: *const HierarchyNode,
        right: *const HierarchyNode,
        height: f64, // dissimilarity at which clusters were merged
    },

    /// Get the height of this node (0 for leaves)
    pub fn getHeight(self: *const HierarchyNode) f64 {
        return switch (self.*) {
            .leaf => 0.0,
            .internal => |n| n.height,
        };
    }

    /// Recursively free the tree
    pub fn deinit(self: *const HierarchyNode, allocator: Allocator) void {
        switch (self.*) {
            .leaf => {
                // Just free the node itself
                allocator.destroy(self);
            },
            .internal => |n| {
                // Free children first
                n.left.deinit(allocator);
                n.right.deinit(allocator);
                // Then free this node
                allocator.destroy(self);
            },
        }
    }

    /// Collect all leaf indices in this subtree
    fn collectLeaves(self: *const HierarchyNode, list: *std.ArrayList(usize), allocator: Allocator) !void {
        switch (self.*) {
            .leaf => |idx| try list.append(allocator, idx),
            .internal => |n| {
                try n.left.collectLeaves(list, allocator);
                try n.right.collectLeaves(list, allocator);
            },
        }
    }
};

/// Result of hierarchical clustering
pub const Hierarchy = struct {
    root: *const HierarchyNode,
    num_strings: usize,
    allocator: Allocator,

    pub fn deinit(self: *Hierarchy) void {
        self.root.deinit(self.allocator);
    }
};

/// Partition result - clusters extracted from hierarchy
pub const Partition = struct {
    clusters: [][]usize, // Each cluster is array of string indices
    allocator: Allocator,

    pub fn deinit(self: *Partition) void {
        for (self.clusters) |cluster| {
            self.allocator.free(cluster);
        }
        self.allocator.free(self.clusters);
    }
};

/// Cluster representation during AHC
const Cluster = struct {
    node: *const HierarchyNode,
    indices: []usize, // String indices in this cluster
    allocator: Allocator,

    fn deinit(self: *Cluster) void {
        self.allocator.free(self.indices);
    }
};

/// Agglomerative Hierarchical Clustering with complete linkage
///
/// Implements the AHC algorithm from Figure 10 of the FlashProfile paper:
///
/// ```
/// func AHC(S, η):
///   C ← {{s} : s ∈ S}  // Start with singleton clusters
///   while |C| > 1:
///     (X, Y) ← argmin_{X,Y∈C, X≠Y} η̂(X, Y)
///     C ← C \ {X, Y} ∪ {X ∪ Y}
///     record merge(X, Y) at height η̂(X, Y)
///   return dendrogram
/// ```
///
/// Uses complete linkage: η̂(X, Y|A) = max{η(x,y) : x∈X, y∈Y}
///
/// Parameters:
///   - matrix: Dissimilarity matrix for the strings
///   - allocator: Memory allocator
///
/// Returns:
///   - Hierarchy with root node of dendrogram
pub fn ahc(matrix: *const DissimilarityMatrix, allocator: Allocator) !Hierarchy {
    const n = matrix.strings.len;

    if (n == 0) {
        return error.EmptyDataset;
    }

    // Special case: single element
    if (n == 1) {
        const node = try allocator.create(HierarchyNode);
        node.* = .{ .leaf = 0 };
        return Hierarchy{
            .root = node,
            .num_strings = 1,
            .allocator = allocator,
        };
    }

    // Initialize singleton clusters
    var clusters: std.ArrayList(Cluster) = .{};
    defer {
        for (clusters.items) |*cluster| {
            cluster.deinit();
        }
        clusters.deinit(allocator);
    }

    for (0..n) |i| {
        const node = try allocator.create(HierarchyNode);
        node.* = .{ .leaf = i };

        const indices = try allocator.alloc(usize, 1);
        indices[0] = i;

        try clusters.append(allocator, .{
            .node = node,
            .indices = indices,
            .allocator = allocator,
        });
    }

    // Main AHC loop: merge until only one cluster remains
    while (clusters.items.len > 1) {
        // Find pair with minimum complete-linkage distance
        const merge_result = try findMinLinkagePair(clusters.items, matrix, allocator);

        // Get the two clusters to merge
        const cluster_x = clusters.items[merge_result.idx_x];
        const cluster_y = clusters.items[merge_result.idx_y];

        // Create merged node
        const merged_node = try allocator.create(HierarchyNode);
        merged_node.* = .{
            .internal = .{
                .left = cluster_x.node,
                .right = cluster_y.node,
                .height = merge_result.linkage,
            },
        };

        // Merge indices
        const merged_indices = try allocator.alloc(usize, cluster_x.indices.len + cluster_y.indices.len);
        @memcpy(merged_indices[0..cluster_x.indices.len], cluster_x.indices);
        @memcpy(merged_indices[cluster_x.indices.len..], cluster_y.indices);

        // Remove old clusters and add merged cluster
        // Remove larger index first to avoid index shifting issues
        const remove_first = @max(merge_result.idx_x, merge_result.idx_y);
        const remove_second = @min(merge_result.idx_x, merge_result.idx_y);

        clusters.items[remove_first].deinit();
        _ = clusters.orderedRemove(remove_first);

        clusters.items[remove_second].deinit();
        _ = clusters.orderedRemove(remove_second);

        // Add merged cluster
        try clusters.append(allocator, .{
            .node = merged_node,
            .indices = merged_indices,
            .allocator = allocator,
        });
    }

    // Return the final cluster
    const final_cluster = clusters.items[0];
    const root = final_cluster.node;

    // Note: we don't deinit final_cluster.indices because ownership transfers to caller

    return Hierarchy{
        .root = root,
        .num_strings = n,
        .allocator = allocator,
    };
}

/// Result of finding minimum linkage pair
const MinLinkageResult = struct {
    idx_x: usize,
    idx_y: usize,
    linkage: f64,
};

/// Find the pair of clusters with minimum complete-linkage distance
fn findMinLinkagePair(
    clusters: []const Cluster,
    matrix: *const DissimilarityMatrix,
    allocator: Allocator,
) !MinLinkageResult {
    var min_linkage: Dissimilarity = .infinity;
    var best_x: usize = 0;
    var best_y: usize = 1;

    // Try all pairs
    for (clusters, 0..) |cluster_x, i| {
        for (clusters[i + 1 ..], i + 1..) |cluster_y, j| {
            const linkage = try completeLinkage(cluster_x, cluster_y, matrix, allocator);

            if (linkage.lessThan(min_linkage)) {
                min_linkage = linkage;
                best_x = i;
                best_y = j;
            }
        }
    }

    // Extract finite value
    const linkage_value = switch (min_linkage) {
        .finite => |v| v,
        .infinity => std.math.inf(f64),
    };

    return MinLinkageResult{
        .idx_x = best_x,
        .idx_y = best_y,
        .linkage = linkage_value,
    };
}

/// Complete linkage criterion: max dissimilarity between any pair
///
/// η̂(X, Y | A) = max{η(x,y) : x∈X, y∈Y}
///
/// Returns the maximum pairwise dissimilarity between elements of the two clusters.
pub fn completeLinkage(
    cluster_x: Cluster,
    cluster_y: Cluster,
    matrix: *const DissimilarityMatrix,
    allocator: Allocator,
) !Dissimilarity {
    _ = allocator; // Not needed but kept for consistency

    var max_diss: Dissimilarity = .{ .finite = 0.0 };

    for (cluster_x.indices) |i| {
        for (cluster_y.indices) |j| {
            const diss = matrix.get(i, j);
            max_diss = max_diss.max(diss);
        }
    }

    return max_diss;
}

/// Extract k clusters from hierarchy by cutting at appropriate height
///
/// Partitions the hierarchy into k clusters by iteratively splitting the
/// cluster with the largest height until k clusters are obtained.
///
/// Algorithm:
/// 1. Start with root as single active node
/// 2. While we have fewer than k clusters:
///    - Find active node with maximum height
///    - Replace it with its two children (if not a leaf)
/// 3. Return leaf indices from all active nodes
///
/// Parameters:
///   - hierarchy: Hierarchy from ahc()
///   - k: Number of clusters to extract (must be >= 1)
///   - allocator: Memory allocator
///
/// Returns:
///   - Partition with k (or fewer) clusters
pub fn partition(hierarchy: *const Hierarchy, k: usize, allocator: Allocator) !Partition {
    if (k == 0) {
        return error.InvalidK;
    }

    // Clamp k to valid range
    const actual_k = @min(k, hierarchy.num_strings);

    // Start with root as single active node
    var active_nodes: std.ArrayList(*const HierarchyNode) = .{};
    defer active_nodes.deinit(allocator);
    try active_nodes.append(allocator, hierarchy.root);

    // Split clusters until we have k
    while (active_nodes.items.len < actual_k) {
        // Find node with maximum height
        var max_height: f64 = -1.0;
        var max_idx: ?usize = null;

        for (active_nodes.items, 0..) |node, i| {
            const height = node.getHeight();
            if (height > max_height) {
                max_height = height;
                max_idx = i;
            }
        }

        if (max_idx) |idx| {
            const max_node = active_nodes.items[idx];

            // Check if it's a leaf (cannot split further)
            if (max_node.* == .leaf) {
                // All remaining nodes are leaves, stop
                break;
            }

            // Replace with children
            const internal = max_node.internal;
            _ = active_nodes.orderedRemove(idx);
            try active_nodes.append(allocator, internal.left);
            try active_nodes.append(allocator, internal.right);
        } else {
            // No valid node found, stop
            break;
        }
    }

    // Collect leaf indices from each active node
    var clusters: std.ArrayList([]usize) = .{};
    errdefer {
        for (clusters.items) |cluster| {
            allocator.free(cluster);
        }
        clusters.deinit(allocator);
    }

    for (active_nodes.items) |node| {
        var indices: std.ArrayList(usize) = .{};
        defer indices.deinit(allocator);

        try node.collectLeaves(&indices, allocator);

        const cluster = try allocator.dupe(usize, indices.items);
        try clusters.append(allocator, cluster);
    }

    return Partition{
        .clusters = try clusters.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "DissimilarityMatrix: basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def", "ghi" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // Diagonal should be 0
    try testing.expectEqual(Dissimilarity{ .finite = 0.0 }, matrix.get(0, 0));
    try testing.expectEqual(Dissimilarity{ .finite = 0.0 }, matrix.get(1, 1));

    // Set and get values
    try matrix.set(0, 1, .{ .finite = 5.0 });
    try testing.expectEqual(Dissimilarity{ .finite = 5.0 }, matrix.get(0, 1));
    try testing.expectEqual(Dissimilarity{ .finite = 5.0 }, matrix.get(1, 0)); // Symmetric

    // Set and get infinity
    try matrix.set(1, 2, .infinity);
    try testing.expectEqual(Dissimilarity.infinity, matrix.get(1, 2));
}

test "HierarchyNode: single element" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{"abc"};
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    try testing.expectEqual(@as(usize, 1), hier.num_strings);
    try testing.expectEqual(HierarchyNode.leaf, std.meta.activeTag(hier.root.*));
    try testing.expectEqual(@as(f64, 0.0), hier.root.getHeight());
}

test "HierarchyNode: two elements" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // Set dissimilarity
    try matrix.set(0, 1, .{ .finite = 10.0 });

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    try testing.expectEqual(@as(usize, 2), hier.num_strings);

    // Root should be internal node
    try testing.expectEqual(HierarchyNode.internal, std.meta.activeTag(hier.root.*));
    try testing.expectEqual(@as(f64, 10.0), hier.root.getHeight());

    // Children should be leaves
    const internal = hier.root.internal;
    try testing.expectEqual(HierarchyNode.leaf, std.meta.activeTag(internal.left.*));
    try testing.expectEqual(HierarchyNode.leaf, std.meta.activeTag(internal.right.*));
}

test "HierarchyNode: three elements with known structure" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create three strings where 0 and 1 are similar, 2 is different
    const strings = [_][]const u8{ "abc", "abd", "xyz" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // 0-1 are close (should merge first)
    try matrix.set(0, 1, .{ .finite = 2.0 });
    // 0-2 are far
    try matrix.set(0, 2, .{ .finite = 20.0 });
    // 1-2 are far
    try matrix.set(1, 2, .{ .finite = 20.0 });

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    try testing.expectEqual(@as(usize, 3), hier.num_strings);

    // Root should merge the (0,1) cluster with 2 at height 20.0
    try testing.expectEqual(HierarchyNode.internal, std.meta.activeTag(hier.root.*));
    try testing.expectEqual(@as(f64, 20.0), hier.root.getHeight());

    // One child should be internal (0,1 merged at 2.0)
    const root_internal = hier.root.internal;
    const has_internal_child = root_internal.left.* == .internal or root_internal.right.* == .internal;
    try testing.expect(has_internal_child);
}

test "Partition: extract single cluster" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    try matrix.set(0, 1, .{ .finite = 10.0 });

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    var part = try partition(&hier, 1, allocator);
    defer part.deinit();

    // Should have 1 cluster with 2 elements
    try testing.expectEqual(@as(usize, 1), part.clusters.len);
    try testing.expectEqual(@as(usize, 2), part.clusters[0].len);
}

test "Partition: extract two clusters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    try matrix.set(0, 1, .{ .finite = 10.0 });

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    var part = try partition(&hier, 2, allocator);
    defer part.deinit();

    // Should have 2 clusters with 1 element each
    try testing.expectEqual(@as(usize, 2), part.clusters.len);
    try testing.expectEqual(@as(usize, 1), part.clusters[0].len);
    try testing.expectEqual(@as(usize, 1), part.clusters[1].len);
}

test "Partition: extract three clusters from three elements" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "abd", "xyz" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    try matrix.set(0, 1, .{ .finite = 2.0 });
    try matrix.set(0, 2, .{ .finite = 20.0 });
    try matrix.set(1, 2, .{ .finite = 20.0 });

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    var part = try partition(&hier, 3, allocator);
    defer part.deinit();

    // Should have 3 clusters with 1 element each
    try testing.expectEqual(@as(usize, 3), part.clusters.len);
    try testing.expectEqual(@as(usize, 1), part.clusters[0].len);
    try testing.expectEqual(@as(usize, 1), part.clusters[1].len);
    try testing.expectEqual(@as(usize, 1), part.clusters[2].len);
}

test "Partition: k larger than number of elements" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    try matrix.set(0, 1, .{ .finite = 10.0 });

    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    // Ask for 10 clusters but only have 2 elements
    var part = try partition(&hier, 10, allocator);
    defer part.deinit();

    // Should get at most 2 clusters
    try testing.expect(part.clusters.len <= 2);
}

test "Complete linkage: two singletons" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "abc", "def" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    try matrix.set(0, 1, .{ .finite = 5.0 });

    // Create singleton clusters
    const node0 = try allocator.create(HierarchyNode);
    node0.* = .{ .leaf = 0 };
    const indices0 = try allocator.alloc(usize, 1);
    indices0[0] = 0;

    const node1 = try allocator.create(HierarchyNode);
    node1.* = .{ .leaf = 1 };
    const indices1 = try allocator.alloc(usize, 1);
    indices1[0] = 1;

    var cluster0 = Cluster{
        .node = node0,
        .indices = indices0,
        .allocator = allocator,
    };

    var cluster1 = Cluster{
        .node = node1,
        .indices = indices1,
        .allocator = allocator,
    };

    // Complete linkage should return 5.0
    const linkage = try completeLinkage(cluster0, cluster1, &matrix, allocator);
    try testing.expectEqual(Dissimilarity{ .finite = 5.0 }, linkage);

    // Cleanup
    cluster0.deinit();
    cluster1.deinit();
    allocator.destroy(node0);
    allocator.destroy(node1);
}

test "Complete linkage: max of multiple pairs" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const strings = [_][]const u8{ "a", "b", "c", "d" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // Set up dissimilarities
    try matrix.set(0, 2, .{ .finite = 3.0 });
    try matrix.set(0, 3, .{ .finite = 7.0 }); // Max
    try matrix.set(1, 2, .{ .finite = 4.0 });
    try matrix.set(1, 3, .{ .finite = 5.0 });

    // Cluster {0, 1} and {2, 3}
    const node01 = try allocator.create(HierarchyNode);
    node01.* = .{ .leaf = 0 }; // Doesn't matter for this test
    const indices01 = try allocator.alloc(usize, 2);
    indices01[0] = 0;
    indices01[1] = 1;

    const node23 = try allocator.create(HierarchyNode);
    node23.* = .{ .leaf = 2 }; // Doesn't matter for this test
    const indices23 = try allocator.alloc(usize, 2);
    indices23[0] = 2;
    indices23[1] = 3;

    var cluster01 = Cluster{
        .node = node01,
        .indices = indices01,
        .allocator = allocator,
    };

    var cluster23 = Cluster{
        .node = node23,
        .indices = indices23,
        .allocator = allocator,
    };

    // Complete linkage should return max = 7.0
    const linkage = try completeLinkage(cluster01, cluster23, &matrix, allocator);
    try testing.expectEqual(Dissimilarity{ .finite = 7.0 }, linkage);

    // Cleanup
    cluster01.deinit();
    cluster23.deinit();
    allocator.destroy(node01);
    allocator.destroy(node23);
}

test "Dissimilarity: comparison" {
    const testing = std.testing;

    const a = Dissimilarity{ .finite = 5.0 };
    const b = Dissimilarity{ .finite = 10.0 };
    const inf: Dissimilarity = .infinity;

    try testing.expect(a.lessThan(b));
    try testing.expect(!b.lessThan(a));
    try testing.expect(a.lessThan(inf));
    try testing.expect(!inf.lessThan(b));
    try testing.expect(!a.lessThan(a));
}

test "Dissimilarity: max" {
    const testing = std.testing;

    const a = Dissimilarity{ .finite = 5.0 };
    const b = Dissimilarity{ .finite = 10.0 };
    const inf: Dissimilarity = .infinity;

    const max_ab = a.max(b);
    try testing.expectEqual(Dissimilarity{ .finite = 10.0 }, max_ab);

    const max_ba = b.max(a);
    try testing.expectEqual(Dissimilarity{ .finite = 10.0 }, max_ba);

    const max_a_inf = a.max(inf);
    const expected_inf: Dissimilarity = .infinity;
    try testing.expectEqual(expected_inf, max_a_inf);

    const max_inf_b = inf.max(b);
    try testing.expectEqual(expected_inf, max_inf_b);
}
