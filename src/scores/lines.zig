//! The layer type of each kind of vibrating body: which primitives one line of score is made of.

const std = @import("std");
const meters = @import("meters");
const primitives = @import("../primitives.zig");

/// Score of one guitar string.
pub const String = thin.Duration
    .Zip(thin.Mute)
    .Zip(thin.Pitch)
    .Zip(thin.Timing)
    .Zip(thin.Volume);

/// A score of a drum: kick, snare or crash.
pub const Hit = thin.Timing
    .Zip(thin.Volume);

pub const thin = struct {
    /// A thin layer which has only durations
    pub const Duration = meters.Layer(.{ .duration = primitives.Duration });

    /// A thin layer which has only some mute values
    pub const Mute = meters.Layer(.{ .mute = primitives.Mute });

    /// A thin layer which has only pitches
    pub const Pitch = meters.Layer(.{ .pitch = primitives.Pitch });

    /// A thin layer which has only timings
    pub const Timing = meters.Layer(.{ .timing = primitives.Timing });

    /// A thin layer which has only volumes
    pub const Volume = meters.Layer(.{ .volume = primitives.Volume });
};

// Multi scores of a guitar: it has only one root string for now
pub const Guitar = struct {
    root: String,
};

// Multi scores of a drum set: kick and snare.
pub const Drum = struct {
    kick: Hit,
    snare: Hit,
};

test {
    std.testing.refAllDecls(@This());
}
