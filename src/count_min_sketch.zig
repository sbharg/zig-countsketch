const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const KWiseHash = @import("k_wise_hash.zig").KWiseHash;

/// CountMinSketchBase is a base data structure used for CountMinSketch.
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer with width less than 32).
/// - CounterType: The type for the counters (e.g., i32, i64). Must be signed.
pub fn CountMinSketchBase(comptime KeyType: type, comptime CounterType: type) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned or @typeInfo(KeyType).int.bits > 32) {
        @compileError("Unsupported KeyType for CountMinSketchBasse. KeyType must be u32 or less.");
    }
    if (@typeInfo(CounterType).int.signedness != .signed) {
        @compileError("CounterType must be signed (e.g., i32, i64)");
    }

    return struct {
        const Self: type = @This();
        const HashFn: type = KWiseHash(KeyType);

        /// The width of the CountSketch vector.
        w: usize,
        allocator: Allocator,
        counters: []CounterType,
        index_hash_base: HashFn,

        /// Initializes the CountSketchBase with specified width (w).
        ///
        /// Parameters:
        /// - allocator: The allocator to use for memory allocation.
        /// - w: The width of the CountSketch vector (must be > 0).
        /// - seed: The seed for the random number generator.
        fn init(allocator: Allocator, w: usize, seed: u64) !Self {
            if (w == 0) {
                const fmt = "CountMinSketchBase width (w) must be greater than 0";
                if (!builtin.is_test) {
                    std.log.err(fmt, .{});
                } else {
                    std.log.warn(fmt, .{});
                }
                return error.InvalidArgument;
            }

            var self = Self{
                .w = w,
                .allocator = allocator,
                .counters = undefined,
                .index_hash_base = undefined,
            };

            self.counters = try allocator.alloc(CounterType, w);
            @memset(self.counters, 0);
            errdefer allocator.free(self.counters);

            var prng = std.Random.DefaultPrng.init(seed);
            const rand = prng.random();
            // Pairwise independent hash function suffices
            self.index_hash_base = try HashFn.init(allocator, 2, rand.int(u64));
            errdefer self.index_hash_base.deinit();

            return self;
        }

        fn deinit(self: *Self) void {
            self.index_hash_base.deinit();
            self.allocator.free(self.counters);
            self.* = undefined;
        }

        /// Computes the index hash for the given key.
        /// Guarantees that the index is in the range [0, w).
        fn index_hash(self: *Self, key: KeyType) usize {
            const index_hash_val: u64 = self.index_hash_base.hash(key);
            return @intCast(index_hash_val % @as(u64, self.w));
        }

        /// Updates the sketch with a delta for the specified item.
        ///
        /// Parameters:
        /// - key: The item to update.
        /// - delta: The delta to add to the item's frequency.
        fn update(self: *Self, key: KeyType, delta: CounterType) void {
            if (delta == 0) return;

            const index: usize = self.index_hash(key);
            self.counters[index] += delta;
        }
    };
}

/// CountMinSketch data strucutre for unsigned integer keys.
///
/// Estimates item frequencies for specified KeyType and CounterType.
///
/// This data structure is only guaranteed to work in the non-negative turnstile
/// stream model, i.e. the actual frequencies of all keys must be
/// guaranteed to always be >= 0 throughout all stream updates.
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer with width less than 32).
/// - CounterType: The type for the counters (e.g., i32, i64). Must be signed.
/// - d (depth): Number of hash functions/rows.
/// - w (width): Number of counters per hash function/columns.
pub fn CountMinSketch(comptime KeyType: type, comptime CounterType: type) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned or @typeInfo(KeyType).int.bits > 32) {
        @compileError("Unsupported KeyType for CountMinSketch. KeyType must be u32 or less.");
    }
    if (@typeInfo(CounterType).int.signedness != .signed) {
        @compileError("CounterType must be signed (e.g., i32, i64)");
    }

    return struct {
        const Self: type = @This();
        const CMSBase: type = CountMinSketchBase(KeyType, CounterType);

        w: usize,
        d: usize,
        table: []CMSBase,
        allocator: Allocator,

        /// Initializes the CountMinSketch with specified epsilon and delta
        /// params. Sets width to ceil(e / eps) and depth to ceil(ln(1/delta)).
        /// Gurantees that an estimate \hat{x}_i satisfies
        ///  - \hat{x}_i >= x_i
        ///  - With probability at least 1 - delta, \hat{x}_i <= x_i + eps ||x||_1
        ///
        /// Parameters:
        /// - allocator: The allocator to use for memory allocation.
        /// - eps: The error tolerance for the CountSketch.
        /// - delta: The probability of failure.
        /// - seed: The seed for the random number generator.
        pub fn initWithParams(allocator: Allocator, eps: f64, delta: f64, seed: u64) !Self {
            const w: usize = @intFromFloat(@ceil(std.math.e / eps));
            const d: usize = @intFromFloat(@ceil(std.math.log(f64, std.math.e, 1.0 / delta)));
            return try Self.init(allocator, d, w, seed);
        }

        /// Initializes the CountMinSketch with specified depth (d) and width (w).
        ///
        /// Parameters:
        /// - allocator: The allocator to use for memory allocation.
        /// - d: The depth of the CountSketch (must be > 0).
        /// - w: The width of the CountSketch (must be > 0).
        /// - seed: The seed for the random number generator.
        pub fn init(allocator: Allocator, d: usize, w: usize, seed: u64) !Self {
            if (d == 0) {
                const fmt = "CountMinSketch depth (d) must be greater than 0";
                if (!builtin.is_test) {
                    std.log.err(fmt, .{});
                } else {
                    std.log.warn(fmt, .{});
                }
                return error.InvalidArgument;
            }
            if (w == 0) {
                const fmt = "CountMinSketch width (w) must be greater than 0";
                if (!builtin.is_test) {
                    std.log.err(fmt, .{});
                } else {
                    std.log.warn(fmt, .{});
                }
                return error.InvalidArgument;
            }

            var self = Self{
                .w = w,
                .d = d,
                .table = undefined,
                .allocator = allocator,
            };

            self.table = try self.allocator.alloc(CMSBase, d);

            var prng = std.Random.DefaultPrng.init(seed);
            const rand = prng.random();
            for (self.table) |*table| {
                table.* = try CMSBase.init(allocator, w, rand.int(u64));
            }
            errdefer for (self.table) |*table| {
                table.deinit();
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            for (self.table) |*table| {
                table.deinit();
            }
            self.allocator.free(self.table);
            self.* = undefined;
        }

        /// Updates the CountMinSketch with a delta for the specified key.
        ///
        /// Parameters:
        /// - key: The ket to update.
        /// - delta: The delta to add to the item's frequency.
        pub fn update(self: *Self, key: KeyType, delta: CounterType) void {
            for (0..self.table.len) |i| {
                self.table[i].update(key, delta);
            }
        }

        /// Estimates the frequency of the specified key.
        ///
        /// Parameters:
        /// - key: The item to estimate.
        pub fn query(self: *Self, key: KeyType) !CounterType {
            var estimate = self.table[0].counters[self.table[0].index_hash(key)];

            for (1..self.table.len) |i| {
                const index: usize = self.table[i].index_hash(key);
                estimate = @min(self.table[i].counters[index], estimate);
            }

            return estimate;
        }
    };
}

test "CountMinSketch (uint) basic usage" {
    const CMS = CountMinSketch(u32, i64);
    const allocator = std.testing.allocator;

    var sketch = try CMS.init(allocator, 5, 10, std.testing.random_seed);
    defer sketch.deinit();

    const item1: u32 = 10001;
    const item2: u32 = 20002;

    sketch.update(item1, 20);
    sketch.update(item2, 50);
    sketch.update(item2, -30);

    const estimate1 = try sketch.query(item1);
    const estimate2 = try sketch.query(item2);
    std.debug.print("\n-- CountMinSketch (u32 keys) --\n", .{});
    std.debug.print(" - Item {d}: {} (Actual 20)\n", .{ item1, estimate1 });
    std.debug.print(" - Item {d}: {} (Actual 20)\n", .{ item2, estimate2 });

    try std.testing.expect(true); // Passes if it compiles
}

test "CountMinSketch (uint) basic usage with params" {
    const CMS = CountMinSketch(u32, i64);
    const allocator = std.testing.allocator;

    const eps: f64 = 0.125;
    const delta: f64 = 0.125;
    var sketch = try CMS.initWithParams(allocator, eps, delta, std.testing.random_seed);
    defer sketch.deinit();

    const item1: u32 = 10001;
    const item2: u32 = 20002;

    sketch.update(item1, 20);
    sketch.update(item2, 50);
    sketch.update(item2, -30);

    const estimate1 = try sketch.query(item1);
    const estimate2 = try sketch.query(item2);
    std.debug.print("\n-- CountMinSketch (u32 keys) --\n", .{});
    std.debug.print(" - Item {d}: {} (Actual 20)\n", .{ item1, estimate1 });
    std.debug.print(" - Item {d}: {} (Actual 20)\n", .{ item2, estimate2 });

    try std.testing.expect(true); // Passes if it compiles
}
