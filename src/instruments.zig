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

const GuitarNote = scores.lines.Guitar.Resolved;
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

/// How long a drum sounds, in seconds, unless its volume is zero.
const DRUM_SECONDS: usize = 1;

/// A drum sounds for `DRUM_SECONDS` unless its volume is zero.
fn drumLength(note: HitNote) usize {
    return if (note.volume > 0.0) toFrames(DRUM_SECONDS) else 0;
}

/// The kick, with a shorter decay than the default, so it has died away by the end of its 0.55 s.
const kick_timbre: timbre.Kick(T) = .{ .decay = 0.17 };
/// The snare with its default settings.
const snare_timbre: timbre.Snare(T) = .{};
/// The snare drum solved once by `solveSnare`, and read by every hit: the drum has no noise and the
/// volume only scales it, so every hit is the same drum. Without it each hit solves the drum again,
/// which gives the same sound far more slowly.
var snare_response: ?timbre.Snare(T).Response = null;

/// Solves the snare for the longest hit. `freeSnare` frees it.
pub fn solveSnare(allocator: std.mem.Allocator) !void {
    snare_response = try snare_timbre.respond(allocator, configs.SAMPLE_RATE, toFrames(DRUM_SECONDS));
}

/// Frees what `solveSnare` made.
pub fn freeSnare(allocator: std.mem.Allocator) void {
    if (snare_response) |response| response.deinit(allocator);
    snare_response = null;
}
/// The cymbals; the closed and open hi-hat and the crash are its settings.
const Cymbal = timbre.Cymbal(T);
/// The left guitar.
const guitar_timbre: timbre.Guitar(T) = .{};

/// A muted string is lifted early; an open one rings for its whole duration.
fn guitarLength(note: GuitarNote) usize {
    if (note.volume == 0.0) return 0;
    const held = 1.0 - 0.25 * note.mute;
    return @intFromFloat(@round(@as(T, @floatFromInt(note.duration)) * held));
}

/// Sounds the left guitar at the pitch, palm muting and volume of the note.
fn guitarTimble(allocator: std.mem.Allocator, note: GuitarNote, length: usize, frames: usize) anyerror![]T {
    return guitar_timbre.render(allocator, configs.SAMPLE_RATE, note.pitch, note.mute, note.volume, length, frames);
}

/// Sounds the left guitar at the pitch, palm muting and volume of the note.
fn kickDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
    return kick_timbre.render(allocator, configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
}

/// Sounds the left guitar at the pitch, palm muting and volume of the note.
fn snareDrumTimble(allocator: std.mem.Allocator, note: HitNote, length: usize, frames: usize) anyerror![]T {
    var prng = seeded(0x5a7e, note.timing);
    const response = snare_response orelse return snare_timbre.render(allocator, prng.random(), configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames);
    return snare_timbre.renderWith(allocator, configs.SAMPLE_RATE, configs.CHANNELS, note.volume, length, frames, response);
}

/// One string of the left guitar; the root and the fifth are two such bodies.
pub const guitar: Procedure(GuitarNote).Body = .{ .length = guitarLength, .timbre = guitarTimble };

pub const kick: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = kickDrumTimble };

pub const snare: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = snareDrumTimble };

test {
    std.testing.refAllDecls(@This());
}
