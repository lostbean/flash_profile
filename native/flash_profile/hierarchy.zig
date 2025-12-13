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
    id: usize, // Unique ID for this cluster
    node: *const HierarchyNode,
    indices: []usize, // String indices in this cluster
    allocator: Allocator,

    fn deinit(self: *Cluster) void {
        self.allocator.free(self.indices);
    }
};

/// Pair of cluster IDs (normalized: i < j)
const ClusterPair = struct {
    i: usize,
    j: usize,

    fn init(a: usize, b: usize) ClusterPair {
        if (a < b) {
            return .{ .i = a, .j = b };
        } else {
            return .{ .i = b, .j = a };
        }
    }
};

/// Entry in the linkage priority queue
const LinkageEntry = struct {
    pair: ClusterPair,
    linkage: f64,

    fn lessThan(_: void, a: LinkageEntry, b: LinkageEntry) std.math.Order {
        // Min-heap: smaller linkage values have higher priority
        if (a.linkage < b.linkage) return .lt;
        if (a.linkage > b.linkage) return .gt;
        return .eq;
    }
};

/// Cache for storing and updating linkage values between clusters
const LinkageCache = struct {
    // Map from cluster pair to linkage value
    cache: std.AutoHashMap(ClusterPair, f64),
    // Priority queue of linkage entries (min-heap)
    heap: std.PriorityQueue(LinkageEntry, void, LinkageEntry.lessThan),
    allocator: Allocator,

    fn init(allocator: Allocator) LinkageCache {
        return .{
            .cache = std.AutoHashMap(ClusterPair, f64).init(allocator),
            .heap = std.PriorityQueue(LinkageEntry, void, LinkageEntry.lessThan).init(allocator, {}),
            .allocator = allocator,
        };
    }

    fn deinit(self: *LinkageCache) void {
        self.cache.deinit();
        self.heap.deinit();
    }

    /// Add a linkage value to the cache and heap
    fn put(self: *LinkageCache, cluster_i: usize, cluster_j: usize, linkage: f64) !void {
        const pair = ClusterPair.init(cluster_i, cluster_j);
        try self.cache.put(pair, linkage);
        try self.heap.add(.{ .pair = pair, .linkage = linkage });
    }

    /// Get linkage value from cache
    fn get(self: *const LinkageCache, cluster_i: usize, cluster_j: usize) ?f64 {
        const pair = ClusterPair.init(cluster_i, cluster_j);
        return self.cache.get(pair);
    }

    /// Remove a cluster from the cache (when it gets merged)
    fn removeCluster(self: *LinkageCache, cluster_id: usize, all_cluster_ids: []const usize) !void {
        // Remove all pairs involving this cluster
        for (all_cluster_ids) |other_id| {
            if (other_id != cluster_id) {
                const pair = ClusterPair.init(cluster_id, other_id);
                _ = self.cache.remove(pair);
            }
        }
    }

    /// Find the minimum valid linkage pair
    /// Returns null if no valid pair exists
    fn findMin(self: *LinkageCache) ?struct { i: usize, j: usize, linkage: f64 } {
        // Keep popping from heap until we find a valid entry
        while (self.heap.removeOrNull()) |entry| {
            // Check if this pair is still in the cache (not stale)
            if (self.cache.get(entry.pair)) |cached_linkage| {
                if (cached_linkage == entry.linkage) {
                    return .{
                        .i = entry.pair.i,
                        .j = entry.pair.j,
                        .linkage = entry.linkage,
                    };
                }
            }
        }
        return null;
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

    // Initialize singleton clusters with unique IDs
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
            .id = i, // Initial cluster ID is the string index
            .node = node,
            .indices = indices,
            .allocator = allocator,
        });
    }

    // Initialize linkage cache with all pairwise linkages
    var cache = LinkageCache.init(allocator);
    defer cache.deinit();

    // Map from cluster ID to cluster index in the clusters array
    var cluster_id_to_idx = std.AutoHashMap(usize, usize).init(allocator);
    defer cluster_id_to_idx.deinit();

    for (clusters.items, 0..) |cluster, idx| {
        try cluster_id_to_idx.put(cluster.id, idx);
    }

    // Compute all initial pairwise linkages
    for (0..clusters.items.len) |i| {
        for (i + 1..clusters.items.len) |j| {
            const cluster_i = clusters.items[i];
            const cluster_j = clusters.items[j];
            const linkage = try completeLinkage(cluster_i, cluster_j, matrix, allocator);

            // Only cache finite linkages
            if (linkage == .finite) {
                try cache.put(cluster_i.id, cluster_j.id, linkage.finite);
            }
        }
    }

    // Next cluster ID for merged clusters
    var next_cluster_id: usize = n;

    // Main AHC loop: merge until only one cluster remains
    while (clusters.items.len > 1) {
        // Find pair with minimum complete-linkage distance from cache
        const min_pair = cache.findMin() orelse return error.NoValidMerge;

        // Map cluster IDs back to indices
        const idx_x = cluster_id_to_idx.get(min_pair.i) orelse return error.ClusterNotFound;
        const idx_y = cluster_id_to_idx.get(min_pair.j) orelse return error.ClusterNotFound;

        // Get the two clusters to merge
        const cluster_x = clusters.items[idx_x];
        const cluster_y = clusters.items[idx_y];

        // Create merged node
        const merged_node = try allocator.create(HierarchyNode);
        merged_node.* = .{
            .internal = .{
                .left = cluster_x.node,
                .right = cluster_y.node,
                .height = min_pair.linkage,
            },
        };

        // Merge indices
        const merged_indices = try allocator.alloc(usize, cluster_x.indices.len + cluster_y.indices.len);
        @memcpy(merged_indices[0..cluster_x.indices.len], cluster_x.indices);
        @memcpy(merged_indices[cluster_x.indices.len..], cluster_y.indices);

        // Collect all current cluster IDs for cache updates
        var all_cluster_ids = try allocator.alloc(usize, clusters.items.len);
        defer allocator.free(all_cluster_ids);
        for (clusters.items, 0..) |cluster, i| {
            all_cluster_ids[i] = cluster.id;
        }

        // Remove old clusters from cache
        try cache.removeCluster(cluster_x.id, all_cluster_ids);
        try cache.removeCluster(cluster_y.id, all_cluster_ids);

        // Remove old clusters from ID map
        _ = cluster_id_to_idx.remove(cluster_x.id);
        _ = cluster_id_to_idx.remove(cluster_y.id);

        // Remove old clusters from list
        // Remove larger index first to avoid index shifting issues
        const remove_first = @max(idx_x, idx_y);
        const remove_second = @min(idx_x, idx_y);

        clusters.items[remove_first].deinit();
        _ = clusters.orderedRemove(remove_first);

        clusters.items[remove_second].deinit();
        _ = clusters.orderedRemove(remove_second);

        // Create merged cluster with new ID
        const merged_cluster = Cluster{
            .id = next_cluster_id,
            .node = merged_node,
            .indices = merged_indices,
            .allocator = allocator,
        };
        next_cluster_id += 1;

        // Add merged cluster
        const merged_idx = clusters.items.len;
        try clusters.append(allocator, merged_cluster);
        try cluster_id_to_idx.put(merged_cluster.id, merged_idx);

        // Update cache with new linkages using incremental formula:
        // η(Z, W) = max(η(X, W), η(Y, W))
        for (clusters.items) |other_cluster| {
            if (other_cluster.id != merged_cluster.id) {
                // Get cached linkages for X-W and Y-W
                const linkage_xw = cache.get(cluster_x.id, other_cluster.id);
                const linkage_yw = cache.get(cluster_y.id, other_cluster.id);

                // If both are available, use incremental formula
                if (linkage_xw != null and linkage_yw != null) {
                    const new_linkage = @max(linkage_xw.?, linkage_yw.?);
                    try cache.put(merged_cluster.id, other_cluster.id, new_linkage);
                } else {
                    // Fallback: compute from scratch
                    const linkage = try completeLinkage(merged_cluster, other_cluster, matrix, allocator);
                    if (linkage == .finite) {
                        try cache.put(merged_cluster.id, other_cluster.id, linkage.finite);
                    }
                }
            }
        }

        // Update cluster ID to index mapping for remaining clusters
        cluster_id_to_idx.clearRetainingCapacity();
        for (clusters.items, 0..) |cluster, idx| {
            try cluster_id_to_idx.put(cluster.id, idx);
        }
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
        .id = 0,
        .node = node0,
        .indices = indices0,
        .allocator = allocator,
    };

    var cluster1 = Cluster{
        .id = 1,
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
        .id = 0,
        .node = node01,
        .indices = indices01,
        .allocator = allocator,
    };

    var cluster23 = Cluster{
        .id = 1,
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

test "LinkageCache: basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cache = LinkageCache.init(allocator);
    defer cache.deinit();

    // Add some linkage values
    try cache.put(0, 1, 5.0);
    try cache.put(0, 2, 10.0);
    try cache.put(1, 2, 3.0);

    // Test retrieval
    try testing.expectEqual(@as(?f64, 5.0), cache.get(0, 1));
    try testing.expectEqual(@as(?f64, 5.0), cache.get(1, 0)); // Symmetric
    try testing.expectEqual(@as(?f64, 10.0), cache.get(0, 2));
    try testing.expectEqual(@as(?f64, 3.0), cache.get(1, 2));

    // Test findMin - should return minimum linkage
    const min = cache.findMin();
    try testing.expect(min != null);
    try testing.expectEqual(@as(f64, 3.0), min.?.linkage);
    try testing.expect((min.?.i == 1 and min.?.j == 2) or (min.?.i == 2 and min.?.j == 1));
}

test "LinkageCache: larger dataset with incremental updates" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a larger dataset to test the cache optimization
    const strings = [_][]const u8{ "a", "b", "c", "d", "e" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // Set up a pattern where (a,b) are close
    try matrix.set(0, 1, .{ .finite = 1.0 }); // a-b: close
    try matrix.set(0, 2, .{ .finite = 5.0 }); // a-c
    try matrix.set(0, 3, .{ .finite = 8.0 }); // a-d
    try matrix.set(0, 4, .{ .finite = 10.0 }); // a-e
    try matrix.set(1, 2, .{ .finite = 6.0 }); // b-c
    try matrix.set(1, 3, .{ .finite = 9.0 }); // b-d
    try matrix.set(1, 4, .{ .finite = 11.0 }); // b-e
    try matrix.set(2, 3, .{ .finite = 2.0 }); // c-d: close
    try matrix.set(2, 4, .{ .finite = 12.0 }); // c-e
    try matrix.set(3, 4, .{ .finite = 13.0 }); // d-e

    // Run AHC and verify it completes successfully
    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    // Verify basic properties
    try testing.expectEqual(@as(usize, 5), hier.num_strings);
    try testing.expectEqual(HierarchyNode.internal, std.meta.activeTag(hier.root.*));

    // The algorithm should produce a valid dendrogram
    // First merge should be (a,b) at height 1.0 or (c,d) at height 2.0
    try testing.expect(hier.root.getHeight() > 0.0);
}

test "hierarchy: large dataset clustering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test with 50+ elements using synthetic data
    const n: usize = 50;
    var strings_array: [n][]const u8 = undefined;
    var string_buffers: [n][10]u8 = undefined;

    // Generate synthetic string data
    for (0..n) |i| {
        const buf = &string_buffers[i];
        const str = std.fmt.bufPrint(buf, "str_{d}", .{i}) catch unreachable;
        strings_array[i] = str;
    }

    const strings: []const []const u8 = &strings_array;
    var matrix = try DissimilarityMatrix.init(strings, allocator);
    defer matrix.deinit();

    // Set up dissimilarities: distance proportional to index difference
    // This creates natural clusters of nearby indices
    for (0..n) |i| {
        for (i + 1..n) |j| {
            const diff = j - i;
            const dissim = @as(f64, @floatFromInt(diff));
            try matrix.set(i, j, .{ .finite = dissim });
        }
    }

    // Build hierarchy
    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    // Verify hierarchy structure is valid
    try testing.expectEqual(@as(usize, n), hier.num_strings);
    try testing.expectEqual(HierarchyNode.internal, std.meta.activeTag(hier.root.*));
    try testing.expect(hier.root.getHeight() > 0.0);

    // Test partition extraction at various k values
    for ([_]usize{ 1, 5, 10, 25, 50 }) |k| {
        var part = try partition(&hier, k, allocator);
        defer part.deinit();

        // Verify we get at most k clusters
        try testing.expect(part.clusters.len <= k);
        try testing.expect(part.clusters.len >= 1);

        // Verify all elements are accounted for
        var total_elements: usize = 0;
        for (part.clusters) |cluster| {
            total_elements += cluster.len;
        }
        try testing.expectEqual(n, total_elements);

        // Verify no empty clusters
        for (part.clusters) |cluster| {
            try testing.expect(cluster.len > 0);
        }
    }
}

test "hierarchy: all equal dissimilarities" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test edge case where all pairs have same dissimilarity
    const strings = [_][]const u8{ "a", "b", "c", "d", "e" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // Set all pairwise dissimilarities to the same value
    const uniform_distance: f64 = 5.0;
    for (0..strings.len) |i| {
        for (i + 1..strings.len) |j| {
            try matrix.set(i, j, .{ .finite = uniform_distance });
        }
    }

    // Build hierarchy - any merge order should be valid
    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    // Verify basic properties
    try testing.expectEqual(@as(usize, strings.len), hier.num_strings);
    try testing.expectEqual(HierarchyNode.internal, std.meta.activeTag(hier.root.*));

    // All internal nodes should have the same height (uniform_distance)
    // since all merges happen at the same dissimilarity
    try testing.expectEqual(uniform_distance, hier.root.getHeight());

    // Test that we can partition into any number of clusters
    for (1..strings.len + 1) |k| {
        var part = try partition(&hier, k, allocator);
        defer part.deinit();

        // Verify partition is valid
        try testing.expect(part.clusters.len <= k);
        try testing.expect(part.clusters.len >= 1);

        // Verify all elements are present
        var total: usize = 0;
        for (part.clusters) |cluster| {
            total += cluster.len;
        }
        try testing.expectEqual(strings.len, total);
    }
}

test "hierarchy: handles infinite dissimilarities" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test when some pairs have infinite dissimilarity
    // Matrix must be fully connected with finite edges for clustering to complete
    const strings = [_][]const u8{ "a", "b", "c", "d" };
    var matrix = try DissimilarityMatrix.init(&strings, allocator);
    defer matrix.deinit();

    // Create two tight groups with large distance between them
    // Group 1: {a, b} - close together
    try matrix.set(0, 1, .{ .finite = 1.0 });

    // Group 2: {c, d} - close together
    try matrix.set(2, 3, .{ .finite = 1.5 });

    // Between-group distances: very large but finite
    try matrix.set(0, 2, .{ .finite = 100.0 });
    try matrix.set(0, 3, .{ .finite = 100.0 });
    try matrix.set(1, 2, .{ .finite = 100.0 });
    try matrix.set(1, 3, .{ .finite = 100.0 });

    // Build hierarchy - should merge within groups first, then merge groups
    var hier = try ahc(&matrix, allocator);
    defer hier.deinit();

    // Verify basic properties
    try testing.expectEqual(@as(usize, 4), hier.num_strings);
    try testing.expectEqual(HierarchyNode.internal, std.meta.activeTag(hier.root.*));

    // Root merge should happen at the large between-group distance
    try testing.expectEqual(@as(f64, 100.0), hier.root.getHeight());

    // Extract 2 clusters - should separate the two groups
    var part = try partition(&hier, 2, allocator);
    defer part.deinit();

    try testing.expectEqual(@as(usize, 2), part.clusters.len);

    // Each cluster should have 2 elements
    try testing.expectEqual(@as(usize, 2), part.clusters[0].len);
    try testing.expectEqual(@as(usize, 2), part.clusters[1].len);

    // Now test with some truly infinite dissimilarities
    // We'll use a fully connected subgraph but leave one edge undefined
    const strings2 = [_][]const u8{ "x", "y", "z" };
    var matrix2 = try DissimilarityMatrix.init(&strings2, allocator);
    defer matrix2.deinit();

    // All pairs have finite dissimilarity
    try matrix2.set(0, 1, .{ .finite = 2.0 });
    try matrix2.set(1, 2, .{ .finite = 3.0 });
    // Leave (0,2) unset - defaults to infinity
    // But when we merge {0,1}, the linkage to {2} will be max(d(0,2), d(1,2)) = max(inf, 3.0) = inf
    // So we need to set it:
    try matrix2.set(0, 2, .{ .finite = 5.0 });

    var hier2 = try ahc(&matrix2, allocator);
    defer hier2.deinit();

    try testing.expectEqual(@as(usize, 3), hier2.num_strings);
    try testing.expect(hier2.root.getHeight() > 0.0);
}
