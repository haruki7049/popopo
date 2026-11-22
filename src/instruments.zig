//! The instrument set: for every vibrating body, how long a note sounds if nothing cuts it, and
//! which timbre sounds it. Which notes share a body is decided by which score is handed to it.

const std = @import("std");
const body = @import("body");
const perform = @import("perform");
const pitches = @import("pitches");
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

const StabNote = scores.lines.Stab.Resolved;

/// The sawtooth synthesizer with its default settings.
const saw_timbre: timbre.Saw(T) = .{};

/// A stab sounds for `SECONDS` unless its volume is zero; it is short, so it stops before the next
/// offbeat comes.
fn stabLength(note: StabNote) usize {
    const SECONDS: T = 0.09;

    return if (note.volume > 0.0) toFrames(SECONDS) else 0;
}

/// The tuning of the synthesizer: twelve-tone equal temperament with A4 at 440 Hz.
const tuning: pitches.TwelveToneEqualTemperament = .{};

/// Sounds the chord of the note, tuned, at the volume of the note.
fn stabTimble(allocator: std.mem.Allocator, note: StabNote, length: usize, frames: usize) anyerror![]T {
    const frequencies = try allocator.alloc(T, note.chord.len);
    defer allocator.free(frequencies);
    for (frequencies, note.chord) |*frequency, pitch| frequency.* = tuning.freq(pitch);

    return saw_timbre.render(allocator, configs.SAMPLE_RATE, frequencies, note.volume, length, frames);
}

/// The guitar with its default settings.
const guitar_timbre: timbre.Guitar(T) = .{};

/// How far the palm mutes the strings of a guitar stab, from 0 (open) to 1 (fully muted).
const GUITAR_STAB_MUTE: T = 1.0;

/// A guitar stab sounds for `SECONDS` unless its volume is zero, as long as the synthesizer stab, so
/// it stops before the next offbeat comes.
fn guitarStabLength(note: StabNote) usize {
    const SECONDS: T = 0.09;

    return if (note.volume > 0.0) toFrames(SECONDS) else 0;
}

/// Sounds every pitch of the chord of the note on its own string of the guitar, tuned, at the volume
/// of the note. The sum is divided by the number of pitches, so a chord is as loud as a single pitch.
fn guitarStabTimble(allocator: std.mem.Allocator, note: StabNote, length: usize, frames: usize) anyerror![]T {
    const samples = try allocator.alloc(T, frames * configs.CHANNELS);
    errdefer allocator.free(samples);
    @memset(samples, 0.0);
    if (note.chord.len == 0) return samples;

    const share: T = 1.0 / @as(T, @floatFromInt(note.chord.len));
    for (note.chord) |pitch| {
        const string = try guitar_timbre.render(allocator, configs.SAMPLE_RATE, configs.CHANNELS, tuning.freq(pitch), GUITAR_STAB_MUTE, note.volume, length, frames);
        defer allocator.free(string);
        for (samples, string) |*sample, value| sample.* += share * value;
    }
    return samples;
}

pub const kick: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = kickDrumTimble };

pub const snare: Procedure(HitNote).Body = .{ .length = drumLength, .timbre = snareDrumTimble };

pub const hihat: Procedure(HitNote).Body = .{ .length = hihatLength, .timbre = hihatTimble };

pub const stab: Procedure(StabNote).Body = .{ .length = stabLength, .timbre = stabTimble };

pub const guitar_stab: Procedure(StabNote).Body = .{ .length = guitarStabLength, .timbre = guitarStabTimble };

test {
    std.testing.refAllDecls(@This());
}
