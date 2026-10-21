//! Acoustic guitar string: a plucked string built from decaying harmonics, whose upper harmonics
//! die faster, with a pluck-position comb, palm muting that shortens and darkens the note, and a
//! body resonance.

const std = @import("std");
const dsp = @import("./dsp.zig");

/// Returns the guitar type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Most harmonics of the string that are summed.
        const harmonics = 24;

        /// Where the string is plucked, as a fraction of its length from the bridge.
        pluck_position: T = 0.18,
        /// How fast the harmonics fall off with their number; higher is mellower.
        mellowness: T = 1.1,
        /// How much faster the upper harmonics die away; 0 makes them last as long as the root.
        damping: T = 0.35,
        /// Stretch of the harmonics from a stiff string, 0 for none.
        inharmonicity: T = 0.00008,
        /// Time constant of an open note's decay, in seconds.
        open_decay: T = 1.4,
        /// Time constant of a fully muted note's decay, in seconds.
        muted_decay: T = 0.09,
        /// Resonance of the body's air cavity, in Hz.
        body_frequency: T = 105.0,
        /// Boost of the body resonance, 0 for none.
        body: T = 0.6,
        /// Cutoff of the top of the sound, in Hz.
        brightness: T = 6500.0,
        /// Rise at the start of the note, in seconds.
        attack: T = 0.002,
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
            const fall = self.open_decay + (self.muted_decay - self.open_decay) * m;
            // Palm muting damps the upper harmonics more.
            const darkening = self.damping * (1.0 + 4.0 * m);

            // The partials: frequency, level and decay of each harmonic below the Nyquist frequency.
            var freq: [harmonics]T = undefined;
            var level: [harmonics]T = undefined;
            var tau: [harmonics]T = undefined;
            var count: usize = 0;
            var norm: T = 0.0;
            for (0..harmonics) |k| {
                const n: T = @floatFromInt(k + 1);
                const f = frequency * n * @sqrt(1.0 + self.inharmonicity * n * n);
                if (f >= 0.45 * rate) break;
                // Plucking at a fraction of the string leaves out the harmonics with a node there.
                const comb = @abs(@sin(std.math.pi * n * self.pluck_position));
                freq[count] = f;
                level[count] = comb / std.math.pow(T, n, self.mellowness);
                tau[count] = fall / (1.0 + darkening * (n - 1.0));
                norm += level[count];
                count += 1;
            }
            if (norm > 0.0) for (level[0..count]) |*l| {
                l.* /= norm;
            };

            var air = dsp.Biquad(T).init(.bandpass, self.body_frequency, 2.5, rate);
            var top = dsp.Biquad(T).init(.lowpass, self.brightness, 0.707, rate);
            var dc = dsp.Biquad(T).init(.highpass, 60.0, 0.707, rate);

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;

                var string: T = 0.0;
                for (0..count) |k| {
                    string += level[k] * @sin(2.0 * std.math.pi * freq[k] * t) * dsp.decay(T, t, tau[k]);
                }
                const plucked = dc.process(top.process(string)) * dsp.rise(T, t, self.attack);
                const voiced = plucked + self.body * air.process(plucked);

                sample.* = volume * 1.2 * voiced * dsp.tail(T, i, length, release_frames);
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
