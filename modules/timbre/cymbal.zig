//! Cymbals: a bank of inharmonic square partials and noise, high-passed, with a decay. The closed
//! hi-hat, the open hi-hat and the crash are three settings of the same timbre.

const std = @import("std");
const dsp = @import("./dsp.zig");

/// Frequencies of the metallic partials, in Hz. Chosen to share no simple ratio.
const partials = [_]f64{ 296.3, 417.1, 538.9, 607.7, 741.9, 883.4 };

/// Returns the cymbal type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Time constant of the decay, in seconds.
        decay: T,
        /// Cutoff of the high-pass that leaves only the sizzle, in Hz.
        tone: T,
        /// Cutoff of the low-pass that softens the top, in Hz.
        brightness: T,
        /// Share of the metallic partials against the noise, from 0 to 1.
        metal: T,
        /// Rise at the start of the hit, in seconds.
        attack: T = 0.0005,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.006,

        /// A closed hi-hat: short and bright.
        pub const closed: Self = .{ .decay = 0.032, .tone = 7600.0, .brightness = 15000.0, .metal = 0.55 };
        /// An open hi-hat: the same metal, ringing.
        pub const open: Self = .{ .decay = 0.28, .tone = 6400.0, .brightness = 13500.0, .metal = 0.6 };
        /// A crash cymbal: wider, lower and long.
        pub const crash: Self = .{ .decay = 0.85, .tone = 3600.0, .brightness = 10500.0, .metal = 0.4, .attack = 0.002 };

        /// Returns the first `frames` frames (mono) of a hit at `volume` that sounds `length`
        /// frames if nothing cuts it. The noise is drawn from `random`, so the caller decides the
        /// seed. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            var oscillators = [_]dsp.Oscillator(T){.{}} ** partials.len;
            var high_a = dsp.Biquad(T).init(.highpass, self.tone, 0.707, rate);
            var high_b = dsp.Biquad(T).init(.highpass, self.tone, 0.707, rate);
            var top = dsp.Biquad(T).init(.lowpass, self.brightness, 0.707, rate);

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;

                var metal: T = 0.0;
                for (&oscillators, partials) |*oscillator, frequency| metal += oscillator.square(@floatCast(frequency), rate);
                metal /= @floatFromInt(partials.len);
                const noise = random.float(T) * 2.0 - 1.0;

                const sizzle = top.process(high_b.process(high_a.process(self.metal * metal + (1.0 - self.metal) * noise)));
                const envelope = dsp.rise(T, t, self.attack) * dsp.decay(T, t, self.decay);
                sample.* = volume * 2.5 * sizzle * envelope * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }
    };
}

test "every setting returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    const Cymbal = inner(f64);
    inline for (.{ Cymbal.closed, Cymbal.open, Cymbal.crash }) |cymbal| {
        var prng = std.Random.DefaultPrng.init(1);
        const samples = try cymbal.render(allocator, prng.random(), 44100, 1.0, 6000, 6000);
        defer allocator.free(samples);

        try std.testing.expectEqual(@as(usize, 6000), samples.len);
        try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
        try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
        for (samples) |s| try std.testing.expect(std.math.isFinite(s) and @abs(s) < 2.0);
    }
}

test "the open hi-hat rings longer than the closed one" {
    const allocator = std.testing.allocator;
    const Cymbal = inner(f64);
    var energy: [2]f64 = .{ 0.0, 0.0 };
    inline for (.{ Cymbal.closed, Cymbal.open }, 0..) |cymbal, k| {
        var prng = std.Random.DefaultPrng.init(3);
        const samples = try cymbal.render(allocator, prng.random(), 44100, 1.0, 22050, 22050);
        defer allocator.free(samples);
        // Energy after 0.1 s.
        for (samples[4410..]) |s| energy[k] += s * s;
    }
    try std.testing.expect(energy[1] > 100.0 * energy[0]);
}

test {
    std.testing.refAllDecls(@This());
}
