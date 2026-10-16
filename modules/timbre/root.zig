//! Ready-made timbres for rock: drums, an overdriven bass and a distorted guitar string.
//!
//! Role: Ready-made timbres. Depends on nothing but `std`.
//!
//! Every timbre is a type whose fields are its parameters, with a `render` function that returns a
//! plain mono sample array: the first `frames` frames of a note that sounds `length` frames if
//! nothing cuts it. Asking for fewer frames gives exactly the start of the full note, so a note cut
//! by the rule of a vibrating body sounds the same up to the cut. The fade of the timbre, how the
//! sound itself dies away, is part of each timbre and ends at `length`.
//!
//! Timbres with noise take a `std.Random`, so the caller seeds it and no waveform depends on what
//! was generated before it. The timbres are designed for this piece; none is a port of a preset.

const std = @import("std");

/// Rock kick drum.
pub const Kick = @import("./kick.zig").inner;
/// Rock snare drum.
pub const Snare = @import("./snare.zig").inner;
/// Cymbals, with the settings `closed`, `open` (hi-hats) and `crash`.
pub const Cymbal = @import("./cymbal.zig").inner;
/// Overdriven picked electric bass.
pub const Bass = @import("./bass.zig").inner;
/// Distorted electric guitar string, open or palm-muted.
pub const Guitar = @import("./guitar.zig").inner;

test {
    std.testing.refAllDecls(@This());
    _ = @import("./dsp.zig");
}
