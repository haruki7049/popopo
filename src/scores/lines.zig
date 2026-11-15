//! The layer type of each kind of vibrating body: which primitives one line of score is made of.

const std = @import("std");
const meters = @import("meters");
const primitives = @import("../primitives.zig");

/// The timings alone, written apart from the volume so that one volume serves every timing.
pub const Timing = meters.Layer(.{ .timing = primitives.Timing });

/// The volume alone.
pub const Volume = meters.Layer(.{ .volume = primitives.Volume });

/// Score of a drum: kick, snare or hi-hat. A timing layer zipped with a volume layer.
pub const Hit = Timing.Zip(Volume);

test {
    std.testing.refAllDecls(@This());
}
