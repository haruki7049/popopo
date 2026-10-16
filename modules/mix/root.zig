//! Place and mix: applies the approximation fade, places waveforms and mixes them.
//!
//! Role: Place and mix. Depends on nothing but `std`.
//!
//! Waveforms come in one at a time, like events, as plain mono sample slices with a start frame
//! and the approximation fade decided by the rule of a vibrating body. This module owns the
//! samples of the mix: it applies the fade, pans each waveform, adds it in, and hands back the
//! interleaved samples. It does not know scores, vibrating bodies or timbres.
//!
//! Reshaped from `sequencer`'s `Renderer` (the equal-power fade curve), without `lightmix.Wave`.

const std = @import("std");

/// Returns a mixer type for samples of type `T`.
pub const Mixer = @import("./mixer.zig").inner;
/// Scales a finished mix in place so that its absolute peak equals a level.
pub const normalize = @import("./normalize.zig").inner;

test {
    std.testing.refAllDecls(@This());
}
