const std = @import("std");
const Allocator = std.mem.Allocator;

/// Provides a k-wise independent hash function based on multiplication-shift
/// for unsigned integer keys.
/// The hash function maps the input key to an integer in the range [0, 2^61).
///
/// Parameters:
/// - KeyType: The type of the keys (must be an unsigned integer type).
pub fn KWiseIndependentHash(comptime KeyType: type) type {
    // --- Compile-time checks ---
    if (@typeInfo(KeyType).int.signedness != .unsigned) {
        @compileError("Unsupported KeyType for KIndependentHasher. KeyType must be an unsigned integer.");
    }

    return struct {
        const Self: type = @This();
        const MP61: u64 = (1 << 61) - 1; // 2^61 - 1 (Large Mersenne prime)

        k: usize,
        coefficients: []u64, // k random odd multipliers
        allocator: Allocator,

        /// Initializes the hasher with k independent hash functions.
        pub fn init(allocator: Allocator, k: usize, seed: u64) !Self {
            if (k == 0) {
                std.log.err("KWiseIndependentHash requires k > 0.", .{});
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
            // Generate k random integers in the range [1, MP)
            for (self.coefficients) |*coeff| {
                coeff.* = rand.intRangeAtMost(u64, 0, MP61);
            }

            return self;
        }

        /// Deinitializes the hasher, freeing allocated memory.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.coefficients);
            self.* = undefined;
        }

        /// Converts the unsigned integer key (KeyType) into a u64 value.
        inline fn keyToU64(self: *Self, item: KeyType) u64 {
            _ = self; // Avoid unused parameter warning
            // Safely cast any unsigned integer type to u64
            return @intCast(item);
        }

        /// Fast moudulo operations for 2^61 - 1
        fn mod61(self: *Self, hi: u64, lo: u64) u64 {
            _ = self; // Avoid unused parameter warning
            const lo61: u64 = lo & MP61;
            const hi_part: u64 = (lo >> 61) + (hi << 3) + (hi >> 58);
            const sum: u64 = lo61 + hi_part;

            return if (sum >= MP61) sum - MP61 else sum;
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
            var res: u64 = 0;
            // Horners method for polynomial evaluation
            var i: usize = self.coefficients.len - 1;
            while (i >= 0) : (i -= 1) {
                const coeff: u64 = self.coefficients[i];
                const key: u64 = self.keyToU64(item);

                res = mul61(res, key) + coeff;
                res = if (res >= MP61) res - MP61 else res;
            }
            return res;
        }
    };
}

// // ----------- TESTS for KIndependentHasher (Unsigned Ints Only) -----------

test "KWiseIndependentHash (uint) init/deinit" {
    const allocator = std.testing.allocator;
    const HasherU64 = KWiseIndependentHash(u64);
    const HasherU32 = KWiseIndependentHash(u32);

    var hasher1 = try HasherU64.init(allocator, 5, 0);
    defer hasher1.deinit();
    try std.testing.expectEqual(@as(usize, 5), hasher1.k);
    try std.testing.expectEqual(@as(usize, 5), hasher1.coefficients.len);

    var hasher2 = try HasherU32.init(allocator, 10, 0);
    defer hasher2.deinit();
    try std.testing.expectEqual(@as(usize, 10), hasher2.k);
    try std.testing.expectEqual(@as(usize, 10), hasher2.coefficients.len);

    try std.testing.expectError(error.InvalidArgument, HasherU64.init(allocator, 0, 0));
}

test "KWiseIndependentHash (uint) mul61" {
    const a: u64 = (1 << 63);
    const b: u64 = (1 << 10) + 20;

    const HasherU64 = KWiseIndependentHash(u64);
    var hasher = try HasherU64.init(std.testing.allocator, 5, 0);
    defer hasher.deinit();

    try std.testing.expectEqual(a + b, 9223372036854776852);
    try std.testing.expectEqual(hasher.mul61(a, b), 4176);
    try std.testing.expectEqual(hasher.mul61(b, a), 4176);
    try std.testing.expectEqual(hasher.mul61(20, 10), 200);
}
