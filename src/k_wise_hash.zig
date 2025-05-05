const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

/// Provides a k-wise independent hash function based on Carter-Wegman hashing
/// for unsigned integer keys.
/// The hash function maps the input key to an integer in the range [0, 2^61).
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer type).
pub fn KWiseHash(comptime KeyType: type) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned or @typeInfo(KeyType).int.bits > 32) {
        @compileError("Unsupported KeyType for KWiseHash. KeyType must be u32 or less.");
    }

    return struct {
        const Self: type = @This();
        const mp_61: u64 = (1 << 61) - 1; // 2^61 - 1 (Large Mersenne prime)

        k: usize,
        coefficients: []u64, // k random coefficients in [0, 2^61-1)
        allocator: Allocator,

        /// Initializes the hasher with k independent hash functions.
        pub fn init(allocator: Allocator, k: usize, seed: u64) !Self {
            if (k == 0) {
                const fmt = "KWiseHash requires k > 0.";
                if (!builtin.is_test) {
                    std.log.err(fmt, .{});
                } else {
                    std.log.warn(fmt, .{});
                }
                return error.InvalidArgument;
            }
            var self = Self{
                .k = k,
                .allocator = allocator,
                .coefficients = undefined,
            };

            self.coefficients = try allocator.alloc(u64, k);
            @memset(self.coefficients, 0);
            errdefer allocator.free(self.coefficients);

            var prng = std.Random.DefaultPrng.init(seed);
            const rand = prng.random();
            // Generate k random integers in the range [0, MP)
            for (self.coefficients) |*coeff| {
                //coeff.* = rand.intRangeAtMost(u64, 0, mp_61);
                coeff.* = rand.uintLessThan(u64, mp_61);
            }

            return self;
        }

        /// Deinitializes the coefficients, freeing allocated memory.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.coefficients);
            self.* = undefined;
        }

        /// Converts the unsigned integer key (KeyType) into a u64 value.
        inline fn keyToU32(self: *Self, item: KeyType) u32 {
            _ = self; // Avoid unused parameter warning
            // Safely cast any unsigned integer type to u64
            return @intCast(item);
        }

        /// Fast moudulo operations for 2^61 - 1
        /// The input is a 128-bit number represented as
        /// its most significant 64 bits (hi) and least significant 64 bits (lo).
        fn mod61(self: *Self, hi: u64, lo: u64) u64 {
            _ = self; // Avoid unused parameter warning
            const lo61: u64 = lo & mp_61; // Get least significant 61 bits
            const hi61: u64 = (lo >> 61) + (hi << 3) + (hi >> 58); // Get most significant 61 bits
            const sum: u64 = lo61 + hi61;

            return if (sum >= mp_61) sum - mp_61 else sum;
        }

        /// Fast multiplication modulo 2^61 - 1
        fn mul61(self: *Self, a: u64, b: u64) u64 {
            const a_cast: u128 = @intCast(a);
            const b_cast: u128 = @intCast(b);
            const product: u128 = a_cast * b_cast;
            const hi: u64 = @intCast(product >> 64);
            const lo: u64 = @truncate(product);
            return self.mod61(hi, lo);
        }

        /// Computes the hash value for the given item.
        /// Returns the full 64-bit hash result.
        pub fn hash(self: *Self, item: KeyType) u64 {
            var res: u64 = self.coefficients[self.coefficients.len - 1];
            // Horners method for polynomial evaluation
            var i: usize = self.coefficients.len - 1;
            while (i > 0) {
                i -= 1;
                const coeff: u64 = self.coefficients[i];
                const key: u32 = self.keyToU32(item);

                res = self.mul61(res, key) + coeff;
                res = if (res >= mp_61) res - mp_61 else res;
            }
            return res;
        }
    };
}

// // ----------- TESTS for KIndependentHasher (Unsigned Ints Only) -----------

test "LeftShift" {
    const a: u64 = (1 << 13);
    try std.testing.expectEqual(8192, a);
}

test "KWiseHash (uint) init/deinit" {
    const allocator: Allocator = std.testing.allocator;
    const HasherU24 = KWiseHash(u24);
    const HasherU32 = KWiseHash(u32);
    const seed: u64 = std.testing.random_seed;

    var hasher1 = try HasherU24.init(allocator, 5, seed);
    defer hasher1.deinit();
    try std.testing.expectEqual(@as(usize, 5), hasher1.k);
    try std.testing.expectEqual(@as(usize, 5), hasher1.coefficients.len);

    var hasher2 = try HasherU32.init(allocator, 10, seed);
    defer hasher2.deinit();
    try std.testing.expectEqual(@as(usize, 10), hasher2.k);
    try std.testing.expectEqual(@as(usize, 10), hasher2.coefficients.len);

    try std.testing.expectError(error.InvalidArgument, HasherU24.init(allocator, 0, 0));
}

test "KWiseHash (uint) mod61" {
    // const a: u64 = (1 << 63);
    // const b: u64 = (1 << 10) + 20;

    const HasherU64 = KWiseHash(u32);
    const seed: u64 = std.testing.random_seed;
    const alloc = std.testing.allocator;
    var hasher = try HasherU64.init(alloc, 5, seed);
    defer hasher.deinit();

    try std.testing.expectEqual(512, hasher.mod61(0, 512));
    try std.testing.expectEqual((1 << 31), hasher.mod61(0, 1 << 31));
    try std.testing.expectEqual(8, hasher.mod61(1, 0));
}

test "KWiseHash (uint) mul61" {
    const a: u64 = (1 << 63);
    const b: u64 = (1 << 10) + 20;

    const HasherU64 = KWiseHash(u32);
    const seed: u64 = std.testing.random_seed;
    const alloc = std.testing.allocator;
    var hasher = try HasherU64.init(alloc, 5, seed);
    defer hasher.deinit();

    try std.testing.expectEqual(
        9223372036854776852,
        a + b,
    );
    try std.testing.expectEqual(4176, hasher.mul61(a, b));
    try std.testing.expectEqual(4176, hasher.mul61(b, a));
    try std.testing.expectEqual(200, hasher.mul61(20, 10));
}
