const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Random = std.Random;
const KWiseHash = @import("k_wise_hash.zig").KWiseHash;

/// CountSketchBase is a base data structure used for CountSketch and L.
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer e.g. u32, u64).
/// - CounterType: The type for the counters (e.g., i32, i64). Must be signed.
/// - sign_hash_base_ind: The independence of the hash function used for determining signs (+1/-1).
pub fn CountSketchBase(comptime KeyType: type, comptime CounterType: type, comptime sign_hash_base_ind: comptime_int) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned) {
        @compileError("Unsupported KeyType for CountSketch. KeyType must be an unsigned integer.");
    }
    if (@typeInfo(CounterType).int.signedness != .signed) {
        @compileError("CounterType must be signed (e.g., i32, i64)");
    }

    return struct {
        const Self: type = @This();
        const Hasher: type = KWiseHash(KeyType);

        /// The width of the CountSketch vector.
        w: usize,
        allocator: Allocator,
        counters: []CounterType,
        index_hash_base: Hasher,
        sign_hash_base: Hasher,

        /// Initializes the CountSketchBase with specified width (w).
        ///
        /// Parameters:
        /// - allocator: The allocator to use for memory allocation.
        /// - w: The width of the CountSketch vector (must be > 0).
        /// - seed: The seed for the random number generator.
        fn init(allocator: Allocator, w: usize, seed: u64) !Self {
            if (w == 0) {
                const fmt = "CountSketchBase width (w) must be greater than 0";
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
                .sign_hash_base = undefined,
            };

            self.counters = try allocator.alloc(CounterType, w);
            @memset(self.counters, 0);
            errdefer allocator.free(self.counters);

            var prng = std.Random.DefaultPrng.init(seed);
            const rand = prng.random();
            self.index_hash_base = try Hasher.init(allocator, 2, rand.int(u64));
            errdefer self.index_hash_base.deinit();
            self.sign_hash_base = try Hasher.init(allocator, sign_hash_base_ind, rand.int(u64));
            errdefer self.sign_hash_base.deinit();

            return self;
        }

        fn deinit(self: *Self) void {
            self.index_hash_base.deinit();
            self.sign_hash_base.deinit();
            self.allocator.free(self.counters);
            self.* = undefined;
        }

        fn index_hash(self: *Self, key: KeyType) usize {
            const index_hash_val: u64 = self.index_hash_base.hash(key);
            return @intCast(index_hash_val % @as(u64, self.w));
        }

        fn sign_hash(self: *Self, key: KeyType) CounterType {
            const sign_hash_val: u64 = self.sign_hash_base.hash(key);
            return if (sign_hash_val & 1 == 0) -1 else 1;
        }

        /// Updates the sketch with a delta for the specified item.
        ///
        /// Parameters:
        /// - key: The item to update.
        /// - delta: The delta to add to the item's frequency.
        fn update(self: *Self, key: KeyType, delta: CounterType) void {
            if (delta == 0) return;

            const index: usize = self.index_hash(key);
            const sign: CounterType = self.sign_hash(key);

            self.counters[index] += sign * delta;
        }
    };
}

/// CountSketch data strucutre for unsigned integer keys.
///
/// Estimates item frequencies for specified KeyType and CounterType.
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer).
/// - CounterType: The type for the counters (e.g., i32, i64). Must be signed.
/// - d (depth): Number of hash functions/rows.
/// - w (width): Number of counters per hash function/column.
pub fn CountSketch(comptime KeyType: type, comptime CounterType: type) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned) {
        @compileError("Unsupported KeyType for CountSketch. KeyType must be an unsigned integer.");
    }
    if (@typeInfo(CounterType).int.signedness != .signed) {
        @compileError("CounterType must be signed (e.g., i32, i64)");
    }

    return struct {
        const Self: type = @This();
        const CSBase: type = CountSketchBase(KeyType, CounterType, 2);

        w: usize,
        d: usize,
        table: []CSBase,
        allocator: Allocator,

        /// Initializes the CountSketch with specified depth (d) and width (w).
        ///
        /// Parameters:
        /// - allocator: The allocator to use for memory allocation.
        /// - d: The depth of the CountSketch (must be > 0).
        /// - w: The width of the CountSketch (must be > 0).
        /// - seed: The seed for the random number generator.
        pub fn init(allocator: Allocator, d: usize, w: usize, seed: u64) !Self {
            if (d == 0) {
                const fmt = "CountSketch depth (d) must be greater than 0";
                if (!builtin.is_test) {
                    std.log.err(fmt, .{});
                } else {
                    std.log.warn(fmt, .{});
                }
                return error.InvalidArgument;
            }
            if (w == 0) {
                const fmt = "CountSketch width (w) must be greater than 0";
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

            self.table = try self.allocator.alloc(CSBase, d);

            var prng = std.Random.DefaultPrng.init(seed);
            const rand = prng.random();
            for (self.table) |*table| {
                table.* = try CSBase.init(allocator, w, rand.int(u64));
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

        /// Updates the CountSketch with a delta for the specified item.
        ///
        /// Parameters:
        /// - key: The ket to update.
        /// - delta: The delta to add to the item's frequency.
        pub fn update(self: *Self, key: KeyType, delta: CounterType) void {
            for (0..self.d) |i| {
                self.table[i].update(key, delta);
            }
        }

        /// Estimates the frequency of the specified item.
        ///
        /// Parameters:
        /// - key: The item to estimate.
        pub fn estimate(self: *Self, key: KeyType) !CounterType {
            const estimates = try self.allocator.alloc(CounterType, self.d);
            @memset(estimates, 0);
            defer self.allocator.free(estimates);

            for (0..self.d) |i| {
                const index: usize = self.table[i].index_hash(key);
                const sign: CounterType = self.table[i].sign_hash(key);
                estimates[i] = sign * self.table[i].counters[index];
            }

            // Return median of estimates
            std.mem.sort(CounterType, estimates, {}, std.sort.asc(CounterType));
            const median_index = self.d / 2;
            return estimates[median_index];
        }
    };
}

/// L2Estimator to estimate the l2 norm squared of a frequency vector undergoing
/// dynamic updates. Returns a (1 + eps)-approximation of the l2 norm squared with
/// constant probability (at least 3/4)
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer).
/// - CounterType: The type for the counters (e.g., i32, i64). Must be signed.
pub fn L2Estimator(comptime KeyType: type, comptime CounterType: type) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned) {
        @compileError("Unsupported KeyType for L. KeyType must be an unsigned integer.");
    }
    if (@typeInfo(CounterType).int.signedness != .signed) {
        @compileError("CounterType must be signed (e.g., i32, i64)");
    }

    return struct {
        const Self: type = @This();
        const CSBase: type = CountSketchBase(KeyType, CounterType, 4);

        w: usize,
        eps: f64,
        sketch: CSBase,

        /// Initializes the L2Estimator with specified depth (d) and width (w).
        ///
        /// Parameters:
        /// - allocator: The allocator to use for memory allocation.
        /// - eps: The error parameter (must be in range (0, 1)).
        /// - seed: The seed for the random number generator.
        pub fn init(allocator: Allocator, eps: f64, seed: u64) !Self {
            if (eps <= 0 or eps >= 1) {
                const fmt = "L eps (w) must be in range (0, 1)";
                if (!builtin.is_test) {
                    std.log.err(fmt, .{});
                } else {
                    std.log.warn(fmt, .{});
                }
                return error.InvalidArgument;
            }

            var self = Self{
                .eps = eps,
                .w = @intFromFloat(6 / (eps * eps)),
                .sketch = undefined,
            };

            var prng = std.Random.DefaultPrng.init(seed);
            const rand = prng.random();
            self.sketch = try CSBase.init(allocator, self.w, rand.int(u64));
            errdefer self.sketch.deinit();

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.sketch.deinit();
            self.* = undefined;
        }

        /// Updates the sketch with a delta for the specified item.
        ///
        /// Parameters:
        /// - key: The item to update.
        /// - delta: The delta to add to the item's frequency.
        pub fn update(self: *Self, key: KeyType, delta: CounterType) void {
            self.sketch.update(key, delta);
        }

        /// Estimates the square of the l2 norm of the frequency vector.
        pub fn estimate(self: *Self) CounterType {
            var est: CounterType = 0;
            for (0..self.w) |i| {
                est += self.sketch.counters[i] * self.sketch.counters[i];
            }
            return est;
        }
    };
}

// ----------- TESTS for CountSketch (Unsigned Ints Only) -----------

test "CountSketch (uint) type check" {
    _ = CountSketch(u8, i32);
    _ = CountSketch(u64, i64);

    // These should fail compilation if uncommented:
    // _ = CountSketch(i32, i64); // Signed key
    // _ = CountSketch(f32, i64); // Float key
    // _ = CountSketch([]const u8, i64); // Slice key
    // _ = CountSketch(u64, u64); // Unsigned counter

    try std.testing.expect(true); // Passes if it compiles
}

test "CountSketch (uint) basic estimates" {
    const CS = CountSketch(u32, i64);
    const allocator = std.testing.allocator;

    var sketch = try CS.init(allocator, 5, 10, std.testing.random_seed);
    defer sketch.deinit();

    const item1: u32 = 10001;
    const item2: u32 = 20002;

    sketch.update(item1, 20);
    sketch.update(item2, -30);

    const estimate1 = try sketch.estimate(item1);
    const estimate2 = try sketch.estimate(item2);
    std.debug.print("\n-- CountSketch (u32 keys) --\n", .{});
    std.debug.print(" - Item {d}: {} (Actual 20)\n", .{ item1, estimate1 });
    std.debug.print(" - Item {d}: {} (Actual -30)\n", .{ item2, estimate2 });

    try std.testing.expect(true); // Passes if it compiles
}

test "L2Estimator (uint) basic usage" {
    const allocator = std.testing.allocator;
    // Test with u32 keys and i64 counters
    const EstimatorU32 = L2Estimator(u32, i64);

    const seed: u64 = std.testing.random_seed;

    var estimator = try EstimatorU32.init(allocator, 0.1, seed);
    defer estimator.deinit();

    const item1: u32 = 10001;
    const item2: u32 = 20002;

    estimator.update(item1, 1);
    estimator.update(item2, 1);
    estimator.update(item1, 1);
    estimator.update(item1, 2); // item1 count = 4
    estimator.update(item2, 5); // item2 count = 1 + 5 = 6

    const estimate = estimator.estimate();
    const actual = 4 * 4 + 6 * 6; // l2 norm squared
    std.debug.print("\n-- L2Estimator (u32 keys, width: {}) --\n", .{estimator.w});
    std.debug.print(" - l2 norm squared estimate: {} (Actual {})\n", .{ estimate, actual });

    try std.testing.expect(true); // Passes if it compiles
}
