const std = @import("std");
const Allocator = std.mem.Allocator;
const cs = @import("countsketch");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const w = 10;
    const d = 5;

    const seed: u64 = @intCast(std.time.microTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    // Initialize the CountSketch with the specified parameters
    var sketch = cs.CountSketch(u32, i64).init(allocator, d, w, rand.int(u64)) catch unreachable;
    defer sketch.deinit();

    // Example usage of the CountSketch
    var list = std.ArrayList(i64).init(allocator);
    const len = 15;
    for (0..len) |i| {
        try list.append(rand.intRangeAtMost(i64, -10, 10));
        sketch.update(@as(u32, @intCast(i)), list.items[i]);
    }

    // Retrieve the estimated count for the key
    for (list.items, 0..) |freq, i| {
        const estimate = try sketch.estimate(@as(u32, @intCast(i)));
        std.debug.print("Estimated count for key {}: {} (Actual: {})\n", .{ i, estimate, freq });
    }
}
