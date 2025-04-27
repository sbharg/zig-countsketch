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
}
