//! The instrument set: for every vibrating body, how long a note sounds if nothing cuts it, and
//! which timbre sounds it. Which notes share a body is decided by which score is handed to it.

const std = @import("std");
const body = @import("body");
const perform = @import("perform");
const timbre = @import("timbre");

const configs = @import("./configs.zig");
const scores = @import("./scores.zig");

const T = configs.T;

/// The procedure for vibrating bodies whose resolved notes are `R`.
pub fn Procedure(comptime R: type) type {
    return perform.Procedure(T, R, body, .timing);
}

const HitNote = scores.lines.Hit.Resolved;

/// Seconds to frames.
fn toFrames(seconds: T) usize {
    return @intFromFloat(@round(seconds * @as(T, @floatFromInt(configs.SAMPLE_RATE))));
}

/// A generator for the noise of one note, seeded by the body and by where the note starts, so
/// the waveform of a note depends on nothing else.
fn seeded(salt: u64, start: usize) std.Random.DefaultPrng {
    return .init(salt ^ @as(u64, start));
}

/// A drum sounds for `seconds` unless its volume is zero.
fn drumLength(note: HitNote) usize {
    const SECONDS: usize = 1;

    return if (note.volume > 0.0) toFrames(SECONDS) else 0;
}

/// The kick, with a shorter decay than the default, so it has died away by the end of its 0.55 s.
const kick_timbre: timbre.Kick(T) = .{ .decay = 0.17 };
/// The snare with its default settings.
const snare_timbre: timbre.Snare(T) = .{};
/// The cymbals; the closed and open hi-hat and the crash are its settings.
const Cymbal = timbre.Cymbal(T);
/// The closed hi-hat.
const hihat_timbre = Cymbal.closed;

/// Sounds the kick at the volume of the note.
fn kickDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
    return kick_timbre.render(allocator, configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
}

/// Sounds the snare at the volume of the note.
fn snareDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
    var prng = seeded(0x5a7e, note.timing);
    return snare_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
}

/// A closed hi-hat sounds for `SECONDS` unless its volume is zero; it has died away by then and
/// the next hit comes later, so it never cuts the previous one.
fn hihatLength(note: HitNote) usize {
    const SECONDS: T = 0.15;

    return if (note.volume > 0.0) toFrames(SECONDS) else 0;
}

/// Sounds the closed hi-hat at the volume of the note.
fn hihatTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
    var prng = seeded(0x41a7, note.timing);
    return hihat_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, note.volume, length, frames);
}

pub const kick: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = kickDrumTimble };

pub const snare: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = snareDrumTimble };

pub const hihat: Procedure(HitNote).Body = .{ .length = hihatLength, .timbre = hihatTimble };

test {
    std.testing.refAllDecls(@This());
}
