//! The procedure that turns values into waveforms.
//!
//! Role: The procedure that turns values into waveforms. Depends on nothing but `std`.
//!
//! For one vibrating body, it takes the resolved notes of its score, asks the instrument set how
//! long each note sounds, has the rule of a vibrating body decide the approximation fade, asks the
//! timbre for the waveform, and passes the waveform on to place and mix with its start and the fade
//! position and length. It provides the type of the instrument set (`Procedure(...).Body`) that the
//! user fills in, and owns the procedure.
//!
//! The rule of a vibrating body and place and mix are received as a comptime parameter and an
//! argument, never imported. This module never changes a sample.

const std = @import("std");

/// Returns the procedure for vibrating bodies whose resolved notes are `R`, making samples of
/// type `T`, with the rule of a vibrating body `B` and the frame position in the field `start`.
pub const Procedure = @import("./procedure.zig").inner;

test {
    std.testing.refAllDecls(@This());
}
