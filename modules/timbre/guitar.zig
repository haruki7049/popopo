//! Distorted electric guitar string: two detuned saws and a square, a pick filter that palm muting
//! closes, asymmetric high-gain clipping, and a speaker cabinet.

const std = @import("std");
const dsp = @import("./dsp.zig");

/// Returns the guitar type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Gain into the clipper.
        drive: T = 9.0,
        /// Detune of the two saws, in cents.
        detune: T = 6.0,
        /// Cutoff of the pick filter on an open note, in Hz.
        open_cutoff: T = 3200.0,
        /// Cutoff of the pick filter on a fully muted note, in Hz.
        muted_cutoff: T = 1000.0,
        /// Time constant of an open note's decay, in seconds.
        open_decay: T = 1.4,
        /// Time constant of a fully muted note's decay, in seconds.
        muted_decay: T = 0.09,
        /// Cutoff of the cabinet, in Hz.
        cabinet: T = 5000.0,
        /// Boost of the cabinet's presence band, 0 for none.
        presence: T = 0.9,
        /// Center of the presence band, in Hz.
        presence_frequency: T = 2600.0,
        /// Rise at the start of the note, in seconds.
        attack: T = 0.0015,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.01,

        /// Returns the first `frames` frames (mono) of a note at `frequency` Hz and `volume` that
        /// sounds `length` frames if nothing cuts it. `mute` is how far the palm mutes the string,
        /// from 0 (open) to 1 (fully muted). Frames past `length` are silent. The caller owns the
        /// samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, sample_rate: u32, frequency: T, mute: T, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            const m = std.math.clamp(mute, 0.0, 1.0);
            const spread = std.math.pow(T, 2.0, self.detune / 1200.0);
            const cutoff = self.open_cutoff + (self.muted_cutoff - self.open_cutoff) * m;
            const fall = self.open_decay + (self.muted_decay - self.open_decay) * m;

            var upper: dsp.Oscillator(T) = .{};
            var lower: dsp.Oscillator(T) = .{};
            var square: dsp.Oscillator(T) = .{};
            var pick = dsp.Biquad(T).init(.lowpass, cutoff, 0.8, rate);
            var tight = dsp.Biquad(T).init(.highpass, 120.0, 0.707, rate);
            var cabinet_a = dsp.Biquad(T).init(.lowpass, self.cabinet, 0.707, rate);
            var cabinet_b = dsp.Biquad(T).init(.lowpass, self.cabinet * 1.2, 1.1, rate);
            var dc = dsp.Biquad(T).init(.highpass, 80.0, 0.707, rate);
            var presence = dsp.Biquad(T).init(.bandpass, self.presence_frequency, 0.9, rate);

            // The clipper leans to one side, which adds even harmonics; the offset is taken back out.
            const bias: T = 0.08;
            const rest = std.math.tanh(self.drive * bias);

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;

                const tone = 0.5 * (upper.saw(frequency * spread, rate) + lower.saw(frequency / spread, rate)) + 0.35 * square.square(frequency, rate);
                const level = dsp.rise(T, t, self.attack) * dsp.decay(T, t, fall);
                const into = tight.process(pick.process(tone)) * level;
                const clipped = std.math.tanh(self.drive * (into + bias)) - rest;
                const cabinet = cabinet_b.process(cabinet_a.process(dc.process(clipped)));
                const voiced = cabinet + self.presence * presence.process(cabinet);

                sample.* = volume * 0.6 * voiced * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }
    };
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const guitar: inner(f64) = .{};
    inline for (.{ 0.0, 1.0 }) |mute| {
        const samples = try guitar.render(allocator, 44100, 164.8, mute, 1.0, 9450, 9450);
        defer allocator.free(samples);

        try std.testing.expectEqual(@as(usize, 9450), samples.len);
        try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
        try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
        var peak: f64 = 0.0;
        for (samples) |s| peak = @max(peak, @abs(s));
        try std.testing.expect(peak > 0.2 and peak < 2.0);
    }
}

test "a muted note dies away faster than an open one" {
    const allocator = std.testing.allocator;
    const guitar: inner(f64) = .{};
    var energy: [2]f64 = .{ 0.0, 0.0 };
    inline for (.{ 0.0, 1.0 }, 0..) |mute, k| {
        const samples = try guitar.render(allocator, 44100, 82.4, mute, 1.0, 22050, 22050);
        defer allocator.free(samples);
        // Energy after 0.25 s.
        for (samples[11025..]) |s| energy[k] += s * s;
    }
    try std.testing.expect(energy[0] > 10.0 * energy[1]);
}

test "a cut note is the start of the full note" {
    const allocator = std.testing.allocator;
    const guitar: inner(f64) = .{};
    const full = try guitar.render(allocator, 44100, 123.5, 0.8, 0.9, 9450, 9450);
    defer allocator.free(full);
    const cut = try guitar.render(allocator, 44100, 123.5, 0.8, 0.9, 9450, 5000);
    defer allocator.free(cut);
    try std.testing.expectEqualSlices(f64, full[0..5000], cut);
}

test {
    std.testing.refAllDecls(@This());
}
