//! The whole piece: one score per vibrating body, each lasting the whole piece.

const std = @import("std");
const lines = @import("./lines.zig");

const Self = @This();

pub const Guitar = struct {
    /// The root string of each guitar.
    root: lines.Guitar,
};

pub const Drum = struct {
    /// kick drum
    kick: lines.Hit,

    /// snare drum
    snare: lines.Hit,
};

base: Self.Guitar,
melody: Self.Guitar,
drum: Self.Drum,

test {
    std.testing.refAllDecls(@This());
}
