//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub export fn add(a: u64, b: u64) u64 {
    return a + b;
}

test "basic add functionality" {
    const MP: u64 = (1 << 61) - 1;
    try testing.expect(add(MP, 1) == 2305843009213693952);

    const a: u64 = (1 << 63);
    const b: u64 = (1 << 10) + 20;
    const a_cast: u128 = @intCast(a);
    const b_cast: u128 = @intCast(b);
    const product: u128 = a_cast * b_cast;
    std.log.err("Product is {b}", .{product});

    const hi: u64 = @intCast(product >> 64);
    const lo: u64 = @truncate(product);
    std.log.err("High is {b}", .{hi});
    std.log.err("Low is {b}", .{lo});
}
//Hig: 0000000000000000000000000000000000000000000000000000001000001010
//Low: 0000000000000000000000000000000000000000000000000000000000000000
