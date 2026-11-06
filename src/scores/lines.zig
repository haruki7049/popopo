//! The layer type of each kind of vibrating body: which primitives one line of score is made of.

const std = @import("std");
const meters = @import("meters");
const primitives = @import("../primitives.zig");

/// Score of one guitar string.
pub const Guitar = meters.Layer(.{
    .duration = primitives.Duration,
    .mute = primitives.Mute,
    .pitch = primitives.Pitch,
    .timing = primitives.Timing,
    .volume = primitives.Volume,
});

/// Score of a drum: kick, snare or crash.
pub const Hit = meters.Layer(.{
    .timing = primitives.Timing,
    .volume = primitives.Volume,
});

test {
    std.testing.refAllDecls(@This());
}
