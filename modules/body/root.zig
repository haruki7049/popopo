//! The rule of a vibrating body: decides the approximation fade.
//!
//! Role: The rule of a vibrating body. Depends on nothing but `std`.
//!
//! A vibrating body sounds one note at a time, and a new note cuts the previous one. This module
//! needs only where each note starts and how long it would sound if nothing cut it; it never sees a
//! waveform. For every note it decides how many frames actually sound, and where and how long the
//! approximation fade is. Applying the fade to samples is the job of place and mix.
//!
//! The approximation fade only approximates the rule: a real body keeps its state when it is
//! struck again, while here the previous note is faded out and the new one starts from nothing.
//!
//! Reshaped from `sequencer`'s `VoiceScheduler`, without waveforms and without the attack fade.

const std = @import("std");

/// One note handed to a vibrating body, in frames.
pub const Strike = struct {
    /// Frame position the note starts at.
    start: usize,
    /// Frames the note sounds if nothing cuts it. Zero: the note does not sound, so it does not
    /// cut the previous one either.
    length: usize,
};

/// What actually sounds of one note, in frames counted from the start of the note.
pub const Cut = struct {
    /// Frames that sound, including the approximation fade. Zero: the note does not sound.
    frames: usize,
    /// Frame, counted from the start of the note, where the approximation fade starts. Equal to
    /// `frames` when the note is not cut.
    fade_start: usize,
    /// Length of the approximation fade. Zero when the note is not cut.
    fade_frames: usize,
};

/// Length of the approximation fade in frames at `sample_rate`: 5 ms, rounded down.
pub fn fade(sample_rate: u32) usize {
    return sample_rate / 200;
}

/// Decides, for every strike on one vibrating body, what actually sounds. The result has one cut
/// per strike, in the order of `strikes`. The caller owns the returned slice.
///
/// Strikes are taken in order of start (ties keep their order in `strikes`). A note that a later
/// note starts during is cut there: it keeps sounding for the approximation fade, which is shortened
/// so that it ends by the time the note after that one starts. A note that another note starts at
/// the same frame does not sound at all.
pub fn decide(allocator: std.mem.Allocator, strikes: []const Strike, sample_rate: u32) std.mem.Allocator.Error![]Cut {
    return decideFrames(allocator, strikes, fade(sample_rate));
}

/// `decide` with the length of the approximation fade given in frames.
pub fn decideFrames(allocator: std.mem.Allocator, strikes: []const Strike, fade_frames: usize) std.mem.Allocator.Error![]Cut {
    const cuts = try allocator.alloc(Cut, strikes.len);
    errdefer allocator.free(cuts);

    // Only strikes that sound take part in the rule.
    var order: std.ArrayList(usize) = .empty;
    defer order.deinit(allocator);
    for (strikes, cuts, 0..) |strike, *cut, i| {
        cut.* = .{ .frames = 0, .fade_start = 0, .fade_frames = 0 };
        if (strike.length > 0) try order.append(allocator, i);
    }
    std.mem.sort(usize, order.items, strikes, struct {
        fn lessThan(all: []const Strike, a: usize, b: usize) bool {
            if (all[a].start == all[b].start) return a < b;
            return all[a].start < all[b].start;
        }
    }.lessThan);

    for (order.items, 0..) |i, k| {
        const strike = strikes[i];
        var cut: Cut = .{ .frames = strike.length, .fade_start = strike.length, .fade_frames = 0 };

        if (k + 1 < order.items.len) {
            const next = strikes[order.items[k + 1]].start;
            if (next == strike.start) {
                // Superseded by a note that starts at the same frame.
                cut = .{ .frames = 0, .fade_start = 0, .fade_frames = 0 };
            } else if (next < strike.start + strike.length) {
                const offset = next - strike.start;
                var length = @min(fade_frames, strike.length - offset);

                // The fade ends by the time the note after the next one starts.
                if (k + 2 < order.items.len) {
                    const after_next = strikes[order.items[k + 2]].start;
                    if (next + length > after_next) length = after_next - next;
                }
                cut = .{ .frames = offset + length, .fade_start = offset, .fade_frames = length };
            }
        }
        cuts[i] = cut;
    }
    return cuts;
}

test "fade is 5 ms" {
    try std.testing.expectEqual(@as(usize, 220), fade(44100));
    try std.testing.expectEqual(@as(usize, 240), fade(48000));
}

test "a cut note keeps sounding for the fade (the worked example of VoiceScheduler)" {
    // 60 BPM, 44100 Hz: a two-second note at beat 0 and a one-second note at beat 1.
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 0, .length = 88200 },
        .{ .start = 44100, .length = 44100 },
    }, 220);
    defer allocator.free(cuts);

    // The first note is cut at 44100 and fades over 220 frames.
    try std.testing.expectEqual(Cut{ .frames = 44320, .fade_start = 44100, .fade_frames = 220 }, cuts[0]);
    // The second note sounds in full.
    try std.testing.expectEqual(Cut{ .frames = 44100, .fade_start = 44100, .fade_frames = 0 }, cuts[1]);
}

test "a note that ends before the next one is not cut" {
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 0, .length = 100 },
        .{ .start = 100, .length = 100 },
    }, 20);
    defer allocator.free(cuts);

    try std.testing.expectEqual(Cut{ .frames = 100, .fade_start = 100, .fade_frames = 0 }, cuts[0]);
    try std.testing.expectEqual(Cut{ .frames = 100, .fade_start = 100, .fade_frames = 0 }, cuts[1]);
}

test "the fade is shortened by the note after the next one and by the end of the note" {
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 0, .length = 1000 },
        .{ .start = 100, .length = 1000 },
        .{ .start = 110, .length = 1000 },
        .{ .start = 500, .length = 405 },
    }, 20);
    defer allocator.free(cuts);

    // Cut at 100; the third note starts 10 frames later, so the fade is 10 frames.
    try std.testing.expectEqual(Cut{ .frames = 110, .fade_start = 100, .fade_frames = 10 }, cuts[0]);
    // Cut at 110 (offset 10), full fade.
    try std.testing.expectEqual(Cut{ .frames = 30, .fade_start = 10, .fade_frames = 20 }, cuts[1]);
    // Cut at 500 (offset 390), full fade.
    try std.testing.expectEqual(Cut{ .frames = 410, .fade_start = 390, .fade_frames = 20 }, cuts[2]);
    try std.testing.expectEqual(Cut{ .frames = 405, .fade_start = 405, .fade_frames = 0 }, cuts[3]);
}

test "the fade does not outlast the note" {
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 0, .length = 105 },
        .{ .start = 100, .length = 100 },
    }, 20);
    defer allocator.free(cuts);

    // Only 5 frames were left when the next note started.
    try std.testing.expectEqual(Cut{ .frames = 105, .fade_start = 100, .fade_frames = 5 }, cuts[0]);
}

test "a note at the same start supersedes the earlier one" {
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 50, .length = 100 },
        .{ .start = 50, .length = 80 },
    }, 20);
    defer allocator.free(cuts);

    try std.testing.expectEqual(@as(usize, 0), cuts[0].frames);
    try std.testing.expectEqual(Cut{ .frames = 80, .fade_start = 80, .fade_frames = 0 }, cuts[1]);
}

test "a note that does not sound does not cut" {
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 0, .length = 1000 },
        .{ .start = 100, .length = 0 },
    }, 20);
    defer allocator.free(cuts);

    try std.testing.expectEqual(Cut{ .frames = 1000, .fade_start = 1000, .fade_frames = 0 }, cuts[0]);
    try std.testing.expectEqual(@as(usize, 0), cuts[1].frames);
}

test "strikes are taken in order of start, and cuts keep the order of strikes" {
    const allocator = std.testing.allocator;
    const cuts = try decideFrames(allocator, &.{
        .{ .start = 100, .length = 1000 },
        .{ .start = 0, .length = 1000 },
    }, 20);
    defer allocator.free(cuts);

    try std.testing.expectEqual(Cut{ .frames = 1000, .fade_start = 1000, .fade_frames = 0 }, cuts[0]);
    try std.testing.expectEqual(Cut{ .frames = 120, .fade_start = 100, .fade_frames = 20 }, cuts[1]);
}

test {
    std.testing.refAllDecls(@This());
}
