//! Scales a finished mix to a peak level.

const std = @import("std");

/// Scales `samples` in place so that its absolute peak equals `peak`. Silence is left as it is.
pub fn inner(comptime T: type, samples: []T, peak: T) void {
    var max: T = 0.0;
    for (samples) |sample| max = @max(max, @abs(sample));
    if (max == 0.0) return;

    const gain = peak / max;
    for (samples) |*sample| sample.* *= gain;
}

test "normalize scales to the peak" {
    var samples = [_]f64{ 0.5, -2.0, 1.0 };
    inner(f64, &samples, 0.8);
    try std.testing.expectEqualSlices(f64, &.{ 0.2, -0.8, 0.4 }, &samples);
}

test "normalize leaves silence alone" {
    var samples = [_]f64{ 0.0, 0.0 };
    inner(f64, &samples, 0.8);
    try std.testing.expectEqualSlices(f64, &.{ 0.0, 0.0 }, &samples);
}

test {
    std.testing.refAllDecls(@This());
}
