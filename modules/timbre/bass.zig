//! Overdriven picked electric bass: saw, square and sine, a low-pass that closes after the pick,
//! drive, and a speaker-like low-pass.

const std = @import("std");
const dsp = @import("./dsp.zig");

/// Returns the bass type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Cutoff of the filter right after the pick, in Hz.
        brightness: T = 1900.0,
        /// Cutoff the filter settles to, in Hz.
        body: T = 520.0,
        /// Time constant of the filter closing, in seconds.
        pluck: T = 0.08,
        /// Level the note settles to after the pick, from 0 to 1.
        sustain: T = 0.55,
        /// Time constant of the fall to `sustain`, in seconds.
        decay: T = 0.18,
        /// Drive of the overdrive.
        drive: T = 2.6,
        /// Cutoff of the speaker, in Hz.
        speaker: T = 3200.0,
        /// Rise at the start of the note, in seconds.
        attack: T = 0.002,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.012,

        /// Returns the first `frames` frames (mono) of a note at `frequency` Hz and `volume` that
        /// sounds `length` frames if nothing cuts it. Frames past `length` are silent. The caller
        /// owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, sample_rate: u32, frequency: T, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            var saw: dsp.Oscillator(T) = .{};
            var square: dsp.Oscillator(T) = .{};
            var sine: dsp.Oscillator(T) = .{};
            var filter = dsp.Biquad(T).init(.lowpass, self.brightness, 0.9, rate);
            var speaker = dsp.Biquad(T).init(.lowpass, self.speaker, 0.707, rate);

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;
                if (i % 16 == 0) {
                    const cutoff = self.body + (self.brightness - self.body) * dsp.decay(T, t, self.pluck);
                    filter.tune(.lowpass, cutoff, 0.9, rate);
                }

                const tone = saw.saw(frequency, rate) + 0.5 * square.square(frequency, rate) + 0.6 * sine.sine(frequency, rate);
                const level = dsp.rise(T, t, self.attack) * (self.sustain + (1.0 - self.sustain) * dsp.decay(T, t, self.decay));
                const driven = dsp.saturate(T, 0.6 * filter.process(tone) * level, self.drive);

                sample.* = volume * speaker.process(driven) * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }
    };
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const bass: inner(f64) = .{};
    const samples = try bass.render(allocator, 44100, 82.4, 1.0, 9450, 9450);
    defer allocator.free(samples);

    try std.testing.expectEqual(@as(usize, 9450), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
    try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
    var peak: f64 = 0.0;
    for (samples) |s| peak = @max(peak, @abs(s));
    try std.testing.expect(peak > 0.3 and peak < 1.5);
}

test "a cut note is the start of the full note" {
    const allocator = std.testing.allocator;
    const bass: inner(f64) = .{};
    const full = try bass.render(allocator, 44100, 55.0, 0.7, 9450, 9450);
    defer allocator.free(full);
    const cut = try bass.render(allocator, 44100, 55.0, 0.7, 9450, 4000);
    defer allocator.free(cut);
    try std.testing.expectEqualSlices(f64, full[0..4000], cut);
}

test "frames past the length are silent" {
    const allocator = std.testing.allocator;
    const bass: inner(f64) = .{};
    const samples = try bass.render(allocator, 44100, 110.0, 1.0, 1000, 1200);
    defer allocator.free(samples);
    for (samples[1000..]) |s| try std.testing.expectEqual(@as(f64, 0.0), s);
}

test {
    std.testing.refAllDecls(@This());
}
