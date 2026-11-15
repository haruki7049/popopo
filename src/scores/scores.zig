//! The whole piece: one score per vibrating body, each lasting the whole piece.

const std = @import("std");
const lines = @import("./lines.zig");

const Self = @This();

pub const Drum = struct {
    /// kick drum
    kick: lines.Hit,

    /// snare drum
    snare: lines.Hit,

    /// closed hi-hat
    hihat: lines.Hit,
};

drum: Self.Drum,

test {
    std.testing.refAllDecls(@This());
}
