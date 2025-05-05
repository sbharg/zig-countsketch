const std = @import("std");
const Allocator = std.mem.Allocator;
const cs = @import("countsketch");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const seed: u64 = @intCast(std.time.microTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    // Example usage of CountSketch and L2Estimator
    var list = std.ArrayList(i64).init(allocator);
    const len = 1_000_000;
    var actual_l2: i64 = 0;
    for (0..len) |_| {
        try list.append(rand.intRangeAtMost(i64, -10, 10));
    }

    const w = 1 << 13;
    const d = 5;
    const eps = 0.125;

    // Initialize the CountSketch and L2Estimator with the specified parameters
    var sketch = try cs.CountSketch(u32, i64).init(allocator, d, w, rand.int(u64));
    var l2_estimator = try cs.L2Estimator(u32, i64).init(allocator, eps, rand.int(u64));
    defer sketch.deinit();
    defer l2_estimator.deinit();

    for (list.items, 0..) |item, i| {
        // Update the CountSketch with the item
        sketch.update(@as(u32, @intCast(i)), item);
        // Update the L2Estimator with the item
        l2_estimator.update(@as(u32, @intCast(i)), item);
        actual_l2 += item * item;
    }

    // Retrieve the estimated L2 squared norm
    const l2_estimate = l2_estimator.estimate();
    std.debug.print("L2 squared estimate: {} (Actual: {})\n", .{ l2_estimate, actual_l2 });
    const approx_factor: f64 = @as(f64, @floatFromInt(l2_estimate)) / @as(f64, @floatFromInt(actual_l2));
    //l2_rel_error = @abs(l2_rel_error - @as(f64, actual_l2)) / @as(f64, actual_l2);
    std.debug.print("Approximation Factor: {e}\n", .{approx_factor});

    // Retrieve the estimated count for the key
    var avg_err: f64 = 0.0;
    var max_err: u64 = 0.0;
    for (list.items, 0..) |freq, i| {
        const estimate = try sketch.estimate(@as(u32, @intCast(i)));
        //std.debug.print("Estimated count for key {}: {} (Actual: {})\n", .{ i, estimate, freq });
        const err = @abs(estimate - freq);
        avg_err += @floatFromInt(err);
        max_err = @max(max_err, err);
    }
    avg_err /= len;
    std.debug.print("CountSketch Average error: {}\n", .{avg_err});
    std.debug.print("CountSketch Maximum error: {}\n", .{max_err});
}
