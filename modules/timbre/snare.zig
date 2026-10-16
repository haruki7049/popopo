//! Rock snare drum: two shell modes, a noise crack, and band-limited noise for the wires, driven.

const std = @import("std");
const dsp = @import("./dsp.zig");

/// Returns the snare type for samples of type `T`. The fields are the parameters of the timbre.
pub fn inner(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Lower shell mode, in Hz.
        shell_frequency: T = 182.0,
        /// Upper shell mode as a ratio of the lower one.
        shell_ratio: T = 1.62,
        /// Time constant of the shell, in seconds.
        shell_decay: T = 0.07,
        /// Level of the wires.
        wires: T = 0.85,
        /// Time constant of the wires, in seconds.
        wire_decay: T = 0.16,
        /// Level of the initial crack.
        crack: T = 0.6,
        /// Saturation of the whole hit.
        drive: T = 2.0,
        /// Fade of the timbre at the end of the note, in seconds.
        release: T = 0.008,

        /// Returns the first `frames` frames (mono) of a hit at `volume` that sounds `length`
        /// frames if nothing cuts it. The noise is drawn from `random`, so the caller decides the
        /// seed. Frames past `length` are silent. The caller owns the samples.
        pub fn render(self: Self, allocator: std.mem.Allocator, random: std.Random, sample_rate: u32, volume: T, length: usize, frames: usize) std.mem.Allocator.Error![]T {
            const samples = try allocator.alloc(T, frames);
            const rate: T = @floatFromInt(sample_rate);
            const release_frames = dsp.frames(T, self.release, sample_rate);

            var low: dsp.Oscillator(T) = .{};
            var high: dsp.Oscillator(T) = .{};
            var wire_band = dsp.Biquad(T).init(.bandpass, 3800.0, 0.55, rate);
            var wire_air = dsp.Biquad(T).init(.highpass, 1400.0, 0.707, rate);

            for (samples, 0..) |*sample, i| {
                const t = @as(T, @floatFromInt(i)) / rate;
                // The head is tighter for a moment after the hit, so the shell starts a little sharp.
                const bend = 1.0 + 0.12 * dsp.decay(T, t, 0.012);
                const shell = (0.7 * low.sine(self.shell_frequency * bend, rate) +
                    0.4 * high.sine(self.shell_frequency * self.shell_ratio * bend, rate)) * dsp.decay(T, t, self.shell_decay);

                const noise = random.float(T) * 2.0 - 1.0;
                const wires = (wire_band.process(noise) + 0.5 * wire_air.process(noise)) * dsp.decay(T, t, self.wire_decay);
                const crack = noise * dsp.decay(T, t, 0.005);

                const hit = shell + self.wires * wires + self.crack * crack;
                const onset = dsp.rise(T, t, 0.0004);
                sample.* = volume * dsp.saturate(T, hit * onset, self.drive) * dsp.tail(T, i, length, release_frames);
            }
            return samples;
        }
    };
}

test "render returns the frames asked for, starting and ending at zero" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(7);
    const snare: inner(f64) = .{};
    const samples = try snare.render(allocator, prng.random(), 44100, 1.0, 13230, 13230);
    defer allocator.free(samples);

    try std.testing.expectEqual(@as(usize, 13230), samples.len);
    try std.testing.expectEqual(@as(f64, 0.0), samples[0]);
    try std.testing.expectEqual(@as(f64, 0.0), samples[samples.len - 1]);
    for (samples) |s| try std.testing.expect(@abs(s) < 1.05);
}

test "the same seed gives the same hit, and a cut hit is the start of the full hit" {
    const allocator = std.testing.allocator;
    const snare: inner(f64) = .{};

    var a = std.Random.DefaultPrng.init(42);
    const full = try snare.render(allocator, a.random(), 44100, 0.9, 8000, 8000);
    defer allocator.free(full);
    var b = std.Random.DefaultPrng.init(42);
    const cut = try snare.render(allocator, b.random(), 44100, 0.9, 8000, 2500);
    defer allocator.free(cut);

    try std.testing.expectEqualSlices(f64, full[0..2500], cut);
}

test {
    std.testing.refAllDecls(@This());
}
